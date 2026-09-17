import Foundation
import Testing
@testable import PeriodicPro

/// The bundled compound catalog, the formula tooling and the scientific
/// promises the compound feature makes. `Tools/validate_compounds.py` mirrors
/// the data half on Linux.
@Suite("Compound catalog")
struct CompoundCatalogTests {
    private let catalog = TestCompounds.catalog
    private let elements = TestCatalog.shared

    @Test("The bundled catalog loads with its fifty verified compounds")
    func catalogLoads() {
        #expect(catalog.loadError == nil, "compounds.json failed to load: \(catalog.loadError ?? "")")
        #expect(catalog.count == 50)
        #expect(catalog.compounds.allSatisfy { $0.isLocalCurated && $0.dataSource == .curated })
        #expect(catalog.compounds.allSatisfy { $0.pubChemCID != nil })
    }

    @Test("Every bundled molar mass matches the app's own IUPAC 2021 weights")
    func molarMassesAgree() {
        for compound in catalog.compounds {
            guard let stored = compound.molarMass,
                  let computed = CompoundFormula.molarMass(compound.composition, catalog: elements) else {
                Issue.record("\(compound.preferredName) has no molar mass")
                continue
            }
            #expect(abs(stored - computed) < 0.02, "\(compound.preferredName): \(stored) vs \(computed)")
        }
    }

    @Test("C₂H₆O is not automatically ethanol: two bundled compounds share it")
    func sharedFormulaIsNotAssumed() {
        let matches = catalog.compounds(hillFormula: "C2H6O")
        #expect(Set(matches.map(\.preferredName)) == ["Ethanol", "Dimethyl ether"])
        #expect(matches.count == 2, "a formula must never resolve to the first hit")
    }

    @Test("Search ranks an exact formula and an exact name first")
    func searchRanking() {
        #expect(catalog.search("H2O").first?.preferredName == "Water")
        #expect(catalog.search("H₂O").first?.preferredName == "Water")
        #expect(catalog.search("NaCl").first?.preferredName == "Sodium chloride")
        #expect(catalog.search("water").first?.preferredName == "Water")
        #expect(catalog.search("sod").contains { $0.preferredName == "Sodium chloride" })
        #expect(catalog.search("").isEmpty)
        #expect(catalog.search("zzzz").isEmpty)
    }

    @Test("Classification is conservative: only stated where the constituents make it clear")
    func classificationIsConservative() {
        #expect(TestCompounds.compound("Sodium chloride").bondingClass == .ionic)
        #expect(TestCompounds.compound("Water").bondingClass == .molecular)
        #expect(TestCompounds.compound("Silicon dioxide").bondingClass == .networkSolid)
        for compound in catalog.compounds where compound.bondingClass != .unknown {
            #expect(compound.classificationSource?.isEmpty == false,
                    "\(compound.preferredName) is classified without a stated basis")
        }
        #expect(TestCompounds.compound("Hydrogen chloride").tags.contains(.acid))
        #expect(!TestCompounds.compound("Methane").tags.contains(.acid), "hydrogen alone is not acidity")
    }

    @Test("Structures say what they are, and a network solid has none")
    func structuresAreLabeled() {
        let water = TestCompounds.compound("Water")
        #expect(water.structure?.source == .computedConformer)
        #expect(water.structure?.is3D == true)
        #expect(water.structure?.atoms.count == 3)
        #expect(water.structure?.bonds.count == 2)
        let salt = TestCompounds.compound("Sodium chloride")
        #expect(salt.structure?.source == .curatedLattice)
        #expect(salt.structure?.bonds.allSatisfy { $0.isContact } == true, "a lattice draws contacts, not bonds")
        #expect(TestCompounds.compound("Silicon dioxide").structure == nil)
        #expect(TestCompounds.compound("Carbon dioxide").structure?.bonds.allSatisfy { $0.order == 2 } == true)
    }

    @Test("A compound scene draws the atoms in their own element colors")
    func sceneConversion() throws {
        let water = TestCompounds.compound("Water")
        let scene = try #require(CompoundStructureScene.scene(for: water))
        #expect(scene.kind == .compound)
        #expect(scene.atoms.count == 3)
        #expect(scene.bonds.count == 2)
        #expect(scene.representationLabel == "Representative molecular structure")
        #expect(scene.atoms.contains { $0.tintHex == ElementRenderPalette.tintHex(atomicNumber: 8) })
        #expect(scene.boundingRadius > 0.99 && scene.boundingRadius < 1.01, "scenes are normalized")
        let spaceFill = try #require(CompoundStructureScene.scene(for: water, style: .spaceFill))
        #expect(spaceFill.bonds.isEmpty)
        #expect(spaceFill.id != scene.id)
        let salt = try #require(CompoundStructureScene.scene(for: TestCompounds.compound("Sodium chloride")))
        #expect(salt.representationLabel == "Representative crystal unit cell")
        #expect(salt.bonds.allSatisfy { !$0.isDiscreteBond })
        #expect(CompoundStructureScene.scene(for: TestCompounds.compound("Silicon dioxide")) == nil)
    }
}

