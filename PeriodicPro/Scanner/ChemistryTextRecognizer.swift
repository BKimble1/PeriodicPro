import CoreGraphics
import Foundation

/// Turns a line of recognized text into the chemistry that is in it.
///
/// This is the half of the scanner that has nothing to do with cameras, and
/// it is where the accuracy lives. Vision hands over a string and a
/// confidence; everything about deciding whether that string is a formula, a
/// name or a structure identifier — and about the handful of character
/// confusions that chemistry can actually resolve — happens here, where it is
/// a pure function and can be tested against fixtures.
enum ChemistryTextRecognizer {
    /// How many substitution variants a single token may be tried as.
    ///
    /// A token with six ambiguous characters has sixty-four readings, and
    /// trying all of them for every token of every frame is how a scanner
    /// becomes a hand warmer. Beyond this the token is read as it was seen.
    static let maximumVariants = 32

    /// The shortest run of letters worth treating as a name.
    static let minimumNameLength = 4

    /// Everything chemical in one line of recognized text, best first.
    static func candidates(
        in line: String,
        confidence: Double = 1,
        bounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        catalog: ElementCatalog = .bundledOrEmpty
    ) -> [ScanCandidate] {
        let cleaned = normalize(line)
        guard !cleaned.isEmpty else { return [] }

        var found: [ScanCandidate] = []
        var seen = Set<String>()

        @discardableResult
        func offer(
            _ text: String,
            raw: String,
            allowsSpacedFormula: Bool = false,
            allowsElementName: Bool = false
        ) -> Bool {
            // A bare number on a page is a page number far more often than it
            // is a PubChem CID, so the camera does not read one as an
            // identifier. "CID 2244" is still recognized.
            let query = ChemicalQueryClassifier.classify(text, catalog: catalog, allowsBareNumber: false)
            guard !query.isEmpty else { return false }
            let named = namedElement(text, catalog: catalog, allowsName: allowsElementName)
            // A name has to look like a chemical name before it is offered —
            // unless it is an element's name, which is one by definition.
            if case .name = query, named == nil,
               !looksLikeChemicalName(text, elements: catalog) { return false }
            // A formula never contains a space. Without this, a line reading
            // "H2O NaCl" would be read as one compound, because the parser
            // strips whitespace before it does anything else.
            if case .formula = query, !allowsSpacedFormula,
               text.contains(where: { $0.isWhitespace }) { return false }
            let candidate = ScanCandidate(
                text: text, raw: raw, query: query, confidence: confidence, bounds: bounds,
                element: named?.atomicNumber
            )
            // Deduplicated by the text, not by the candidate's identity. The
            // whole line and one of its tokens are often the same string, and
            // "Chlorine" read as an element and read as a chemical name are
            // two identities for one word — which would put the same thing on
            // the chooser twice, once with the right answer and once with a
            // PubChem round trip. The line is offered first, so the reading
            // that wins is the more specific one.
            guard seen.insert(candidate.text).inserted else { return false }
            found.append(candidate)
            return true
        }

        // The whole line first: a name is usually the line, not a word in it,
        // and an element's name is only its name when it is the whole line.
        offer(cleaned, raw: line, allowsElementName: true)

        // Then each token, which is where a formula lives.
        var words: [String] = []
        for token in tokens(in: cleaned) {
            let text = repaired(token, catalog: catalog) ?? token
            let isIdentifier = offer(text, raw: token)
            if !isIdentifier || isWord(text) { words.append(token) }
        }

        // And the words between the formulas, as a name: "Sulfuric acid
        // H2SO4" is one line carrying both, and neither half is the line.
        if !words.isEmpty, words.count < tokens(in: cleaned).count {
            offer(words.joined(separator: " "), raw: words.joined(separator: " "))
        }

        return found.sorted { lhs, rhs in
            if lhs.kindRank != rhs.kindRank { return lhs.kindRank < rhs.kindRank }
            return lhs.text.count > rhs.text.count
        }
    }

    // MARK: - Elements

