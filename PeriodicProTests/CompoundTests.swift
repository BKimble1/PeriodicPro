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
