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

/// Where a formula search has got to.
///
/// A formula can match hundreds of records. Asking the index once and then
/// resolving properties a page at a time keeps both halves small: the cursor
/// carries the identifiers still to look at and the candidates already found,
/// so "Load more" costs one property request rather than a second search.
struct FormulaSearchCursor: Equatable, Sendable {
    let hillFormula: String
    /// CIDs the index returned that have not been resolved yet.
    var remaining: [Int]
    /// Candidates resolved so far, before ranking.
    var resolved: [CompoundMatchCandidate]

    var isExhausted: Bool { remaining.isEmpty }
}

/// One page of a formula search.
struct FormulaSearchPage: Equatable, Sendable {
    /// Ranked, and never truncated before ranking.
    let candidates: [CompoundMatchCandidate]
    let cursor: FormulaSearchCursor
    /// Whether the index has identifiers this page did not reach.
    let hasMore: Bool

    static let empty = FormulaSearchPage(
        candidates: [],
        cursor: FormulaSearchCursor(hillFormula: "", remaining: [], resolved: []),
        hasMore: false
    )

    /// The same page with its candidates replaced — used to attach the
    /// records the app already holds without re-running the search.
    func replacingCandidates(_ candidates: [CompoundMatchCandidate]) -> FormulaSearchPage {
        FormulaSearchPage(candidates: candidates, cursor: cursor, hasMore: hasMore)
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
    private let autocompleteBaseURL: URL
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
        let resolved = baseURL ?? Self.baseURL ?? URL(fileURLWithPath: "/")
        self.baseURL = resolved
        // The Auto-Complete Search Service is a sibling of PUG REST rather
        // than a path inside it: `…/rest/pug` and `…/rest/autocomplete`.
        self.autocompleteBaseURL = resolved.deletingLastPathComponent()
            .appendingPathComponent("autocomplete")
        self.maximumRetries = maximumRetries
        self.minimumGap = minimumGap
    }

    // MARK: - How much is asked for

    /// How many candidate CIDs a formula search asks the index for.
    ///
    /// The old number was thirty, and it was thirty *before* ranking, which
    /// meant a real compound could be hidden by thirty records nobody was
    /// looking for. PubChem's `MaxRecords` exists for exactly this, so it is
    /// used: two hundred and fifty identifiers, which is one small request.
    static let formulaCandidateLimit = 250

    /// How many CIDs are turned into full properties at once.
    ///
    /// Two hundred and fifty CIDs is one cheap request; two hundred and fifty
    /// property rows is not, and would arrive all at once as a single visible
    /// stall. Properties come back a page at a time instead.
    static let propertyBatchSize = 40

    /// How many results a first page shows.
    static let defaultPageSize = 16

    /// How many suggestions the name autocomplete asks for.
    static let suggestionLimit = 12

    // MARK: - Lookups

