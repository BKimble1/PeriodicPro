import Foundation
import OSLog

/// What can go wrong talking to PubChem, in terms a screen can explain.
enum PubChemError: Error, Hashable, Sendable {
    case offline
    case timeout
    case notFound
    case rateLimited
    case serverError(Int)
    case malformed(String)
    case invalidQuery
    case canceled

    /// One plain sentence for the interface.
    var userMessage: String {
        switch self {
        case .offline: return "You are offline. Saved and bundled compounds still work."
        case .timeout: return "PubChem took too long to answer. Try again in a moment."
        case .notFound: return "No known PubChem match found."
        case .rateLimited: return "PubChem is busy. Wait a moment and try again."
        case .serverError: return "PubChem could not answer right now. Try again later."
        case .malformed: return "PubChem sent a record the app could not read."
        case .invalidQuery: return "That does not look like a name or a formula."
        case .canceled: return "Search canceled."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .timeout, .rateLimited, .serverError: return true
        case .offline, .notFound, .malformed, .invalidQuery, .canceled: return false
        }
    }
}

/// One PubChem hit, before the full record is fetched: enough to list it,
/// decide whether it is the compound the learner meant, and show it offline.
struct CompoundMatchCandidate: Identifiable, Hashable, Sendable {
    let cid: Int
    let name: String
    let hillFormula: String
    let molarMass: Double?
    let iupacName: String?
    let charge: Int
    /// The bundled or cached record, when the app already has one.
    let local: ChemicalCompound?

    var id: String { "pubchem-\(cid)" }
    var isLocal: Bool { local != nil }
    var displayFormula: String { CompoundFormula.subscripted(local?.formula ?? hillFormula) }

    init(cid: Int, name: String, hillFormula: String, molarMass: Double?, iupacName: String?,
         charge: Int = 0, local: ChemicalCompound? = nil) {
        self.cid = cid
        self.name = name
        self.hillFormula = hillFormula
        self.molarMass = molarMass
        self.iupacName = iupacName
        self.charge = charge
        self.local = local
    }

    init(local compound: ChemicalCompound) {
        self.init(
            cid: compound.pubChemCID ?? -1,
            name: compound.preferredName,
            hillFormula: compound.hillFormula,
            molarMass: compound.molarMass,
            iupacName: compound.iupacName,
            charge: compound.charge,
            local: compound
        )
    }
}

