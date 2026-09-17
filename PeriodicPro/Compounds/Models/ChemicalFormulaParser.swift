import Foundation

/// A molecular formula that has been read, rather than pattern-matched.
struct ParsedFormula: Equatable, Sendable {
    /// Atomic number → how many atoms of it.
    var composition: [Int: Int]
    /// The species charge. Zero when none was written.
    var charge: Int
    /// Whether a charge was written at all, which is not the same as a charge
    /// of zero: a formula search for a neutral species and a formula search
    /// that simply did not say are different questions.
    var hasExplicitCharge: Bool

    var atomCount: Int { composition.values.reduce(0, +) }
    /// How many different elements it names.
    var elementCount: Int { composition.count }
    /// True for a single atom of a single element — Fe, Cl, O.
    var isMonatomic: Bool { composition.count == 1 && composition.first?.value == 1 }

    func hill(catalog: ElementCatalog = .bundledOrEmpty) -> String {
        CompoundFormula.hill(composition, catalog: catalog)
    }
}

/// Reads molecular formulas the way they are actually written.
///
/// Every syntax below is parsed and tested. Nothing is accepted cosmetically —
/// a form this does not understand is rejected rather than silently read as
/// something else.
///
/// **Supported**
///
/// * ASCII counts — `H2O`, `C27H46O`, `C40H56`
/// * Unicode subscripts — `H₂O`, `C₆H₁₂O₆`
/// * Parentheses and brackets, nested — `Ca(OH)2`, `Al2(SO4)3`, `[Fe(CN)6]`,
///   `K4[Fe(CN)6]`
/// * Hydrates and other dot-separated parts, with coefficients —
///   `CuSO4·5H2O`, `Na2CO3.10H2O`, `MgSO4*7H2O`
/// * Charges, in the four forms that are unambiguous:
///   sign first (`NH4+`, `SO4-2`, `Fe+3`), superscript (`SO4²⁻`, `NH4⁺`),
///   caret-separated (`SO4^2-`), and bracketed (`[SO4]2-`, `[Fe(CN)6]3-`)
///
/// **The one ambiguous form, and the rule for it**
///
/// `Fe3+` and `NH4+` are written the same way and mean different things: in
/// the first the digit is the charge, in the second it is a subscript. The
/// rule is what a chemist reads — digits before a trailing sign are the
/// charge when what remains is a single atom of a single element, and a count
/// otherwise. So `Fe3+` is iron(III), `Ca2+` is the calcium ion, `O2-` is
/// oxide, and `NH4+` is ammonium with four hydrogens and a charge of one.
///
/// `SO42-` is therefore read as a count of forty-two and a charge of one,
/// which is wrong — but it is a form nobody writes, and the three forms people
/// do write for sulfate (`SO4-2`, `SO4²⁻`, `[SO4]2-`) are all read correctly.
///
/// **Not supported**, deliberately: isotope notation (`²H`), radicals,
/// oxidation states in Roman numerals (`Fe(III)` is read as iron with a
/// parenthesized group it cannot resolve, and rejected), and anything with a
/// bond symbol in it, which is a SMILES string rather than a formula.
enum ChemicalFormulaParser {
    /// Long enough for a real molecule written out — buckminsterfullerene,
    /// a protein subunit's empirical formula, an elaborate hydrate — and
    /// short enough that nothing pathological reaches the parser.
    static let maximumLength = 240
    /// Deeper than any formula uses, shallow enough to bound the recursion.
    static let maximumDepth = 8
    /// A resource bound, not a chemical one.
    static let maximumAtoms = 250_000
    static let maximumCount = 100_000

    enum Failure: Error, Equatable, Sendable {
        case empty
        case tooLong
        case tooDeep
        case tooManyAtoms
        case unknownSymbol(String)
        case unexpected(Character)
        case unbalanced
        case trailing(String)
    }

    /// `nil` for anything that is not a formula.
    static func parse(_ text: String, catalog: ElementCatalog = .bundledOrEmpty) -> ParsedFormula? {
        try? read(text, catalog: catalog)
    }

