import Foundation
import Testing
@testable import PeriodicPro

/// Removing a compound means different things depending on where it came
/// from, and none of them may leave progress pointing at an identifier that
/// no longer resolves.
@MainActor
@Suite("Removing a saved compound")
struct SavedCompoundRemovalTests {
    private let elements = TestCatalog.shared

    private func makeStore() -> CompoundStore {
        CompoundStore(container: nil, catalog: TestCompounds.catalog, isOnlineLookupEnabled: false)
    }

    private func hypothetical(_ composition: [Int: Int] = [113: 2, 8: 3]) -> ChemicalCompound {
        ChemicalCompound.hypothetical(composition: composition, catalog: elements)
    }

    @Test("A bundled compound is taken off the list, never out of the catalog")
    func bundledCompoundsSurviveRemoval() throws {
        let store = makeStore()
        let progress = makeTestStore()
        let water = try #require(store.compound(cid: 962))

        progress.setCompoundSaved(water.id, true)
        _ = progress.toggleCompoundFavorite(water.id)
        #expect(store.keptCompounds(progress: progress).contains { $0.id == water.id })

        #expect(store.remove(water, progress: progress) == .clearedState)
        #expect(!progress.isCompoundSaved(water.id))
        #expect(!progress.isCompoundFavorite(water.id))
        #expect(!store.keptCompounds(progress: progress).contains { $0.id == water.id })
        // Still in the catalog, still findable, still water.
        #expect(store.compound(cid: 962)?.preferredName == "Water")
    }

    @Test("A fetched compound is purged once nothing points at it")
    func fetchedCompoundsArePurged() {
        let store = makeStore()
        let progress = makeTestStore()
        let fetched = ChemicalCompound(
            id: "pubchem-999999", pubChemCID: 999_999, preferredName: "Test compound",
            formula: "XeF6", hillFormula: "F6Xe", iupacName: nil, molarMass: 245.28,
            canonicalSMILES: nil, charge: 0, bondingClass: .unknown, tags: [],
            alternateNames: [], summary: nil, classificationSource: nil,
            dataSource: .pubChem, isLocalCurated: false, lastUpdated: "2026-01-01", structure: nil
        )
        store.retain(fetched)
        progress.setCompoundSaved(fetched.id, true)
        #expect(store.compound(id: fetched.id) != nil)

        #expect(store.remove(fetched, progress: progress) == .purgedFromCache)
        #expect(store.compound(id: fetched.id) == nil, "nothing refers to it, so it need not be kept")
        #expect(!progress.hasCompoundReferences(fetched.id))
    }

    @Test("A fetched compound the learner has practiced is kept, not purged")
    func practicedCompoundsAreKept() {
        let store = makeStore()
        let progress = makeTestStore()
        let fetched = ChemicalCompound(
            id: "pubchem-888888", pubChemCID: 888_888, preferredName: "Test compound",
            formula: "KrF2", hillFormula: "F2Kr", iupacName: nil, molarMass: 121.79,
            canonicalSMILES: nil, charge: 0, bondingClass: .unknown, tags: [],
            alternateNames: [], summary: nil, classificationSource: nil,
            dataSource: .pubChem, isLocalCurated: false, lastUpdated: "2026-01-01", structure: nil
        )
        store.retain(fetched)
        progress.setCompoundSaved(fetched.id, true)
        progress.recordCompoundAnswer(id: fetched.id, correct: true)

        #expect(store.remove(fetched, progress: progress) == .clearedState)
        #expect(store.compound(id: fetched.id) != nil,
                "an answered compound is still referred to, so the record has to stay resolvable")
        #expect(progress.compoundMastery(for: fetched.id) != .notStarted)
    }

    @Test("A composition the learner built is deleted, and leaves nothing behind")
    func hypotheticalCompositionsAreDeleted() {
        let store = makeStore()
        let progress = makeTestStore()
        let composition = hypothetical()

        store.remember(composition)
        progress.setCompoundSaved(composition.id, true)
        _ = progress.toggleCompoundFavorite(composition.id)
        progress.recordCompoundAnswer(id: composition.id, correct: false)
        #expect(store.keptCompounds(progress: progress).contains { $0.id == composition.id })

        #expect(store.remove(composition, progress: progress) == .deleted)
        #expect(store.compound(id: composition.id) == nil)
        #expect(!progress.isCompoundSaved(composition.id))
        #expect(!progress.isCompoundFavorite(composition.id))
        #expect(!progress.hasCompoundReferences(composition.id))
        #expect(progress.compoundMastery(for: composition.id) == .notStarted)
        #expect(!progress.studyCompoundIDs.contains(composition.id))
        #expect(!progress.savedCompoundIDs.contains(composition.id))
        #expect(!progress.favoriteCompoundIDs.contains(composition.id))
    }

    @Test("No removal ever leaves a study identifier that cannot be resolved")
    func nothingIsLeftDangling() {
        let store = makeStore()
        let progress = makeTestStore()
        let composition = hypothetical([6: 40, 1: 56])
        store.remember(composition)
        progress.setCompoundSaved(composition.id, true)

        let fetched = ChemicalCompound(
            id: "pubchem-777777", pubChemCID: 777_777, preferredName: "Another",
            formula: "ArF", hillFormula: "ArF", iupacName: nil, molarMass: 58.94,
            canonicalSMILES: nil, charge: 0, bondingClass: .unknown, tags: [],
            alternateNames: [], summary: nil, classificationSource: nil,
            dataSource: .pubChem, isLocalCurated: false, lastUpdated: "2026-01-01", structure: nil
        )
        store.retain(fetched)
        progress.setCompoundSaved(fetched.id, true)

        _ = store.remove(composition, progress: progress)
        _ = store.remove(fetched, progress: progress)

        for id in progress.studyCompoundIDs {
            #expect(store.compound(id: id) != nil, "\(id) is in Study and no longer resolves")
        }
        #expect(progress.studyCompoundIDs.isEmpty)
    }

    @Test("Everything the learner kept is in one list, compositions included")
    func theKeptListIsComplete() throws {
        let store = makeStore()
        let progress = makeTestStore()
        let water = try #require(store.compound(cid: 962))
        let composition = hypothetical()
        store.remember(composition)
        progress.setCompoundSaved(water.id, true)

        let kept = store.keptCompounds(progress: progress)
        #expect(kept.contains { $0.id == water.id })
        #expect(kept.contains { $0.id == composition.id },
                "a built composition is kept whether or not Save was pressed; there is nowhere else for it")
        #expect(Set(kept.map(\.id)).count == kept.count, "the list must not repeat a compound")
    }
}