@Suite("Compound formulas")
struct CompoundFormulaTests {
    private let elements = TestCatalog.shared

    @Test("Parsing reads symbols, counts, subscripts and trailing charges")
    func parsing() {
        #expect(CompoundFormula.parse("H2O", catalog: elements) == [1: 2, 8: 1])
        #expect(CompoundFormula.parse("C₂H₆O", catalog: elements) == [6: 2, 1: 6, 8: 1])
        #expect(CompoundFormula.parse("NaCl", catalog: elements) == [11: 1, 17: 1])
        #expect(CompoundFormula.parse("NH4+", catalog: elements) == [7: 1, 1: 4])
        #expect(CompoundFormula.parse("Xx2", catalog: elements) == nil)
        #expect(CompoundFormula.parse("", catalog: elements) == nil)
        #expect(CompoundFormula.parse("h2o", catalog: elements) == nil, "symbols are case-sensitive")
    }

    @Test("Hill order puts carbon and hydrogen first, then the alphabet")
    func hillOrder() {
        #expect(CompoundFormula.hill([6: 2, 1: 6, 8: 1], catalog: elements) == "C2H6O")
        #expect(CompoundFormula.hill([11: 1, 17: 1], catalog: elements) == "ClNa")
        #expect(CompoundFormula.hill([1: 2, 8: 1], catalog: elements) == "H2O")
        #expect(CompoundFormula.hill([1: 2, 16: 1, 8: 4], catalog: elements) == "H2O4S")
    }

    @Test("The written formula follows convention: metal first, hydroxides as OH, organics in Hill order")
    func displayOrder() {
        #expect(CompoundFormula.display([11: 1, 17: 1], catalog: elements) == "NaCl")
        #expect(CompoundFormula.display([1: 2, 8: 1], catalog: elements) == "H2O")
        #expect(CompoundFormula.display([6: 2, 1: 6, 8: 1], catalog: elements) == "C2H6O")
        #expect(CompoundFormula.display([11: 1, 8: 1, 1: 1], catalog: elements) == "NaOH")
        #expect(CompoundFormula.display([20: 1, 8: 2, 1: 2], catalog: elements) == "Ca(OH)2")
        #expect(CompoundFormula.display([7: 1, 1: 3], catalog: elements) == "NH3")
        #expect(CompoundFormula.display([1: 2, 16: 1, 8: 4], catalog: elements) == "H2SO4")
        #expect(CompoundFormula.display([6: 1, 8: 2], catalog: elements) == "CO2")
    }

    @Test("Subscripts and spoken forms")
    func formatting() {
        #expect(CompoundFormula.subscripted("C2H6O") == "C₂H₆O")
        #expect(CompoundFormula.subscripted("Ca(OH)2") == "Ca(OH)₂")
        #expect(CompoundFormula.unsubscripted("H₂O") == "H2O")
        #expect(CompoundFormula.spoken("NaCl") == "Na Cl")
        #expect(CompoundFormula.spoken("H2O") == "H 2 O")
    }

    @Test("Molar mass is the sum of the bundled atomic weights")
    func molarMass() throws {
        let water = try #require(CompoundFormula.molarMass([1: 2, 8: 1], catalog: elements))
        #expect(abs(water - 18.015) < 0.01)
        #expect(CompoundFormula.molarMass([999: 1], catalog: elements) == nil)
    }
}

@Suite("Compound honesty")
struct CompoundHonestyTests {
    private let elements = TestCatalog.shared

    @Test("A hypothetical composition carries a formula and a mass, and nothing invented")
    func hypotheticalInventsNothing() {
        let compound = ChemicalCompound.hypothetical(composition: [79: 1, 2: 3], catalog: elements)
        #expect(compound.isHypothetical)
        #expect(compound.dataSource == .hypothetical)
        #expect(compound.structure == nil)
        #expect(compound.bondingClass == .unknown)
        #expect(compound.tags.isEmpty)
        #expect(compound.summary == nil)
        #expect(compound.iupacName == nil)
        #expect(compound.pubChemCID == nil)
        #expect(compound.id.hasPrefix("hypothetical-"))
        #expect(compound.attribution.contains("No database match"))
        #expect(compound.molarMass != nil)
    }

