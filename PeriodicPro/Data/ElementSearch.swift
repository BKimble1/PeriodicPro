import Foundation

/// Instant, allocation-light element search.
///
/// Ranking, highest first:
/// 1. exact symbol match ("o" → Oxygen)
/// 2. exact atomic-number match ("8" → Oxygen)
/// 3. name prefix ("oxy" → Oxygen)
/// 4. symbol prefix ("mg" → Magnesium)
/// 5. name contains ("gen" → Hydrogen, Nitrogen, Oxygen)
/// 6. family word prefix ("noble" → the noble gases)
/// Ties break by atomic number so results are stable and testable.
enum ElementSearch {
    static let resultLimit = 40

    /// Case- and diacritic-folded strings for one element.
    ///
    /// Folding is the expensive part of searching, so it happens once when the
    /// catalog is built rather than 236 times per keystroke.
    struct Entry: Sendable {
        let element: ChemicalElement
        let name: String
        let symbol: String
        let familyWords: [String]
    }

    /// A fixed locale: folding must not change behavior with the device region,
    /// and building a `Locale` per call showed up as pure overhead.
    private static let foldingLocale = Locale(identifier: "en_US_POSIX")

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: foldingLocale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func makeEntries(_ elements: [ChemicalElement]) -> [Entry] {
        elements.map { element in
            Entry(
                element: element,
                name: normalize(element.name),
                symbol: normalize(element.symbol),
                familyWords: normalize(element.category.displayName)
                    .split(whereSeparator: { $0 == " " || $0 == "-" })
                    .map(String.init)
            )
        }
    }

    static func results(
        for rawQuery: String,
        in entries: [Entry],
        limit: Int = resultLimit
    ) -> [ChemicalElement] {
        let query = normalize(rawQuery)
        guard !query.isEmpty, limit > 0 else { return [] }

        let queryNumber = Int(query)
        var scored: [(rank: Int, element: ChemicalElement)] = []
        scored.reserveCapacity(min(entries.count, limit * 2))

        for entry in entries {
            if entry.symbol == query {
                scored.append((0, entry.element))
            } else if let queryNumber, entry.element.atomicNumber == queryNumber {
                scored.append((1, entry.element))
            } else if entry.name.hasPrefix(query) {
                scored.append((2, entry.element))
            } else if entry.symbol.hasPrefix(query) {
                scored.append((3, entry.element))
            } else if query.count >= 2, entry.name.contains(query) {
                scored.append((4, entry.element))
            } else if queryNumber == nil, query.count >= 3,
                      // Word-prefix, not substring: otherwise "metal" would
                      // match "Reactive Nonmetal" and return the nonmetals.
                      entry.familyWords.contains(where: { $0.hasPrefix(query) }) {
                scored.append((5, entry.element))
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

    /// Convenience that folds on the spot. The app searches through
    /// `ElementCatalog.search(_:)`, which reuses a prebuilt index; this overload
    /// exists for tests and one-off callers.
    static func results(
        for rawQuery: String,
        in elements: [ChemicalElement],
        limit: Int = resultLimit
    ) -> [ChemicalElement] {
        results(for: rawQuery, in: makeEntries(elements), limit: limit)
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
