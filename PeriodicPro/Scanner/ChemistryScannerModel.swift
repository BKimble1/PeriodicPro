import AVFoundation
import CoreGraphics
import Foundation
import Observation

/// Whether the camera may be used, and how to ask.
///
/// Asked for only when the learner opens Scan. Nothing about the camera
/// happens at launch, on the table, or anywhere else in the app.
enum CameraAuthorization {
    enum State: Equatable, Sendable {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    static func current() -> State {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    /// Presents the system prompt, once, and reports what the learner chose.
    static func request() async -> State {
        guard current() == .notDetermined else { return current() }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }
}

/// Drives the live chemistry scanner.
///
/// The camera produces recognized text; `ChemistryTextRecognizer` decides what
/// chemistry is in it; `ScanStabilizer` decides when the learner has actually
/// settled on something; and this resolves that — the elements first, because
/// all 118 are bundled and pointing at `Na` on a table means sodium, then
/// Elemora's own compound catalog, then the on-device cache, then PubChem,
/// then a clear not-found.
///
/// Camera frames never leave the device. What can reach PubChem is the
/// recognized text alone — a name, a formula or a structure identifier — and
/// only after the learner has held the phone on it long enough for the
/// scanner to be sure.
@MainActor
@Observable
final class ChemistryScannerModel {
    /// What the screen is doing.
    enum Phase: Equatable, Sendable {
        /// Permission has not been asked for yet.
        case idle
        case requestingPermission
        case denied(CameraAuthorization.State)
        /// This device cannot run live text recognition.
        case unsupported
        /// Camera running, nothing settled on.
        case scanning
        /// Settled, and being looked up.
        case resolving(ScanCandidate)
        /// Settled and found.
        case found(ScanCandidate, CompoundMatchCandidate)
        /// Settled on one of the 118, which is answered from the bundle.
        case foundElement(ScanCandidate, ChemicalElement)
        /// Settled, looked up, and nothing has it.
        case notFound(ScanCandidate)
        /// Settled, but the lookup could not be made.
        case failed(ScanCandidate, String)
    }

    private(set) var phase: Phase = .idle
    /// Everything readable in the current frame, for the chooser a page with
    /// several formulas on it needs.
    private(set) var visible: [ScanCandidate] = []
    /// How close the scanner is to accepting the thing it is looking at.
    private(set) var progress: Double = 0

    @ObservationIgnored private var stabilizer = ScanStabilizer()
    @ObservationIgnored private var resolution: Task<Void, Never>?
    /// What has already been looked up in this session, so pointing at the
    /// same bottle twice is one request rather than two.
    @ObservationIgnored private var resolved: [String: CompoundMatchCandidate] = [:]
    @ObservationIgnored private var missed: Set<String> = []


    init(
        phase: Phase = .idle
    ) {
        self.phase = phase
    }

    var isLive: Bool {
        if case .scanning = phase { return true }
        if case .resolving = phase { return true }
        return false
    }


    // MARK: - Lifecycle

    /// Asks for the camera, and only now.
    func start(isSupported: Bool) async {
        guard isSupported else {
            phase = .unsupported
            return
        }
        switch CameraAuthorization.current() {
        case .authorized:
            phase = .scanning
        case .notDetermined:
            phase = .requestingPermission
            let outcome = await CameraAuthorization.request()
            phase = outcome == .authorized ? .scanning : .denied(outcome)
        case .denied:
            phase = .denied(.denied)
        case .restricted:
            phase = .denied(.restricted)
        }
    }

    func stop() {
        resolution?.cancel()
        resolution = nil
        stabilizer.reset()
        visible = []
        progress = 0
        if isLive { phase = .scanning }
    }

    /// Back to looking, after a result.
    func resume() {
        resolution?.cancel()
        resolution = nil
        stabilizer.resume()
        progress = 0
        visible = []
        phase = .scanning
    }

    // MARK: - Frames

