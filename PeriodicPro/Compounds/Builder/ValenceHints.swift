import Foundation

/// Heuristic hints about a composition, from common oxidation states.
///
/// These are labeled as heuristics everywhere they appear, because that is
/// what they are: a charge-balance check with a short table of the states
/// each element is usually found in. A balance is not proof that a compound
/// exists, and the lack of one is not proof that it does not — most covalent
/// molecules do not need one. The lookup is the only source of truth.
enum ValenceHints {
    /// What kind of hint this is, for the icon and for tests.
    enum Kind: Hashable, Sendable {
        case elementalForm
        case nobleGas
        case balanced
        case unbalanced
        case noData
    }

    struct Hint: Hashable, Identifiable, Sendable {
        let kind: Kind
        let text: String
        var id: String { text }
    }

    /// Common oxidation states, most typical first. Deliberately short: a
    /// hint should mention the state a learner would meet in a textbook, not
    /// every state ever reported.
    static let commonOxidationStates: [Int: [Int]] = [
        1: [1, -1], 3: [1], 4: [2], 5: [3], 6: [4, -4, 2], 7: [-3, 3, 5], 8: [-2], 9: [-1],
        11: [1], 12: [2], 13: [3], 14: [4, -4], 15: [-3, 3, 5], 16: [-2, 4, 6], 17: [-1, 1, 3, 5, 7],
        19: [1], 20: [2], 21: [3], 22: [4, 3], 23: [5, 4, 3], 24: [3, 6], 25: [2, 4, 7], 26: [3, 2],
        27: [2, 3], 28: [2], 29: [2, 1], 30: [2], 31: [3], 32: [4], 33: [-3, 3, 5], 34: [-2, 4, 6],
        35: [-1, 1, 5], 37: [1], 38: [2], 39: [3], 40: [4], 42: [6, 4], 47: [1], 48: [2], 49: [3],
        50: [4, 2], 51: [3, 5], 52: [-2, 4, 6], 53: [-1, 1, 5, 7], 55: [1], 56: [2], 57: [3],
        58: [3, 4], 74: [6, 4], 78: [2, 4], 79: [3, 1], 80: [2, 1], 81: [1, 3], 82: [2, 4], 83: [3],
        88: [2], 90: [4], 92: [6, 4],
    ]

    static func hints(for composition: [Int: Int], catalog: ElementCatalog) -> [Hint] {
        let elements = composition.compactMap { number, count -> (ChemicalElement, Int)? in
            guard count > 0, let element = catalog.element(atomicNumber: number) else { return nil }
            return (element, count)
        }.sorted { $0.0.atomicNumber < $1.0.atomicNumber }
        guard !elements.isEmpty else { return [] }

        if elements.count == 1, let only = elements.first {
            let formula = CompoundFormula.subscripted(only.0.symbol + (only.1 > 1 ? "\(only.1)" : ""))
            return [Hint(kind: .elementalForm,
                         text: "\(formula) is one element on its own: an elemental form, not a compound.")]
        }

        var hints: [Hint] = []
        if let noble = elements.first(where: { $0.0.category == .nobleGas }) {
            hints.append(Hint(kind: .nobleGas,
                              text: "\(noble.0.name) is a noble gas. It forms very few compounds, "
                                  + "so a lookup is likely to find nothing."))
        }

        if let balance = balance(elements) {
            hints.append(Hint(kind: .balanced, text: "Charge balance with common oxidation states: "
                              + balance + "."))
        } else if elements.allSatisfy({ commonOxidationStates[$0.0.atomicNumber] != nil }) {
            hints.append(Hint(kind: .unbalanced,
                              text: "No charge balance with common oxidation states. Covalent molecules do "
                                  + "not need one, so this says nothing on its own — the lookup decides."))
        } else {
            hints.append(Hint(kind: .noData,
                              text: "No oxidation-state hint: the table here does not cover every element."))
        }
        return hints
    }

    /// One assignment of a common state to each element whose weighted sum
    /// is zero, described as "Na +1, Cl −1", or `nil` when there is none.
    static func balance(_ elements: [(ChemicalElement, Int)]) -> String? {
        guard elements.count <= 4 else { return nil }
        let options = elements.map { commonOxidationStates[$0.0.atomicNumber] ?? [] }
        guard options.allSatisfy({ !$0.isEmpty }) else { return nil }

        var chosen: [Int] = []
        func search(_ index: Int, sum: Int) -> Bool {
            if index == elements.count {
                return sum == 0 && chosen.contains { $0 > 0 } && chosen.contains { $0 < 0 }
            }
            for state in options[index] {
                chosen.append(state)
                if search(index + 1, sum: sum + state * elements[index].1) { return true }
                chosen.removeLast()
            }
            return false
        }
        guard search(0, sum: 0) else { return nil }
        return zip(elements, chosen).map { pair, state in
            let sign = state > 0 ? "+" : "\u{2212}"
            return "\(pair.0.symbol) \(sign)\(abs(state))"
        }.joined(separator: ", ")
    }
}