    static func read(_ text: String, catalog: ElementCatalog = .bundledOrEmpty) throws -> ParsedFormula {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { throw Failure.empty }
        guard normalized.count <= maximumLength else { throw Failure.tooLong }

        var composition: [Int: Int] = [:]
        var charge = 0
        var hasExplicitCharge = false

        let parts = split(normalized)
        guard !parts.isEmpty else { throw Failure.empty }

        for (index, rawPart) in parts.enumerated() {
            var part = rawPart
            guard !part.isEmpty else { throw Failure.empty }

            // A charge belongs to the species, so it is only read off the
            // last part: `CuSO4·5H2O` has no charge on its water.
            if index == parts.count - 1, let found = takeCharge(&part, catalog: catalog) {
                charge = found
                hasExplicitCharge = true
            }

            // A leading coefficient multiplies the part: the 5 of `5H2O`.
            let coefficient = takeLeadingCoefficient(&part)
            guard !part.isEmpty else { throw Failure.empty }

            var reader = Reader(characters: part, catalog: catalog)
            let group = try reader.readGroup(depth: 0)
            guard reader.isAtEnd else {
                throw Failure.trailing(String(part[reader.index...]))
            }
            for (number, count) in group {
                composition[number, default: 0] += count * coefficient
            }
        }

        guard !composition.isEmpty else { throw Failure.empty }
        let total = composition.values.reduce(0, +)
        guard total <= maximumAtoms else { throw Failure.tooManyAtoms }
        return ParsedFormula(composition: composition, charge: charge, hasExplicitCharge: hasExplicitCharge)
    }

    // MARK: - Normalizing