    /// One analysis of what the camera can see.
    ///
    /// `lines` is whatever the recognizer read this time, with a confidence
    /// and a normalized bounding box each. Everything chemical in them is
    /// extracted, the best is offered to the stabilizer, and a lookup starts
    /// only if the stabilizer says the learner has settled.
    func observe(
        lines: [(text: String, confidence: Double, bounds: CGRect)],
        catalog: ElementCatalog,
        store: CompoundStore,
        at now: ContinuousClock.Instant = .now
    ) {
        guard isLive else { return }
        var found: [ScanCandidate] = []
        var seen = Set<String>()
        for line in lines {
            for candidate in ChemistryTextRecognizer.candidates(
                in: line.text, confidence: line.confidence, bounds: line.bounds, catalog: catalog
            ) {
                // One entry per thing, not per spelling of it. A periodic
                // table cell arrives as several lines — the atomic number,
                // the symbol, the name, the mass — and `Na` and `Sodium` are
                // the same answer, so offering both is offering the same
                // choice twice.
                let key = candidate.element.map { "element:\($0)" } ?? candidate.text
                guard seen.insert(key).inserted else { continue }
                found.append(candidate)
            }
        }
        let ranked = found.sorted { lhs, rhs in
            if lhs.kindRank != rhs.kindRank { return lhs.kindRank < rhs.kindRank }
            return lhs.confidence > rhs.confidence
        }
        // Written only when it actually changed. VisionKit reports several
        // times a second and mostly reports the same thing; assigning an
        // identical list each time is an observation each time, which is a
        // rebuild of the overlay each time — the chooser popping in and out
        // and the guidance line flickering under a steady hand.
        if ranked != visible { visible = ranked }

        let best = visible.first { !missed.contains($0.id) } ?? visible.first
        guard let settled = stabilizer.observe(best, at: now) else {
            let reached = stabilizer.progress
            if reached != progress { progress = reached }
            return
        }
        progress = 1
        select(settled, store: store, catalog: catalog)
    }

    /// Looks up a candidate the learner picked from the ones on screen.
    func select(_ candidate: ScanCandidate, store: CompoundStore, catalog: ElementCatalog) {
        resolution?.cancel()
        Haptics.tap()

        // An element first, and without asking anybody. All 118 are in the
        // bundle, so pointing at a periodic table, a bottle or a textbook
        // margin is answered on the spot and offline. Before this, `Na` was
        // a formula like any other: a PubChem round trip that came back with
        // something that was not the sodium page, or with nothing at all.
        if let identified = element(for: candidate, catalog: catalog) {
            phase = .foundElement(candidate, identified)
            return
        }
        // Already known in this session: no request, no wait.
        if let known = resolved[candidate.id] {
            phase = .found(candidate, known)
            return
        }
        // Elemora's own catalog and the on-device cache, which are a
        // dictionary lookup and work with the phone in airplane mode.
        if let local = localMatch(candidate, store: store) {
            resolved[candidate.id] = local
            phase = .found(candidate, local)
            return
        }
        // Already looked for and not there. Asking again gets the same
        // answer a second later, which is how the not-found card came back
        // every time the learner resumed on the same thing.
        guard !missed.contains(candidate.id) else {
            phase = .notFound(candidate)
            return
        }
        guard store.isOnlineLookupEnabled else {
            phase = .notFound(candidate)
            return
        }

        phase = .resolving(candidate)
        resolution = Task { [weak self] in
            guard let self else { return }
            do {
                let hits = try await store.remoteSearch(query: candidate.query)
                guard !Task.isCancelled else { return }
                if let first = hits.first {
                    self.resolved[candidate.id] = first
                    self.phase = .found(candidate, first)
                } else {
                    self.missed.insert(candidate.id)
                    self.phase = .notFound(candidate)
                }
            } catch let error as PubChemError {
                guard !Task.isCancelled, error != .canceled else { return }
                if error == .notFound {
                    self.missed.insert(candidate.id)
                    self.phase = .notFound(candidate)
                } else {
                    self.phase = .failed(candidate, error.userMessage)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(candidate, PubChemError.malformed("").userMessage)
            }
        }
    }

    /// The element a settled candidate names, if it names one.
    ///
    /// Decided once, by the recognizer, when the line was read — a symbol
    /// spelled as the table spells it, or an element's name on a line of its
    /// own. Carried as an atomic number rather than as an object because a
    /// candidate travels through the stabilizer and back, and the number is
    /// the whole of what has to survive that trip. Deliberately not
    /// re-derived from the text here: that would apply the whole-line rule to
    /// a token and quietly undo it.
    func element(for candidate: ScanCandidate, catalog: ElementCatalog) -> ChemicalElement? {
        candidate.element.flatMap { catalog.element(atomicNumber: $0) }
    }

    /// What the device already knows, without a network.
    func localMatch(_ candidate: ScanCandidate, store: CompoundStore) -> CompoundMatchCandidate? {
        switch candidate.query {
        case .formula(let parsed, _):
            let hill = parsed.hill()
            return store.localCandidates(hillFormula: hill).first
        case .name(let name):
            return store.localSearch(name, limit: 1).first.map(CompoundMatchCandidate.init(local:))
        case .cid(let cid):
            return store.compound(cid: cid).map(CompoundMatchCandidate.init(local:))
        case .smiles, .inchi, .inchiKey, .empty:
            return nil
        }
    }

    /// Waits for a lookup in flight. For tests.
    func waitForPendingLookup() async {
        await resolution?.value
    }
}
