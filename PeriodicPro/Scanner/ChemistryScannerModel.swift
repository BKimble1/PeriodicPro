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
/// settled on something; and this resolves that to a compound — Elemora's own
/// catalog first, then the on-device cache, then PubChem, then a clear
/// not-found.
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
            ) where seen.insert(candidate.id).inserted {
                found.append(candidate)
            }
        }
        visible = found.sorted { lhs, rhs in
            if lhs.kindRank != rhs.kindRank { return lhs.kindRank < rhs.kindRank }
            return lhs.confidence > rhs.confidence
        }

        let best = visible.first { !missed.contains($0.id) } ?? visible.first
        guard let settled = stabilizer.observe(best, at: now) else {
            progress = stabilizer.progress
            return
        }
        progress = 1
        select(settled, store: store)
    }

    /// Looks up a candidate the learner picked from the ones on screen.
    func select(_ candidate: ScanCandidate, store: CompoundStore) {
        resolution?.cancel()
        Haptics.tap()

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
