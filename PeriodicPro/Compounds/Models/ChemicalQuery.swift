import Foundation

/// What a learner typed into a chemistry search, once it has been recognized.
///
/// Elemora's compound search takes one field and accepts every identifier a
/// chemistry learner is likely to be holding: a name off a bottle, a formula
/// off a worksheet, a CID from a PubChem page, or a SMILES / InChI /
/// InChIKey string pasted out of a paper. Each of those reaches PubChem
/// through a different endpoint, so recognizing which one is in the field is
/// the whole job.
enum ChemicalQuery: Hashable, Sendable {
    /// Nothing worth searching for.
    case empty
    /// A common name, an IUPAC name or a synonym.
    case name(String)
    /// A molecular formula, read.
    case formula(ParsedFormula, text: String)
    /// A PubChem compound identifier.
    case cid(Int)
    /// A SMILES string.
    case smiles(String)
    /// An InChI string, which always begins `InChI=`.
    case inchi(String)
    /// A 27-character InChIKey.
    case inchiKey(String)

    /// What to call this kind of query on screen.
    var kindDescription: String {
        switch self {
        case .empty: return "Nothing"
        case .name: return "Name"
        case .formula: return "Molecular formula"
        case .cid: return "PubChem CID"
        case .smiles: return "SMILES"
        case .inchi: return "InChI"
        case .inchiKey: return "InChIKey"
        }
    }

    var isEmpty: Bool { self == .empty }

    /// Whether name suggestions are worth fetching for this query. A formula,
    /// an identifier or a structure string has an exact answer; only a name
    /// has near ones.
    var acceptsSuggestions: Bool {
        if case .name = self { return true }
        return false
    }
}

/// Decides which kind of identifier a piece of text is.
///
/// The order is deliberate and each step is exclusive, so a string is never
/// two things at once:
///
/// 1. `InChI=…` — the prefix is reserved and unambiguous.
/// 2. An InChIKey — a fixed 14-10-1 block of capitals, which nothing else is.
/// 3. `CID 2244`, `cid:2244`, or a bare number. Build's search is
///    compound-only, so a bare positive integer there is a CID. (The Table
///    screen's search keeps its own meaning for a bare number, which is an
///    atomic number, and never asks this.)
/// 4. An oxidation state in parentheses — `Fe(III)` — which is a name.
/// 5. A molecular formula, if it parses completely.
/// 6. A SMILES string, if it uses the syntax only SMILES has.
/// 7. Otherwise a name.
///
/// Step 5 before step 6 is a choice with one visible consequence: `CO` is
/// both carbon monoxide's formula and methanol's SMILES, and in a periodic
/// table app it is carbon monoxide.
enum ChemicalQueryClassifier {
    /// Longer than this is not a query.
    static let maximumLength = 900

    /// - Parameter allowsBareNumber: whether a bare positive integer is a
    ///   CID. True in a search field, where somebody who typed 2244 meant a
    ///   CID; false for the camera, where a number on a page is a page
    ///   number, a figure number or a coefficient far more often than it is a
    ///   compound identifier. `CID 2244` is recognized either way.
    static func classify(
        _ raw: String,
        catalog: ElementCatalog = .bundledOrEmpty,
        allowsBareNumber: Bool = true
    ) -> ChemicalQuery {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maximumLength else { return .empty }

        if isInChI(text) { return .inchi(text) }
        if isInChIKey(text) { return .inchiKey(text.uppercased()) }
        if let cid = cid(in: text, allowsBareNumber: allowsBareNumber) { return .cid(cid) }
        // `Fe(III)` is a name for an oxidation state. It is neither a formula
        // nor a structure string, and both of the readers below would
        // otherwise take it for one.
        if looksLikeOxidationState(text) { return .name(text) }
        if let formula = ChemicalFormulaParser.parse(text, catalog: catalog) {
            return .formula(formula, text: text)
        }
        if isSMILES(text) { return .smiles(text) }
        return .name(text)
    }

    // MARK: - InChI

    static func isInChI(_ text: String) -> Bool {
        text.hasPrefix("InChI=") && text.count > "InChI=".count
    }

    /// Fourteen capitals, ten capitals, one capital — `BSYNRYMUTXBXSQ-UHFFFAOYSA-N`.
    static func isInChIKey(_ text: String) -> Bool {
        text.range(of: "^[A-Za-z]{14}-[A-Za-z]{10}-[A-Za-z]$", options: .regularExpression) != nil
    }

    // MARK: - CID

    /// `2244`, `CID 2244`, `cid:2244`, `CID2244`.
    static func cid(in text: String, allowsBareNumber: Bool = true) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if allowsBareNumber, let bare = Int(trimmed), bare > 0 { return bare }
        if Int(trimmed) != nil { return nil }
        guard let match = trimmed.range(
            of: "^[Cc][Ii][Dd][ :=#]*([0-9]{1,9})$", options: .regularExpression
        ), match.lowerBound == trimmed.startIndex else { return nil }
        let digits = trimmed.drop { !$0.isNumber }
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    // MARK: - SMILES

    /// The characters and shapes that only SMILES has.
    ///
    /// A formula has already been ruled out by the time this is asked, so this
    /// does not have to separate `CO` from `CO` — it has to separate a
    /// structure string from an English word. Bond symbols, ring-closure
    /// digits after a bracket atom, aromatic lowercase atoms and square
    /// bracket atoms are all things a name never contains.
    static func isSMILES(_ text: String) -> Bool {
        guard (1...800).contains(text.count) else { return false }
        // A name can contain spaces and commas; a SMILES string cannot.
        guard !text.contains(" "), !text.contains(",") else { return false }
        let allowed = CharacterSet(charactersIn:
            "BCNOPSFIHKclnorsibaefgmtuphdyzABCDEFGHIKLMNOPRSTUVWXYZ0123456789"
            + "()[]=#$:/\\@+-.%*")
        guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let structural = CharacterSet(charactersIn: "=#$[]()/\\@%")
        if text.unicodeScalars.contains(where: { structural.contains($0) }) { return true }
        // Aromatic atoms are written lowercase, and a lowercase letter that
        // cannot continue an element symbol is either that or a word.
        let aromatic: Set<Character> = ["b", "c", "n", "o", "p", "s"]
        return text.contains { aromatic.contains($0) }
            && text.contains { $0.isUppercase || aromatic.contains($0) }
            && !text.contains { $0.isLowercase && !aromatic.contains($0) }
    }

    // MARK: - Oxidation states

    /// `Fe(III)`, `Cu(II)`, `Mn(VII)` — a name for an oxidation state, not a
    /// formula.
    ///
    /// Without this the parser would happily read the Roman numerals as
    /// iodine and vanadium and hand back a real but entirely unrelated
    /// compound. The letters of a Roman numeral are all element symbols, so
    /// the only way to tell is the shape.
    static func looksLikeOxidationState(_ text: String) -> Bool {
        text.range(of: "\\((?:I{1,3}|IV|VI{0,3}|IX|XI{0,2})\\)", options: .regularExpression) != nil
    }
}