    /// Compounds matching a name, the best first, with their properties.
    func search(name: String, limit: Int = defaultPageSize) async throws -> [CompoundMatchCandidate] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPlausibleName(trimmed) else { throw PubChemError.invalidQuery }
        let cids = try await identifiers(path: "compound/name/\(Self.escaped(trimmed))/cids/JSON")
        return try await candidates(cids: Array(cids.prefix(limit)))
    }

    /// Name suggestions, for a learner who is still typing.
    ///
    /// PubChem's Auto-Complete Search Service, which answers on a prefix. It
    /// returns terms rather than records — selecting one performs the ordinary
    /// exact name lookup — so nothing here is presented as a compound the app
    /// has found.
    func suggestions(startingWith prefix: String, limit: Int = suggestionLimit) async throws -> [String] {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPlausibleName(trimmed) else { return [] }
        let data = try await get(
            base: autocompleteBaseURL,
            path: "compound/\(Self.escaped(trimmed))/JSON",
            query: "limit=\(max(1, min(limit, 50)))"
        )
        let response = try Self.decode(PubChemAutocompleteDTO.self, from: data)
        return response.dictionaryTerms.compound
    }

    /// Every compound with exactly this molecular formula.
    ///
    /// Which can be many, and that is the point: a formula does not name a
    /// compound. C₂H₆O is ethanol *and* dimethyl ether, and the app's job is
    /// to say so rather than to pick.
    ///
    /// The candidate identifiers are fetched in one request and the
    /// properties a page at a time, so a formula with two hundred matches
    /// costs one small request plus one page — not two hundred records
    /// downloaded to show ten.
    ///
    /// Nothing is filtered on charge here. The formula index returns ions as
    /// well as neutral molecules and both are real answers; `rank` puts the
    /// neutral ones first and the interface badges the rest.
    func search(hillFormula: String, limit: Int = defaultPageSize) async throws -> FormulaSearchPage {
        let cursor = try await formulaCandidates(hillFormula: hillFormula)
        return try await page(of: cursor, count: limit)
    }

    /// The identifiers for a formula, unresolved.
    ///
    /// Split out from the properties so the interface can say how many
    /// matches exist before it has downloaded any of them, and can ask for
    /// the next page without asking the index again.
    func formulaCandidates(hillFormula: String) async throws -> FormulaSearchCursor {
        let trimmed = hillFormula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPlausibleFormula(trimmed) else { throw PubChemError.invalidQuery }
        let cids = try await identifiers(
            path: "compound/fastformula/\(Self.escaped(trimmed))/cids/JSON",
            query: "MaxRecords=\(Self.formulaCandidateLimit)"
        )
        return FormulaSearchCursor(hillFormula: trimmed, remaining: cids, resolved: [])
    }

    /// Resolves enough of a cursor to show `count` more results.
    ///
    /// Properties arrive in batches, and a batch that yields nothing usable —
    /// every row a different formula, which the index does return — is
    /// followed by the next one rather than reported as the end.
    func page(of cursor: FormulaSearchCursor, count: Int = defaultPageSize) async throws -> FormulaSearchPage {
        var cursor = cursor
        var found: [CompoundMatchCandidate] = cursor.resolved
        let target = found.count + max(1, count)

        while found.count < target, !cursor.remaining.isEmpty {
            try Task.checkCancellation()
            let batch = Array(cursor.remaining.prefix(Self.propertyBatchSize))
            cursor.remaining.removeFirst(batch.count)
            let rows = try await candidates(cids: batch)
            // The formula index matches on composition, so isotopologues and
            // records written another way come back too. Only an exact Hill
            // formula is the compound that was asked for.
            found.append(contentsOf: rows.filter { $0.hillFormula == cursor.hillFormula })
        }

        cursor.resolved = found
        let ranked = Self.rank(found, forFormula: cursor.hillFormula)
        return FormulaSearchPage(
            candidates: Array(ranked.prefix(target)),
            cursor: cursor,
            hasMore: !cursor.remaining.isEmpty || ranked.count > target
        )
    }

    /// The compounds a structure identifier names.
    ///
    /// SMILES, InChI and InChIKey each have their own PubChem namespace, and
    /// each identifies a structure exactly — so these are lookups rather than
    /// searches, and an empty answer means PubChem has no record of that
    /// structure, not that the structure is wrong.
    func search(smiles: String, limit: Int = defaultPageSize) async throws -> [CompoundMatchCandidate] {
        try await structureSearch(namespace: "smiles", identifier: smiles, limit: limit)
    }

    func search(inchi: String, limit: Int = defaultPageSize) async throws -> [CompoundMatchCandidate] {
        // InChI strings contain slashes, so they go in the body rather than
        // the path — PUG REST accepts a POST with the same semantics.
        let trimmed = inchi.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("InChI="), trimmed.count <= 4_000 else { throw PubChemError.invalidQuery }
        let cids = try await identifiers(
            path: "compound/inchi/cids/JSON",
            body: "inchi=\(Self.formEscaped(trimmed))"
        )
        return try await candidates(cids: Array(cids.prefix(limit)))
    }

    func search(inchiKey: String, limit: Int = defaultPageSize) async throws -> [CompoundMatchCandidate] {
        try await structureSearch(namespace: "inchikey", identifier: inchiKey, limit: limit)
    }

    private func structureSearch(
        namespace: String, identifier: String, limit: Int
    ) async throws -> [CompoundMatchCandidate] {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...900).contains(trimmed.count) else { throw PubChemError.invalidQuery }
        let cids = try await identifiers(
            path: "compound/\(namespace)/\(Self.escaped(trimmed))/cids/JSON"
        )
        return try await candidates(cids: Array(cids.prefix(limit)))
    }

    /// Ranks what a formula search found.
    ///
    /// A lower CID is an older record, which is often but not always the
    /// better-known compound — and "often" is not a fact about chemistry. So
    /// CID order is only the tie-break, and it is the last one:
    ///
    /// 1. records the app already has, curated or cached;
    /// 2. neutral species before charged ones, because an unqualified formula
    ///    is conventionally the neutral compound — the charged ones stay in
    ///    the list, badged, rather than being filtered away;
    /// 3. records with a title, which is PubChem's own preferred name, before
    ///    ones that only have a systematic name;
    /// 4. then CID, so the order is stable.
    ///
    /// Nothing here selects. Ranking decides what is shown first; the list is
    /// still the list, and an ambiguous formula stays visibly ambiguous.
    static func rank(_ candidates: [CompoundMatchCandidate],
                     forFormula formula: String) -> [CompoundMatchCandidate] {
        candidates.sorted { lhs, rhs in
            if lhs.isLocal != rhs.isLocal { return lhs.isLocal }
            let lhsNeutral = lhs.charge == 0
            let rhsNeutral = rhs.charge == 0
            if lhsNeutral != rhsNeutral { return lhsNeutral }
            let lhsNamed = !lhs.name.hasPrefix("CID ")
            let rhsNamed = !rhs.name.hasPrefix("CID ")
            if lhsNamed != rhsNamed { return lhsNamed }
            return lhs.cid < rhs.cid
        }
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

    private func identifiers(path: String, query: String? = nil, body: String? = nil) async throws -> [Int] {
        let data = try await get(path: path, query: query, body: body)
        return try Self.decode(PubChemIdentifierListDTO.self, from: data).identifierList.cid
    }

    private func get(base: URL? = nil, path: String,
                     query: String? = nil, body: String? = nil) async throws -> Data {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            await pace()
            do {
                return try await performOnce(base: base ?? baseURL, path: path, query: query, body: body)
            } catch let error as PubChemError where error.isRetryable && attempt < maximumRetries {
                attempt += 1
                let backoff = Duration.milliseconds(600 * (1 << (attempt - 1)))
                Self.logger.info("PubChem retry \(attempt) after \(String(describing: error), privacy: .public)")
                try await Task.sleep(for: backoff)
            }
        }
    }

    private func performOnce(base: URL, path: String, query: String?, body: String?) async throws -> Data {
        guard var components = URLComponents(url: base.appendingPathComponent(path),
                                             resolvingAgainstBaseURL: false) else {
            throw PubChemError.invalidQuery
        }
        components.percentEncodedQuery = query
        guard let url = components.url else { throw PubChemError.invalidQuery }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }

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
    /// names use, between 2 and 120 characters, not a bare number (which is
    /// an atomic number, and never a compound search).
    ///
    /// Longer than it was, and with the rest of the punctuation real names
    /// carry: `N,N-dimethylformamide`, `(R)-(+)-limonene`, `beta-D-glucose`,
    /// `cis-1,2-dichloroethene`.
    static func isPlausibleName(_ text: String) -> Bool {
        guard (2...120).contains(text.count), Int(text) == nil else { return false }
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: " -,()[]{}'+.·:;%*/\\"))
        return text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// A Hill formula: capitalized symbols with optional counts, nothing else.
    ///
    /// Longer than it was, because the limit of forty characters excluded
    /// formulas that are perfectly ordinary once written out — a protein
    /// subunit's empirical formula runs past it easily. Still a hard bound:
    /// this string goes into a URL.
    static func isPlausibleFormula(_ text: String) -> Bool {
        guard (1...120).contains(text.count) else { return false }
        return text.range(of: "^([A-Z][a-z]?[0-9]*)+$", options: .regularExpression) != nil
    }

    static func escaped(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
    }

    /// For a form body, where `+` means a space and has to be escaped.
    static func formEscaped(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