/// The app's only connection to PubChem.
///
/// Direct PUG REST calls over `URLSession`, no key, no backend. Requests are
/// short and user-driven: a name, a formula, one record. Nothing here crawls.
/// The actor serializes calls and keeps them at least `minimumGap` apart,
/// which stays comfortably inside PubChem's published limit of five a
/// second; on a 429 or a 5xx it backs off and retries twice, then gives up
/// with an error the screen can explain. Every request checks for
/// cancellation, so a stale search stops as soon as it is superseded.
actor PubChemClient {
    static let baseURL = URL(string: "https://pubchem.ncbi.nlm.nih.gov/rest/pug")
    static let userAgent = "Elemora/1.0 (educational periodic table app)"

    private let transport: NetworkTransport
    private let baseURL: URL
    private let maximumRetries: Int
    private let minimumGap: Duration
    private var lastRequestFinished: ContinuousClock.Instant?
    private static let logger = Logger(subsystem: "com.periodicpro.app", category: "pubchem")

    init(
        transport: NetworkTransport = URLSessionTransport(),
        baseURL: URL? = nil,
        maximumRetries: Int = 2,
        minimumGap: Duration = .milliseconds(220)
    ) {
        self.transport = transport
        self.baseURL = baseURL ?? Self.baseURL ?? URL(fileURLWithPath: "/")
        self.maximumRetries = maximumRetries
        self.minimumGap = minimumGap
    }

    // MARK: - Lookups

    /// Compounds matching a name, the best first, with their properties.
    func search(name: String, limit: Int = 6) async throws -> [CompoundMatchCandidate] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPlausibleName(trimmed) else { throw PubChemError.invalidQuery }
        let cids = try await identifiers(path: "compound/name/\(Self.escaped(trimmed))/cids/JSON")
        return try await candidates(cids: Array(cids.prefix(limit)))
    }

    /// Every compound with exactly this molecular formula — which can be many,
    /// and that is the point: a formula does not name a compound. Results are
    /// filtered to neutral species whose formula is exactly the one asked
    /// for, because the formula index also returns ions and isotopologues.
    func search(hillFormula: String, limit: Int = 10) async throws -> [CompoundMatchCandidate] {
        let trimmed = hillFormula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPlausibleFormula(trimmed) else { throw PubChemError.invalidQuery }
        let cids = try await identifiers(path: "compound/fastformula/\(Self.escaped(trimmed))/cids/JSON")
        // Lower CIDs are the older, better-known records; PubChem returns
        // them roughly in that order, and thirty is plenty to find the
        // common isomers.
        let candidates = try await candidates(cids: Array(cids.prefix(30)))
        return Array(candidates.filter { $0.hillFormula == trimmed && $0.charge == 0 }.prefix(limit))
    }

    /// The standard properties for a set of CIDs.
    func candidates(cids: [Int]) async throws -> [CompoundMatchCandidate] {
        guard !cids.isEmpty else { return [] }
        let list = cids.map(String.init).joined(separator: ",")
        let data = try await get(path: "compound/cid/\(list)/property/"
                                 + "MolecularFormula,MolecularWeight,IUPACName,Title,Charge/JSON")
        let table = try Self.decode(PubChemPropertyTableDTO.self, from: data)
        return table.propertyTable.properties.map { row in
            CompoundMatchCandidate(
                cid: row.cid,
                name: row.title ?? row.iupacName ?? "CID \(row.cid)",
                hillFormula: row.molecularFormula ?? "",
                molarMass: row.molecularWeight,
                iupacName: row.iupacName,
                charge: row.charge ?? 0
            )
        }
    }

    /// The full compound: properties plus the 3D conformer, or the 2D record
    /// when PubChem has no conformer for it.
    func compound(cid: Int) async throws -> ChemicalCompound {
        let summary = try await candidates(cids: [cid]).first
        guard let summary else { throw PubChemError.notFound }
        let structure = try await structure(cid: cid)
        return Self.assemble(summary: summary, structure: structure)
    }

    /// 3D when it exists, otherwise the authentic 2D connectivity — never a
    /// fabricated third thing.
    func structure(cid: Int) async throws -> CompoundStructure? {
        do {
            let data = try await get(path: "compound/cid/\(cid)/JSON", query: "record_type=3d")
            let response = try Self.decode(PubChemRecordResponseDTO.self, from: data)
            if let structure = response.compounds.first?.compoundStructure(), structure.is3D {
                return structure
            }
        } catch PubChemError.notFound {
            // No conformer for this record: fall through to 2D.
        }
        let data = try await get(path: "compound/cid/\(cid)/JSON")
        let response = try Self.decode(PubChemRecordResponseDTO.self, from: data)
        return response.compounds.first?.compoundStructure()
    }

    static func assemble(summary: CompoundMatchCandidate, structure: CompoundStructure?) -> ChemicalCompound {
        let composition = structure?.composition ?? CompoundFormula.parse(summary.hillFormula) ?? [:]
        let displayFormula = composition.isEmpty
            ? summary.hillFormula
            : CompoundFormula.display(composition)
        return ChemicalCompound(
            id: "pubchem-\(summary.cid)",
            pubChemCID: summary.cid,
            preferredName: summary.name,
            formula: displayFormula,
            hillFormula: summary.hillFormula,
            iupacName: summary.iupacName,
            molarMass: summary.molarMass,
            canonicalSMILES: nil,
            charge: summary.charge,
            // PubChem does not say whether a compound is ionic or an acid, and
            // the app does not guess.
            bondingClass: .unknown,
            tags: [],
            alternateNames: [],
            summary: nil,
            classificationSource: nil,
            dataSource: .pubChem,
            isLocalCurated: false,
            lastUpdated: CompoundFormula.today(),
            structure: structure
        )
    }

    // MARK: - Transport

    private func identifiers(path: String) async throws -> [Int] {
        let data = try await get(path: path)
        return try Self.decode(PubChemIdentifierListDTO.self, from: data).identifierList.cid
    }

    private func get(path: String, query: String? = nil) async throws -> Data {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            await pace()
            do {
                return try await performOnce(path: path, query: query)
            } catch let error as PubChemError where error.isRetryable && attempt < maximumRetries {
                attempt += 1
                let backoff = Duration.milliseconds(600 * (1 << (attempt - 1)))
                Self.logger.info("PubChem retry \(attempt) after \(String(describing: error), privacy: .public)")
                try await Task.sleep(for: backoff)
            }
        }
    }

    private func performOnce(path: String, query: String?) async throws -> Data {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                             resolvingAgainstBaseURL: false) else {
            throw PubChemError.invalidQuery
        }
        components.percentEncodedQuery = query
        guard let url = components.url else { throw PubChemError.invalidQuery }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.perform(request)
        } catch is CancellationError {
            throw PubChemError.canceled
        } catch let error as URLError {
            throw Self.map(error)
        } catch let error as PubChemError {
            throw error
        } catch {
            throw PubChemError.malformed(String(describing: error))
        }
        lastRequestFinished = .now

        switch response.statusCode {
        case 200: return data
        case 404: throw PubChemError.notFound
        case 400: throw PubChemError.invalidQuery
        case 429, 503: throw PubChemError.rateLimited
        case 500...599: throw PubChemError.serverError(response.statusCode)
        default:
            // PubChem wraps errors in a Fault envelope; read its code when
            // the status alone is not conclusive.
            if let fault = try? JSONDecoder().decode(PubChemFaultDTO.self, from: data) {
                throw Self.map(faultCode: fault.fault.code, status: response.statusCode)
            }
            throw PubChemError.serverError(response.statusCode)
        }
    }

    /// Keeps consecutive requests `minimumGap` apart.
    private func pace() async {
        guard let last = lastRequestFinished else { return }
        let elapsed = ContinuousClock.now - last
        if elapsed < minimumGap {
            try? await Task.sleep(for: minimumGap - elapsed)
        }
    }

    // MARK: - Mapping

    static func map(_ error: URLError) -> PubChemError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timeout
        case URLError.Code.cancelled:
            return .canceled
        default:
            return .serverError(error.errorCode)
        }
    }

    static func map(faultCode: String, status: Int) -> PubChemError {
        if faultCode.contains("NotFound") { return .notFound }
        if faultCode.contains("ServerBusy") { return .rateLimited }
        if faultCode.contains("Timeout") { return .timeout }
        if faultCode.contains("BadRequest") { return .invalidQuery }
        return .serverError(status)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            if let fault = try? JSONDecoder().decode(PubChemFaultDTO.self, from: data) {
                throw map(faultCode: fault.fault.code, status: 200)
            }
            throw PubChemError.malformed(String(describing: error))
        }
    }

    // MARK: - Query hygiene

    /// A name worth sending: letters, digits and the punctuation chemical
    /// names use, between 2 and 80 characters, not a bare number (which is
    /// an atomic number, and never a compound search).
    static func isPlausibleName(_ text: String) -> Bool {
        guard (2...80).contains(text.count), Int(text) == nil else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -,()[]'+"))
        return text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// A Hill formula: capitalized symbols with optional counts, nothing else.
    static func isPlausibleFormula(_ text: String) -> Bool {
        guard (1...40).contains(text.count) else { return false }
        return text.range(of: "^([A-Z][a-z]?[0-9]*)+$", options: .regularExpression) != nil
    }

    static func escaped(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
    }
}
