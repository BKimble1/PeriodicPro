import Foundation

/// Parsing, ordering and formatting of molecular formulas.
///
/// Pure functions over the element catalog, so the ordering rules below are
/// unit-tested rather than eyeballed.
enum CompoundFormula {
    /// "C2H6O" → [6: 2, 1: 6, 8: 1]. `nil` for anything that is not a
    /// formula.
    ///
    /// The reading itself lives in `ChemicalFormulaParser`, which also
    /// understands parentheses, hydrates and charges; this is the composition
    /// half of it, for the callers that only want to know what is in there.
    static func parse(_ formula: String, catalog: ElementCatalog = .bundledOrEmpty) -> [Int: Int]? {
        ChemicalFormulaParser.parse(formula, catalog: catalog)?.composition
    }

    /// Hill order, which is what PubChem indexes: C first, H second, then the
    /// rest alphabetically by symbol; alphabetical throughout when there is
    /// no carbon.
    static func hill(_ composition: [Int: Int], catalog: ElementCatalog = .bundledOrEmpty) -> String {
        let symbols = composition.compactMap { number, count -> (String, Int)? in
            guard count > 0, let element = catalog.element(atomicNumber: number) else { return nil }
            return (element.symbol, count)
        }
        let hasCarbon = symbols.contains { $0.0 == "C" }
        let ordered = symbols.sorted { lhs, rhs in
            if hasCarbon {
                if lhs.0 == "C" { return true }
                if rhs.0 == "C" { return false }
                if lhs.0 == "H" { return true }
                if rhs.0 == "H" { return false }
            }
            return lhs.0 < rhs.0
        }
        return ordered.map { $0.0 + ($0.1 > 1 ? "\($0.1)" : "") }.joined()
    }

    /// The conventional written order, as far as a rule can give it.
    ///
    /// * Organic compounds (carbon and hydrogen, no metal): Hill order — CH₄,
    ///   C₂H₆O, C₆H₁₂O₆.
    /// * Anything with a metal: the metal first, then the rest by rising
    ///   electronegativity — NaCl, CaCO₃, NaHCO₃ — with a hydroxide written
    ///   as OH: NaOH, Ca(OH)₂.
    /// * Nonmetals only: hydrogen first — H₂O, HCl, H₂SO₄, H₃PO₄ — except the
    ///   hydrides of groups 13 to 15, written NH₃, PH₃; then the rest by
    ///   rising electronegativity — CO₂, SO₂, NO₂.
    ///
    /// A known compound shows its curated formula instead; this is for the
    /// compositions a learner builds that the catalog does not know.
    static func display(_ composition: [Int: Int], catalog: ElementCatalog = .bundledOrEmpty) -> String {
        let elements = composition.compactMap { number, count -> (ChemicalElement, Int)? in
            guard count > 0, let element = catalog.element(atomicNumber: number) else { return nil }
            return (element, count)
        }
        guard !elements.isEmpty else { return "" }
        let metals = elements.filter { $0.0.category.family == .metal }
        let hasCarbon = elements.contains { $0.0.symbol == "C" }
        let hasHydrogen = elements.contains { $0.0.symbol == "H" }

        func electronegativity(_ element: ChemicalElement) -> Double {
            element.electronegativity ?? (element.category.family == .metal ? 0.8 : 2.5)
        }
        func byElectronegativity(_ lhs: (ChemicalElement, Int), _ rhs: (ChemicalElement, Int)) -> Bool {
            let left = electronegativity(lhs.0)
            let right = electronegativity(rhs.0)
            if left != right { return left < right }
            return lhs.0.atomicNumber < rhs.0.atomicNumber
        }
        func joined(_ ordered: [(ChemicalElement, Int)]) -> String {
            ordered.map { $0.0.symbol + ($0.1 > 1 ? "\($0.1)" : "") }.joined()
        }

        if metals.isEmpty, hasCarbon, hasHydrogen {
            return hill(composition, catalog: catalog)
        }

        if !metals.isEmpty {
            // A hydroxide: a metal plus equal numbers of O and H.
            let oxygen = elements.first { $0.0.symbol == "O" }
            let hydrogen = elements.first { $0.0.symbol == "H" }
            if elements.count == 3, let oxygen, let hydrogen, oxygen.1 == hydrogen.1, metals.count == 1 {
                let metal = metals[0]
                let metalPart = metal.0.symbol + (metal.1 > 1 ? "\(metal.1)" : "")
                return oxygen.1 == 1 ? metalPart + "OH" : metalPart + "(OH)\(oxygen.1)"
            }
            return joined(elements.sorted(by: byElectronegativity))
        }

        // Nonmetals only.
        if hasHydrogen, elements.count == 2, let other = elements.first(where: { $0.0.symbol != "H" }),
           let group = other.0.group, (13...15).contains(group) {
            let hydrogen = elements.first { $0.0.symbol == "H" }
            return joined([other] + (hydrogen.map { [$0] } ?? []))
        }
        var ordered = elements.filter { $0.0.symbol != "H" }.sorted(by: byElectronegativity)
        if let hydrogen = elements.first(where: { $0.0.symbol == "H" }) {
            ordered.insert(hydrogen, at: 0)
        }
        return joined(ordered)
    }

    /// "C2H6O" → "C₂H₆O". Digits that follow a letter or a closing bracket
    /// become subscripts; a leading coefficient does not.
    static func subscripted(_ formula: String) -> String {
        var output = ""
        var previous: Character?
        for character in formula {
            if character.isNumber, let previous, previous.isLetter || previous == ")" || previous.isNumber,
               let scalar = Self.subscripts[character] {
                // Only digits that continue a subscript run stay subscript.
                output.append(scalar)
            } else {
                output.append(character)
            }
            previous = character
        }
        return output
    }

    /// "C₂H₆O" → "C2H6O".
    static func unsubscripted(_ formula: String) -> String {
        String(formula.map { Self.plainDigits[$0] ?? $0 })
    }

    /// "H2O" → "H 2 O", so VoiceOver reads each symbol rather than a word.
    static func spoken(_ formula: String) -> String {
        var parts: [String] = []
        for character in unsubscripted(formula) {
            if character.isUppercase || character.isNumber || character == "(" || character == ")" {
                parts.append(String(character))
            } else if character.isLowercase, var last = parts.popLast() {
                last.append(character)
                parts.append(last)
            }
        }
        return parts.joined(separator: " ")
    }

    /// Grams per mole from the IUPAC 2021 standard atomic weights the app
    /// ships. `nil` when the composition names an element it lacks.
    static func molarMass(_ composition: [Int: Int], catalog: ElementCatalog = .bundledOrEmpty) -> Double? {
        var total = 0.0
        for (number, count) in composition {
            guard let element = catalog.element(atomicNumber: number) else { return nil }
            total += element.atomicMass * Double(count)
        }
        return total > 0 ? total : nil
    }

    /// Today as an ISO 8601 date, for `lastUpdated`.
    static func today() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: Date())
    }

    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
    ]
    private static let plainDigits: [Character: Character] = [
        "₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4",
        "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9",
    ]
}

extension ElementCatalog {
    /// The bundled catalog, for callers with no environment to read it from
    /// (formula parsing, the compound catalog's own indexes). Empty rather
    /// than crashing if the bundle is unreadable.
    static let bundledOrEmpty: ElementCatalog = {
        switch ElementCatalog.loadFromApplicationBundle() {
        case .success(let catalog): return catalog
        case .failure: return ElementCatalog(elements: [])
        }
    }()
}