    /// The element a piece of read text names exactly, or nil.
    ///
    /// Two spellings count and nothing else: the symbol exactly as the table
    /// prints it, and the element's full name in any case.
    ///
    /// **Case matters for a symbol.** `AT`, `IN`, `NO`, `BE`, `AS`, `AM` and
    /// `HE` are ordinary English words in capitals, and reading them as
    /// astatine, indium, nobelium, beryllium, arsenic, americium and helium
    /// would turn a page of prose into a stream of confident wrong answers.
    /// A periodic table, a bottle and a textbook all print `Na`, so requiring
    /// `Na` costs nothing and rules all of that out.
    static func element(in text: String, catalog: ElementCatalog = .bundledOrEmpty) -> ChemicalElement? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let bySymbol = catalog.element(symbol: trimmed), bySymbol.symbol == trimmed {
            return bySymbol
        }
        return catalog.element(name: trimmed)
    }

    /// The element a candidate should be resolved as.
    ///
    /// A **symbol** counts wherever it is read: `Na` is already offered as a
    /// formula, and saying it is sodium only decides which answer it
    /// deserves. A **name** counts only when it is the whole line, because
    /// lead, iron, gold, silver and tin are English words — inside a sentence
    /// the word is what was meant far more often than the element, and the
    /// line a camera hands over for a table cell is the cell.
    static func namedElement(
        _ text: String, catalog: ElementCatalog, allowsName: Bool
    ) -> ChemicalElement? {
        guard let found = element(in: text, catalog: catalog) else { return nil }
        if found.symbol == text.trimmingCharacters(in: .whitespacesAndNewlines) { return found }
        return allowsName ? found : nil
    }

    // MARK: - Normalizing

    /// Folds what a page prints into what a parser reads.
    ///
    /// Subscripts and superscripts survive as themselves here rather than
    /// being flattened, because `ChemicalFormulaParser` distinguishes them —
    /// a subscript is a count and a superscript is a charge, and collapsing
    /// both to a digit would turn SO₄²⁻ into SO42.
    static func normalize(_ text: String) -> String {
        var output = ""
        for character in text {
            if let replacement = confusions[character] {
                output.append(replacement)
            } else if character == "\u{00A0}" {
                output.append(" ")
            } else {
                output.append(character)
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Characters that are one thing on a page and another in Unicode.
    ///
    /// Only the unambiguous ones: a typographic minus really is a minus, and a
    /// full-width plus really is a plus. The genuinely ambiguous glyphs — zero
    /// against O, one against l against I — are not here, because which they
    /// are depends on the chemistry around them. Those are `repaired(_:)`.
    private static let confusions: [Character: Character] = [
        "\u{2212}": "-", "\u{2013}": "-", "\u{2014}": "-",
        "\u{FF0B}": "+", "\u{2010}": "-", "\u{2011}": "-",
        "\u{00B7}": "·", "\u{2022}": "·", "\u{2219}": "·", "\u{22C5}": "·",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{2018}": "'", "\u{2019}": "'",
    ]

    /// Whether a token is a word rather than a chemical identifier.
    static func isWord(_ token: String) -> Bool {
        !token.contains(where: { $0.isNumber })
            && token.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" }
            && token.dropFirst().contains(where: { $0.isLowercase })
    }

    /// Splits a line into the runs that could each be a formula.
    static func tokens(in line: String) -> [String] {
        line
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    // MARK: - Repairing what OCR cannot tell apart

    /// The confusions worth attempting, and what each could be instead.
    ///
    /// Every one of these is a pair of glyphs that look alike in print. The
    /// substitution is only kept if it turns the token into something that
    /// parses — so `H20` becomes H₂O because "H2O" is a formula and "H20" is
    /// not, while `C60` stays C₆₀ because it already is one.
    private static let ambiguous: [Character: [Character]] = [
        "0": ["O"],
        "O": ["0"],
        // Ordered by which reading chemistry is more likely to have meant:
        // a capital I between letters is nearly always a lowercase L
        // continuing a symbol — NaCI is sodium chloride, not sodium carbide.
        "l": ["I", "1"],
        "1": ["l", "I"],
        "I": ["l", "1"],
        "5": ["S"],
        "S": ["5"],
        "8": ["B"],
        "B": ["8"],
        "6": ["G", "b"],
        "2": ["Z"],
    ]

    /// The reading of a token that names a compound, when the reading as seen
    /// does not.
    ///
    /// "Does it parse" is not enough to decide this, and assuming it was is
    /// the bug this replaces. `H20` parses perfectly well — as twenty
    /// hydrogens — so a repair guarded on parsing never fired for the single
    /// commonest OCR error in chemistry. Meanwhile `C60` also parses, and is
    /// buckminsterfullerene, and must not be turned into anything else.
    ///
    /// What separates them is not syntax, it is whether the reading names
    /// something. A substitution is taken only when it produces a formula the
    /// app has a compound for and the original does not — so `H20` becomes
    /// water, `C02` becomes carbon dioxide, `NaCI` becomes sodium chloride,
    /// and `C60` is left exactly as it was read. Nothing is invented: the
    /// alternative reading has to correspond to a record.
    ///
    /// Bounded twice over: only tokens short enough to be a formula are tried,
    /// and only `maximumVariants` readings of each.
    static func repaired(
        _ token: String,
        catalog: ElementCatalog = .bundledOrEmpty,
        compounds: CompoundCatalog = .bundled
    ) -> String? {
        guard (2...24).contains(token.count) else { return nil }
        // A formula on a page starts with an element symbol. Without this, a
        // year reads as a coefficient and a formula: "2026" becomes 2 O26.
        guard token.first?.isUppercase == true else { return nil }

        let asRead = ChemicalFormulaParser.parse(token, catalog: catalog)
        // Already names something: never second-guess a reading that works.
        if let asRead, namesACompound(asRead, catalog: catalog, compounds: compounds) { return nil }

        let characters = Array(token)
        let positions = characters.indices.filter { ambiguous[characters[$0]] != nil }
        guard !positions.isEmpty else { return nil }

        var variants: [[Character]] = [characters]
        for position in positions {
            guard variants.count < maximumVariants else { break }
            var grown = variants
            for replacement in ambiguous[characters[position]] ?? [] {
                guard grown.count < maximumVariants else { break }
                for variant in variants {
                    guard grown.count < maximumVariants else { break }
                    var candidate = variant
                    candidate[position] = replacement
                    grown.append(candidate)
                }
            }
            variants = grown
        }

        var firstParsing: String?
        for variant in variants.dropFirst() {
            guard variant.first?.isUppercase == true else { continue }
            let text = String(variant)
            guard let parsed = ChemicalFormulaParser.parse(text, catalog: catalog) else { continue }
            if namesACompound(parsed, catalog: catalog, compounds: compounds) { return text }
            if firstParsing == nil { firstParsing = text }
        }
        // Nothing matched a record. A reading that at least parses beats one
        // that does not; a token that already parsed is left alone.
        return asRead == nil ? firstParsing : nil
    }

    /// Whether a composition is one the app has a compound for.
    private static func namesACompound(
        _ parsed: ParsedFormula, catalog: ElementCatalog, compounds: CompoundCatalog
    ) -> Bool {
        !compounds.compounds(hillFormula: parsed.hill(catalog: catalog)).isEmpty
    }

    // MARK: - Names

    /// Whether a run of words is shaped like a chemical name.
    ///
    /// The scanner reads whatever is pointed at, and a page of prose is mostly
    /// not chemistry. A formula is distinctive enough to be taken at face
    /// value; a name is not, so a name has to look like one before it is
    /// offered — otherwise "provide", "different" and "state" all become
    /// compound lookups.
    ///
    /// Four signals settle it on their own: the app's own catalog, which knows
    /// the common names that follow no rule; a locant, which ordinary words do
    /// not carry; an element name followed by an anion ending, which is how
    /// every binary salt is written; and a short list of names chemistry uses
    /// that no rule would find. Failing those, it takes both a nomenclature
    /// prefix and a nomenclature suffix — "eth" and "ol", "carb" and "ide" —
    /// because either one alone is a word ending, and both together is a name.
    static func looksLikeChemicalName(
        _ text: String,
        catalog: CompoundCatalog? = nil,
        elements: ElementCatalog = .bundledOrEmpty
    ) -> Bool {
        let lowered = text.lowercased()
        let letters = lowered.filter { $0.isLetter }
        guard letters.count >= minimumNameLength, lowered.count <= 120 else { return false }
        // No more than a short phrase: a sentence is not a compound name.
        let words = lowered.split(separator: " ").map(String.init)
        guard (1...6).contains(words.count) else { return false }

        if let catalog, !catalog.search(text, limit: 1).isEmpty { return true }
        if commonNames.contains(lowered) { return true }
        // "2-propanol", "1,3-butadiene", "N,N-dimethylformamide".
        if lowered.range(of: "^[0-9]+([,'-][0-9]+)*-", options: .regularExpression) != nil { return true }
        if lowered.range(of: "^[nopsr](,[nopsr])*-", options: .regularExpression) != nil { return true }
        if isElementAndAnion(words, elements: elements) { return true }

        if matchesSystematicNomenclature(lowered) { return true }

        let hasPrefix = namePrefixes.contains { lowered.hasPrefix($0) }
        let hasSuffix = nameSuffixes.contains { lowered.hasSuffix($0) }
        return hasPrefix && hasSuffix
    }

    /// A systematic carbon-chain name, by the rule that builds one: a chain
    /// stem, a saturation infix, and an ending.
    ///
    /// This exists because the prefix-and-suffix pair below cannot express it
    /// safely. "dec" is a chain stem and "ide" is an ending, but "decide" is
    /// an English word; requiring the -an-/-en-/-yn- in between is what tells
    /// "decane" from "decide" and "nonanone" from "none".
    static func matchesSystematicNomenclature(_ lowered: String) -> Bool {
        let pattern = "^(meth|eth|prop|but|pent|hex|hept|oct|non|dec|undec|dodec)"
            + "(an|en|yn)(e|ol|al|oic acid|oic|oate|one|amine|amide|edione|ediol)$"
        return lowered.range(of: pattern, options: .regularExpression) != nil
    }

    /// Stems chemistry uses at the start of a name.
    ///
    /// Every one of them had to fail a simple test: no ordinary English word
    /// begins with it and also ends with one of the endings below. That is why
    /// "pro", "con" and "out" are absent although they open plenty of chemical
    /// names — with "-ide" and "-ate" after them they would turn "provide",
    /// "control" and "outside" into compound lookups.
    private static let namePrefixes: [String] = [
        "acet", "acryl", "alk", "amino", "anhydr", "benz", "brom", "butyl",
        "carb", "chlor", "cyan", "cycl", "ethyl", "fluor", "form", "hydro",
        "hydroxy", "iod", "isoprop", "keto", "meth", "methyl", "nitr", "oxal",
        "perchlor", "peroxy", "phen", "phosph", "poly", "propyl", "silic",
        "sulf", "thio", "vinyl",
    ]

    /// Endings chemistry uses, and English mostly does not.
    ///
    /// "-one" and "-al" are deliberately missing: "cyclone" and "formal" are
    /// ordinary words that a stem above would otherwise complete. Ketones and
    /// aldehydes are reached by the systematic rule instead, which is where
    /// they are unambiguous.
    private static let nameSuffixes: [String] = [
        "acid", "ide", "ate", "ite", "ol", "ane", "ene", "yne",
        "amine", "amide", "aldehyde", "oxide", "ose", "yl", "ine",
    ]

    /// "sodium chloride", "calcium carbonate", "potassium iodide" — an element
    /// name and an anion ending, which is how a binary or oxyanion salt is
    /// written and how nothing else is.
    private static func isElementAndAnion(_ words: [String], elements: ElementCatalog) -> Bool {
        guard words.count >= 2, let last = words.last else { return false }
        let elementNames = Set(elements.elements.map { $0.name.lowercased() })
        guard elementNames.contains(words[0]) else { return false }
        return ["ide", "ate", "ite"].contains { last.hasSuffix($0) }
    }

    /// Names chemistry uses that follow no rule, so no rule can find them.
    private static let commonNames: Set<String> = [
        "water", "salt", "table salt", "sugar", "baking soda", "bleach",
        "caffeine", "glucose", "sucrose", "fructose", "lactose", "aspirin",
        "ammonia", "urea", "quartz", "lime", "quicklime", "vinegar",
        "ozone", "graphite", "diamond", "rust", "chalk", "borax",
        "cholesterol", "testosterone", "estrogen", "adrenaline", "dopamine",
        "serotonin", "insulin", "penicillin", "morphine", "nicotine",
        "capsaicin", "vanillin", "citric acid", "acetic acid", "ethanol",
        "methanol", "acetone", "benzene", "toluene", "glycerol", "chlorophyll",
        "carotene", "beta-carotene", "retinol", "lycopene", "melatonin",
        "histamine", "keratin", "collagen", "hemoglobin", "chlorine bleach",
    ]
}