    @Test("Hints are heuristics and say so; balance is a description, not a verdict")
    func valenceHints() {
        let saltHints = ValenceHints.hints(for: [11: 1, 17: 1], catalog: elements)
        #expect(saltHints.contains { $0.kind == .balanced && $0.text.contains("Na +1") && $0.text.contains("Cl") })
        let waterHints = ValenceHints.hints(for: [1: 2, 8: 1], catalog: elements)
        #expect(waterHints.contains { $0.kind == .balanced })
        let single = ValenceHints.hints(for: [8: 2], catalog: elements)
        #expect(single.first?.kind == .elementalForm)
        let noble = ValenceHints.hints(for: [2: 1, 1: 1], catalog: elements)
        #expect(noble.contains { $0.kind == .nobleGas })
        #expect(ValenceHints.hints(for: [:], catalog: elements).isEmpty)
        // Methane balances only with a formal −4 on carbon: fine as a hint,
        // but the hint text must never claim existence.
        for hint in ValenceHints.hints(for: [6: 1, 1: 4], catalog: elements) {
            #expect(!hint.text.lowercased().contains("exists"))
        }
    }

    @Test("Only PubChem candidates count as known; a formula miss is a miss")
    @MainActor
    func builderStates() async throws {
        let store = CompoundStore(container: nil, catalog: TestCompounds.catalog,
                                  client: PubChemClient(transport: StubTransport(), maximumRetries: 0,
                                                        minimumGap: .zero))
        let model = CompoundBuilderModel()
        model.add(TestCatalog.element("H"))
        model.increment(1)
        model.add(TestCatalog.element("O"))
        #expect(model.hillFormula(catalog: elements) == "H2O")
        model.lookUp(store: store, catalog: elements)
        guard case .matched(let water) = model.state else {
            Issue.record("water should match the bundled catalog, got \(model.state)")
            return
        }
        #expect(water.preferredName == "Water")

        // Ethanol and dimethyl ether: the learner chooses.
        model.clear()
        model.add(TestCatalog.element("C"))
        model.increment(6)
        model.add(TestCatalog.element("H"))
        for _ in 0..<5 { model.increment(1) }
        model.add(TestCatalog.element("O"))
        model.lookUp(store: store, catalog: elements)
        guard case .choices(let candidates) = model.state else {
            Issue.record("C2H6O should offer a choice, got \(model.state)")
            return
        }
        #expect(candidates.count == 2)
        #expect(candidates.allSatisfy { $0.hillFormula == "C2H6O" })
        model.choose(candidates[1], store: store)
        guard case .matched(let chosen) = model.state else {
            Issue.record("choosing should resolve, got \(model.state)")
            return
        }
        #expect(chosen.preferredName == candidates[1].name)

        // Nothing local, and the stub transport answers like an offline
        // device: that is a failure to ask, never a miss.
        model.clear()
        model.add(TestCatalog.element("Au"))
        model.add(TestCatalog.element("He"))
        model.lookUp(store: store, catalog: elements)
        try await Task.sleep(for: .milliseconds(300))
        guard case .failed = model.state else {
            Issue.record("an unreachable PubChem must not be reported as a miss, got \(model.state)")
            return
        }
        model.clear()
        #expect(model.state == .idle)
    }
}

@MainActor
@Suite("Compound progress")
struct CompoundProgressTests {
    @Test("Favorites, saved and answers are tracked per compound and survive a reset only as choices")
    func progressRoundTrip() {
        let store = makeTestStore()
        #expect(!store.isCompoundFavorite("pubchem-962"))
        #expect(store.toggleCompoundFavorite("pubchem-962"))
        #expect(store.isCompoundFavorite("pubchem-962"))
        store.setCompoundSaved("pubchem-5234", true)
        #expect(store.isCompoundSaved("pubchem-5234"))
        store.recordCompoundAnswer(id: "pubchem-702", correct: true)
        store.recordCompoundAnswer(id: "pubchem-702", correct: true)
        store.recordCompoundAnswer(id: "pubchem-702", correct: true)
        #expect(store.compoundMastery(for: "pubchem-702") == .mastered)
        #expect(store.masteredCompoundCount == 1)
        #expect(store.totalCompoundAnswered == 3)
        #expect(Set(store.studyCompoundIDs) == ["pubchem-962", "pubchem-5234", "pubchem-702"])
        #expect(store.currentStreak == 1, "a compound answer counts as study on that day")

        store.resetAllProgress()
        #expect(store.isCompoundFavorite("pubchem-962"))
        #expect(store.isCompoundSaved("pubchem-5234"))
        #expect(store.compoundMastery(for: "pubchem-702") == .notStarted)
        #expect(store.totalCompoundAnswered == 0)
    }

