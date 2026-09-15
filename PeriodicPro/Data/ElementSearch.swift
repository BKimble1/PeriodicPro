import Foundation

/// Instant, allocation-light element search.
///
/// Ranking, highest first:
/// 1. exact symbol match ("o" → Oxygen)
/// 2. exact atomic-number match ("8" → Oxygen)
/// 3. name prefix ("oxy" → Oxygen)
/// 4. symbol prefix ("mg" → Magnesium)
/// 5. name contains ("gen" → Hydrogen, Nitrogen, Oxygen)
/// Ties break by atomic number so results are stable and testable.
enum ElementSearch {
    static let resultLimit = 40

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func results(
        for rawQuery: String,
        in elements: [ChemicalElement],
        limit: Int = resultLimit
    ) -> [ChemicalElement] {
        let query = normalize(rawQuery)
        guard !query.isEmpty else { return [] }

        let queryNumber = Int(query)
        var scored: [(rank: Int, element: ChemicalElement)] = []
        scored.reserveCapacity(min(elements.count, limit * 2))

        for element in elements {
            let symbol = normalize(element.symbol)
            let name = normalize(element.name)

            if symbol == query {
                scored.append((0, element))
            } else if let queryNumber, element.atomicNumber == queryNumber {
                scored.append((1, element))
            } else if name.hasPrefix(query) {
                scored.append((2, element))
            } else if symbol.hasPrefix(query) {
                scored.append((3, element))
            } else if query.count >= 2, name.contains(query) {
                scored.append((4, element))
            } else if queryNumber == nil,
                      query.count >= 2,
                      normalize(element.category.displayName).contains(query) {
                scored.append((5, element))
            }
        }

        return scored
            .sorted { lhs, rhs in
                lhs.rank == rhs.rank
                    ? lhs.element.atomicNumber < rhs.element.atomicNumber
                    : lhs.rank < rhs.rank
            }
            .prefix(limit)
            .map { $0.element }
    }
}

/// The current table filter. `nil` family and empty category set mean "All".
struct ElementFilter: Equatable, Hashable, Sendable {
    var family: ElementFamily?
    var categories: Set<ElementCategory>

    static let all = ElementFilter(family: nil, categories: [])

    var isActive: Bool { family != nil || !categories.isEmpty }

    var summary: String {
        if let family, categories.isEmpty { return family.displayName }
        if categories.count == 1, let only = categories.first { return only.pluralName }
        if categories.count > 1 { return "\(categories.count) families" }
        return "All"
    }

    func matches(_ element: ChemicalElement) -> Bool {
        if !categories.isEmpty {
            return categories.contains(element.category)
        }
        if let family {
            return element.category.family == family
        }
        return true
    }

    func apply(to elements: [ChemicalElement]) -> [ChemicalElement] {
        isActive ? elements.filter(matches) : elements
    }
}