    /// Whitespace out, subscripts down to ASCII, the several dash and dot
    /// characters that mean one thing each collapsed to one spelling.
    static func normalize(_ text: String) -> [Character] {
        var output: [Character] = []
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character.isWhitespace { continue }
            if let plain = subscriptDigits[character] {
                output.append(plain)
            } else if minusCharacters.contains(character) {
                output.append("-")
            } else if plusCharacters.contains(character) {
                output.append("+")
            } else if separatorCharacters.contains(character) {
                output.append("·")
            } else {
                output.append(character)
            }
        }
        return output
    }

    private static let subscriptDigits: [Character: Character] = [
        "₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4",
        "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9",
    ]
    static let superscriptDigits: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
        "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
    ]
    /// Hyphen-minus, the true minus sign, and the en dash people type for it.
    private static let minusCharacters: Set<Character> = ["-", "\u{2212}", "\u{2013}", "⁻"]
    private static let plusCharacters: Set<Character> = ["+", "\u{FF0B}", "⁺"]
    /// Middle dot, bullet, dot operator, asterisk and full stop: five ways of
    /// writing the same separator in a hydrate.
    private static let separatorCharacters: Set<Character> = ["·", "•", "∙", "⋅", "*", ".", "\u{00B7}"]

    private static func split(_ characters: [Character]) -> [[Character]] {
        characters.split(separator: "·", omittingEmptySubsequences: true).map(Array.init)
    }

    private static func takeLeadingCoefficient(_ part: inout [Character]) -> Int {
        var digits = ""
        var index = 0
        while index < part.count, part[index].isASCII, part[index].isNumber, digits.count < 6 {
            digits.append(part[index])
            index += 1
        }
        guard index > 0, index < part.count, let value = Int(digits), value > 0 else { return 1 }
        part.removeFirst(index)
        return value
    }

    // MARK: - Charge

    /// Takes a trailing charge off the part, if one is written there.
    ///
    /// Four unambiguous spellings, then the one ambiguous spelling resolved by
    /// whether what remains is a single atom. See the type's documentation.
    private static func takeCharge(_ part: inout [Character], catalog: ElementCatalog) -> Int? {
        guard let last = part.last else { return nil }

        // `SO4-2`, `Fe+3`: the sign comes first and the digits after it are
        // unambiguously the magnitude.
        if last.isASCII, last.isNumber {
            var index = part.count - 1
            var digits = ""
            while index >= 0, part[index].isASCII, part[index].isNumber, digits.count < 3 {
                digits.insert(part[index], at: digits.startIndex)
                index -= 1
            }
            guard index >= 0, part[index] == "+" || part[index] == "-", let magnitude = Int(digits)
            else { return nil }
            let sign = part[index] == "-" ? -1 : 1
            part.removeSubrange(index...)
            return sign * magnitude
        }

        guard last == "+" || last == "-" else { return nil }
        let sign = last == "-" ? -1 : 1
        part.removeLast()
        guard let beforeSign = part.last else { return sign }

        // Superscript digits can only be a charge.
        if superscriptDigits[beforeSign] != nil {
            var digits = ""
            while let character = part.last, let plain = superscriptDigits[character], digits.count < 3 {
                digits.insert(plain, at: digits.startIndex)
                part.removeLast()
            }
            return sign * (Int(digits) ?? 1)
        }

        guard beforeSign.isASCII, beforeSign.isNumber else {
            // `Cl-`, `[SO4]-`: a bare sign is a charge of one.
            return sign
        }

        var digits = ""
        var index = part.count - 1
        while index >= 0, part[index].isASCII, part[index].isNumber, digits.count < 3 {
            digits.insert(part[index], at: digits.startIndex)
            index -= 1
        }
        let magnitude = Int(digits) ?? 1

        // `SO4^2-` and `[SO4]2-`: the caret and the bracket both say the
        // digits are not a subscript.
        if index >= 0, part[index] == "^" {
            part.removeSubrange(index...)
            return sign * magnitude
        }
        if index >= 0, part[index] == "]" || part[index] == ")" {
            part.removeSubrange((index + 1)...)
            return sign * magnitude
        }

        // The ambiguous case. `Fe3+` is iron(III); `NH4+` is ammonium. The
        // digits are the charge exactly when what is left is one atom.
        var withoutDigits = part
        withoutDigits.removeSubrange((index + 1)...)
        if !withoutDigits.isEmpty, isSingleAtom(withoutDigits, catalog: catalog) {
            part = withoutDigits
            return sign * magnitude
        }
        return sign
    }

    /// Whether these characters are exactly one atom of one element.
    private static func isSingleAtom(_ characters: [Character], catalog: ElementCatalog) -> Bool {
        var reader = Reader(characters: characters, catalog: catalog)
        guard let group = try? reader.readGroup(depth: 0), reader.isAtEnd else { return false }
        return group.count == 1 && group.first?.value == 1
    }

    // MARK: - Reading

    private struct Reader {
        let characters: [Character]
        var index = 0
        let catalog: ElementCatalog

        var isAtEnd: Bool { index >= characters.count }

        private func peek(_ offset: Int = 0) -> Character? {
            let position = index + offset
            return position < characters.count ? characters[position] : nil
        }

        /// A run of symbols and bracketed groups, each with an optional count.
        mutating func readGroup(depth: Int) throws -> [Int: Int] {
            guard depth <= ChemicalFormulaParser.maximumDepth else { throw Failure.tooDeep }
            var composition: [Int: Int] = [:]
            var readAnything = false

            while let character = peek() {
                if character == "(" || character == "[" {
                    let closing: Character = character == "(" ? ")" : "]"
                    index += 1
                    let inner = try readGroup(depth: depth + 1)
                    guard peek() == closing else { throw Failure.unbalanced }
                    index += 1
                    let multiplier = readCount()
                    for (number, count) in inner {
                        composition[number, default: 0] += count * multiplier
                    }
                    readAnything = true
                } else if character == ")" || character == "]" {
                    break
                } else if character.isUppercase {
                    let element = try readSymbol()
                    let count = readCount()
                    composition[element, default: 0] += count
                    readAnything = true
                } else {
                    break
                }
                let running = composition.values.reduce(0, +)
                guard running <= ChemicalFormulaParser.maximumAtoms else { throw Failure.tooManyAtoms }
            }

            guard readAnything else {
                if let character = peek() { throw Failure.unexpected(character) }
                throw Failure.empty
            }
            return composition
        }

        /// Two letters first, then one — so `Co` is cobalt and `CO` is carbon
        /// monoxide, and `Nao` is neither.
        private mutating func readSymbol() throws -> Int {
            guard let first = peek(), first.isUppercase else {
                throw Failure.unexpected(peek() ?? " ")
            }
            if let second = peek(1), second.isLowercase {
                let twoLetter = String([first, second])
                if let element = catalog.element(symbol: twoLetter) {
                    index += 2
                    return element.atomicNumber
                }
                // A lowercase letter that does not make a symbol is not a
                // formula at all — it is a word, or a SMILES string.
                throw Failure.unknownSymbol(twoLetter)
            }
            guard let element = catalog.element(symbol: String(first)) else {
                throw Failure.unknownSymbol(String(first))
            }
            index += 1
            return element.atomicNumber
        }

        private mutating func readCount() -> Int {
            var digits = ""
            while let character = peek(), character.isASCII, character.isNumber, digits.count < 6 {
                digits.append(character)
                index += 1
            }
            guard let value = Int(digits), value > 0 else { return 1 }
            return min(value, ChemicalFormulaParser.maximumCount)
        }
    }
}
