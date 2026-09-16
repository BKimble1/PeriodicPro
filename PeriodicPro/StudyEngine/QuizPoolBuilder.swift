import Foundation

/// Turns a `QuizConfiguration` into the subjects a round may draw from.
///
/// Pure: it reads the catalogs and the progress snapshots it is handed and
/// returns an ordered list, so every scope and every filter is testable
/// without a store. The order matters when shuffling is off — "recently
/// missed" is most recent first, "custom" is the order the learner chose.
enum QuizPoolBuilder {
    /// The fewest subjects a round can be dealt from.
    static let minimumPool = 3

    static func subjects(
        for configuration: QuizConfiguration,
        catalog: ElementCatalog,
        compounds: [ChemicalCompound],
        elementSnapshots: [Int: ElementProgressSnapshot],
        compoundSnapshots: [String: CompoundProgressSnapshot]
    ) -> [QuizSubject] {
        var pool: [QuizSubject] = []
        if configuration.content.includesElements {
            pool += elements(for: configuration, catalog: catalog, snapshots: elementSnapshots)
                .map(QuizSubject.element)
        }
        if configuration.content.includesCompounds {
            pool += self.compounds(for: configuration, compounds: compounds, snapshots: compoundSnapshots)
                .map(QuizSubject.compound)
        }
        var seen = Set<String>()
        return pool.filter { seen.insert($0.key).inserted }
    }

    /// Why a round cannot start, in one plain sentence, or `nil` when it can.
    static func unavailableReason(
        for configuration: QuizConfiguration,
        poolCount: Int
    ) -> String? {
        guard poolCount < minimumPool else { return nil }
        switch configuration.scope {
        case .favorites:
            return "Add at least \(minimumPool) favorites first. Tap the heart on an element or a compound."
        case .recentlyMissed:
            return "Nothing has been missed yet. Play a round or two and this scope fills itself."
        case .notMastered:
            return "Everything in this selection is already mastered."
        case .custom:
            return "Choose at least \(minimumPool) elements or compounds."
        case .all:
            return "The filters leave fewer than \(minimumPool) items. Loosen them to start."
        }
    }

    // MARK: - Elements

    static func elements(
        for configuration: QuizConfiguration,
        catalog: ElementCatalog,
        snapshots: [Int: ElementProgressSnapshot]
    ) -> [ChemicalElement] {
        let scoped: [ChemicalElement]
        switch configuration.scope {
        case .all:
            scoped = catalog.elements
        case .favorites:
            scoped = catalog.elements.filter { snapshots[$0.atomicNumber]?.isFavorite == true }
        case .recentlyMissed:
            scoped = snapshots.values
                .filter { $0.incorrectCount > 0 }
                .sorted { ($0.lastReviewed ?? .distantPast) > ($1.lastReviewed ?? .distantPast) }
                .compactMap { catalog.element(atomicNumber: $0.atomicNumber) }
        case .notMastered:
            scoped = catalog.elements.filter { (snapshots[$0.atomicNumber]?.mastery ?? .notStarted) != .mastered }
        case .custom:
            scoped = configuration.customElementIDs.compactMap { catalog.element(atomicNumber: $0) }
        }
        return scoped.filter(configuration.elementFilters.matches)
    }

    // MARK: - Compounds

    static func compounds(
        for configuration: QuizConfiguration,
        compounds: [ChemicalCompound],
        snapshots: [String: CompoundProgressSnapshot]
    ) -> [ChemicalCompound] {
        let byID = Dictionary(compounds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // A hypothetical composition has no name and no facts to ask about.
        let askable = compounds.filter { !$0.isHypothetical }
        let scoped: [ChemicalCompound]
        switch configuration.scope {
        case .all:
            scoped = askable
        case .favorites:
            scoped = askable.filter { snapshots[$0.id]?.isFavorite == true }
        case .recentlyMissed:
            scoped = snapshots.values
                .filter { $0.incorrectCount > 0 }
                .sorted { ($0.lastReviewed ?? .distantPast) > ($1.lastReviewed ?? .distantPast) }
                .compactMap { byID[$0.compoundID] }
                .filter { !$0.isHypothetical }
        case .notMastered:
            scoped = askable.filter { (snapshots[$0.id]?.mastery ?? .notStarted) != .mastered }
        case .custom:
            scoped = configuration.customCompoundIDs.compactMap { byID[$0] }.filter { !$0.isHypothetical }
        }
        return scoped.filter { compound in
            configuration.compoundFilters.matches(compound, isSaved: snapshots[compound.id]?.isInStudy == true)
        }
    }
}