    @Test("Compound progress persists across a reload of the same container")
    func persistence() throws {
        let container = try #require(PersistenceController.makeInMemoryContainer())
        let first = ProgressStore(container: container, storage: .memoryOnlyForTesting)
        first.toggleCompoundFavorite("pubchem-962")
        first.recordCompoundAnswer(id: "pubchem-962", correct: false)
        let second = ProgressStore(container: container, storage: .memoryOnlyForTesting)
        #expect(second.isCompoundFavorite("pubchem-962"))
        #expect(second.compoundSnapshot(for: "pubchem-962").incorrectCount == 1)
    }
}

@MainActor
@Suite("Automatic identification")
struct BuilderIdentificationTests {
    private let elements = TestCatalog.shared

    private func makeStore(_ transport: StubTransport) -> CompoundStore {
        CompoundStore(
            container: nil,
            catalog: TestCompounds.catalog,
            client: PubChemClient(transport: transport, maximumRetries: 0, minimumGap: .zero)
        )
    }

    @Test("A formula the device knows is named without touching the network")
    func localMatchesAreInstant() {
        let transport = StubTransport()
        let model = CompoundBuilderModel()
        model.configure(store: makeStore(transport), catalog: elements)

        model.add(TestCatalog.element("H"))
        model.increment(1)
        model.add(TestCatalog.element("O"))

        guard case .matched(let water) = model.state else {
            Issue.record("H2O should name itself from the catalog, got \(model.state)")
            return
        }
        #expect(water.preferredName == "Water")
        #expect(model.origin == .local)
        #expect(transport.requestedPaths.isEmpty, "a local match must never reach PubChem")
    }

    @Test("An ambiguous formula is never resolved to one of its candidates")
    func ambiguityIsNotGuessed() {
        let transport = StubTransport()
        let model = CompoundBuilderModel()
        model.configure(store: makeStore(transport), catalog: elements)

        model.add(TestCatalog.element("C"))
        model.increment(6)
        model.add(TestCatalog.element("H"))
        for _ in 0..<5 { model.increment(1) }
        model.add(TestCatalog.element("O"))

        guard case .choices(let candidates) = model.state else {
            Issue.record("C2H6O must stay a choice, got \(model.state)")
            return
        }
        #expect(candidates.count == 2)
        let names = Set(candidates.map(\.name))
        #expect(names.contains("Ethanol"))
        #expect(names.contains("Dimethyl ether"))
        #expect(model.statusMessage?.contains("2 known compounds") == true)
        #expect(transport.requestedPaths.isEmpty)
    }

    @Test("PubChem is asked once the learner stops, not once per tap")
    func debouncesTheNetwork() async throws {
        let transport = StubTransport()
        let model = CompoundBuilderModel()
        model.configure(store: makeStore(transport), catalog: elements)

        model.add(TestCatalog.element("Au"))
        for _ in 0..<8 { model.increment(79) }
        #expect(model.state == .searching)
        #expect(model.origin == .remote)
        #expect(model.remoteRequestCount == 0, "nothing is sent while the tray is still changing")

        // Waited for rather than slept through. The debounce is 650 ms, but a
        // loaded runner can take several times that to schedule the work, and
        // a fixed sleep then reads the counter before the request has gone —
        // which is how this passed at 3.257 seconds and failed on the next
        // run with nothing changed between them.
        let deadline = ContinuousClock.now + .seconds(20)
        while model.remoteRequestCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.remoteRequestCount == 1, "nine changes, one request")

        // And it stays one: a debounce that merely delayed the nine requests
        // rather than coalescing them would show the rest arriving now.
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.remoteRequestCount == 1, "the other eight changes must never be sent")

        while model.state == .searching, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        // The stub answers like an offline device, which is a failure to ask
        // rather than a miss — and never a discovery.
        guard case .failed = model.state else {
            Issue.record("an unreachable PubChem is not a miss, got \(model.state)")
            return
        }
    }

    @Test("Clearing the tray cancels whatever was in flight")
    func clearingCancels() async throws {
        let transport = StubTransport()
        let model = CompoundBuilderModel()
        model.configure(store: makeStore(transport), catalog: elements)

        model.add(TestCatalog.element("Au"))
        model.add(TestCatalog.element("He"))
        #expect(model.state == .searching)
        model.clear()
        #expect(model.state == .idle)
        try await Task.sleep(for: .milliseconds(1_000))
        #expect(model.remoteRequestCount == 0, "a canceled lookup never reaches the network")
        #expect(model.state == .idle)
    }
}