/// An unverified composition may never claim to be a discovery, and a database
/// miss may never be reported as a fact about chemistry.
@MainActor
@Suite("An unverified composition says only what it knows")
struct UnverifiedCompositionTests {
    private let elements = TestCatalog.shared

    @Test("Nothing is invented: no name, no structure, no properties, no uses")
    func nothingIsInvented() {
        let composition = ChemicalCompound.hypothetical(composition: [113: 2, 8: 3], catalog: elements)
        #expect(composition.dataSource == .hypothetical)
        #expect(composition.structure == nil, "there is no structure to draw and none is made up")
        #expect(composition.summary == nil)
        #expect(composition.iupacName == nil)
        #expect(composition.tags.isEmpty)
        #expect(composition.bondingClass == .unknown)
        #expect(composition.pubChemCID == nil)
        // What it may say is what the composition itself determines.
        #expect(composition.molarMass != nil)
        #expect(!composition.hillFormula.isEmpty)
    }

    @Test("A miss is never worded as nonexistence")
    func wordingIsAboutTheDatabase() {
        let composition = ChemicalCompound.hypothetical(composition: [113: 2, 8: 3], catalog: elements)
        let source = composition.dataSource.displayName + " " + composition.attribution
        for forbidden in ["does not exist", "new compound", "discovery", "you discovered", "novel compound"] {
            #expect(!source.lowercased().contains(forbidden),
                    "a database miss must not be described as \(forbidden)")
        }
    }

    @Test("Re-checking is a separate answer from the one it was saved with")
    func recheckStatesAreDistinct() async {
        let store = CompoundStore(container: nil, catalog: TestCompounds.catalog,
                                  isOnlineLookupEnabled: false)
        let model = HypotheticalRecheckModel()
        let composition = ChemicalCompound.hypothetical(composition: [113: 2, 8: 3], catalog: elements)

        model.check(composition, store: store)
        await model.waitForPendingCheck()
        // Offline: the question could not be put, which is not an answer to it.
        guard case .failed = model.state else {
            Issue.record("being unable to ask is not the same as being told no, got \(model.state)")
            return
        }
        model.reset()
        #expect(model.state == .idle)
    }

    @Test("A recheck that finds a record offers it rather than taking it")
    func aFindIsOfferedNotApplied() async throws {
        let store = CompoundStore(
            container: nil,
            catalog: TestCompounds.catalog,
            client: PubChemClient(transport: CatalogBackedStubTransport(catalog: TestCompounds.catalog),
                                  maximumRetries: 0, minimumGap: .zero)
        )
        let progress = makeTestStore()
        // A composition whose formula the catalog does in fact know.
        let composition = ChemicalCompound.hypothetical(composition: [1: 2, 8: 1], catalog: elements)
        store.remember(composition)
        progress.setCompoundSaved(composition.id, true)

        let model = HypotheticalRecheckModel()
        model.check(composition, store: store)
        await model.waitForPendingCheck()

        guard case .found(let matches) = model.state else {
            Issue.record("H2O should now match, got \(model.state)")
            return
        }
        #expect(matches.contains { $0.name == "Water" })
        // And the learner's own record is untouched until they choose.
        #expect(store.compound(id: composition.id) != nil)
        #expect(progress.isCompoundSaved(composition.id))
    }
}