@MainActor
@Suite("Study shelves and compound persistence")
struct StudyShelfTests {
    private let elements = TestCatalog.shared

    @Test("The recent shelf shows at most six, and filters before it caps")
    func recentShelfIsCapped() {
        let history = Array(1...20)
        #expect(StudyShelf.recentLimit == 6)
        #expect(StudyShelf.recent(from: history, isFavorite: { _ in false }) == [1, 2, 3, 4, 5, 6])
        #expect(StudyShelf.recent(from: [], isFavorite: { _ in false }).isEmpty)
        #expect(StudyShelf.recent(from: [1, 2, 3], isFavorite: { _ in false }) == [1, 2, 3])

        // Favoriting the six most recent must not empty the shelf: the filter
        // runs over the whole window, and the cap comes afterwards.
        let favorites: Set<Int> = [1, 2, 3, 4, 5, 6]
        let shelf = StudyShelf.recent(from: history, isFavorite: { favorites.contains($0) })
        #expect(shelf == [7, 8, 9, 10, 11, 12])
        #expect(shelf.count == StudyShelf.recentLimit)
    }

    /// The hole this closes: a compound fetched from PubChem lives only in the
    /// cache, and progress stores an identifier. Favoriting one without
    /// caching it first left an identifier that resolved to nothing after a
    /// relaunch — a favorite that had quietly disappeared.
    @Test("A remote compound is cached before its favorite is, and both survive a relaunch")
    func remoteFavoritesSurvive() throws {
        let container = try #require(PersistenceController.makeInMemoryContainer())
        let remote = ChemicalCompound(
            id: "pubchem-999999", pubChemCID: 999_999, preferredName: "Test remote compound",
            formula: "XeF4", hillFormula: "F4Xe", iupacName: nil, molarMass: 207.28,
            canonicalSMILES: nil, charge: 0, bondingClass: .molecular, tags: [],
            alternateNames: [], summary: nil, classificationSource: nil, dataSource: .pubChem,
            isLocalCurated: false, lastUpdated: nil, structure: nil
        )

        let store = CompoundStore(container: container, catalog: TestCompounds.catalog,
                                  isOnlineLookupEnabled: false)
        let progress = ProgressStore(container: container, storage: .memoryOnlyForTesting)
        #expect(store.compound(id: remote.id) == nil, "nothing knows it yet")

        store.retain(remote)
        #expect(progress.toggleCompoundFavorite(remote.id))
        progress.setCompoundSaved(remote.id, true)

        // A fresh pair of stores over the same container is what a relaunch is.
        let reopened = CompoundStore(container: container, catalog: TestCompounds.catalog,
                                     isOnlineLookupEnabled: false)
        let reopenedProgress = ProgressStore(container: container, storage: .memoryOnlyForTesting)
        #expect(reopenedProgress.isCompoundFavorite(remote.id))
        #expect(reopenedProgress.isCompoundSaved(remote.id))
        let resolved = reopened.compound(id: remote.id)
        #expect(resolved?.preferredName == "Test remote compound",
                "a favorited compound has to still resolve by identifier")
        #expect(reopenedProgress.studyCompoundIDs.contains(remote.id),
                "a saved compound joins the study pool")
    }

    @Test("Retaining a bundled compound does not duplicate it into the cache")
    func bundledCompoundsAreNotCached() throws {
        let container = try #require(PersistenceController.makeInMemoryContainer())
        let store = CompoundStore(container: container, catalog: TestCompounds.catalog,
                                  isOnlineLookupEnabled: false)
        let water = TestCompounds.compound("Water")
        store.retain(water)
        #expect(store.cachedCompounds.isEmpty, "the bundle is already permanent")
        #expect(store.compound(id: water.id)?.preferredName == "Water")
    }

    @Test("A quiz built from a saved compound can be dealt")
    func savedCompoundsReachTheQuizPool() {
        let progress = makeTestStore()
        let water = TestCompounds.compound("Water")
        progress.setCompoundSaved(water.id, true)

        var configuration = QuizConfiguration.standard
        configuration.content = .compounds
        configuration.compoundFilters.onlySaved = true
        let pool = QuizPoolBuilder.subjects(
            for: configuration,
            catalog: elements,
            compounds: TestCompounds.catalog.compounds,
            elementSnapshots: progress.snapshots,
            compoundSnapshots: progress.compoundSnapshots
        )
        #expect(pool.contains { $0.compound?.id == water.id })
    }
}
