import Foundation
import Testing
@testable import PeriodicPro

/// The scientific promises the 3D feature makes, asserted against the shipped
/// data. `Tools/validate_structures.py` mirrors these on Linux.
@Suite("Structure profiles")
struct StructureProfileTests {
    private let catalog = TestCatalog.shared
    private let structures = ElementStructureCatalog.shared

    private func entry(_ symbol: String) -> ElementStructureEntry {
        structures.entry(atomicNumber: TestCatalog.element(symbol).atomicNumber)
    }

    private func form(_ symbol: String, index: Int = 0) -> StructureScene {
        StructureSceneBuilder.scene(for: TestCatalog.element(symbol), representation: .form(index))
    }

    @Test("Every one of the 118 elements has a profile: established, or explicitly unknown")
    func allElementsAreCovered() {
        #expect(structures.loadError == nil, "structures.json failed to load: \(structures.loadError ?? "")")
        #expect(structures.isComplete)
        for element in catalog.elements {
            let entry = structures.entry(atomicNumber: element.atomicNumber)
            let profile = entry.primary
            if profile.representationKind == .unknown {
                #expect(!profile.isExperimentallyEstablished, "\(element.symbol) unknown but established")
                #expect(profile.notes?.lowercased().contains("not established") == true,
                        "\(element.symbol) must say its structure is not established")
            } else {
                #expect(profile.isExperimentallyEstablished, "\(element.symbol) drawn without being established")
                #expect(!profile.source.isEmpty, "\(element.symbol) has no source")
            }
        }
    }

    @Test("A missing entry is an honest unknown, never a generic lattice")
    func missingDataIsHonest() {
        let empty = ElementStructureCatalog(entries: [])
        let entry = empty.entry(atomicNumber: 79)
        #expect(entry.isUnknown)
        #expect(entry.primary.representationKind == .unknown)
        let options = StructureSceneBuilder.representations(for: TestCatalog.element("Au"), catalog: empty)
        #expect(options.map(\.representation) == [.atom])
        let scene = StructureSceneBuilder.scene(for: TestCatalog.element("Au"), representation: .form(0),
                                                catalog: empty)
        #expect(scene.kind == .atomModel)
        #expect(scene.representationLabel == "Bulk structure not established")
        #expect(!scene.isEstablished)
    }

    @Test("Gold, copper and silver are face-centered cubic")
    func coinageMetalsAreFCC() {
        for symbol in ["Au", "Cu", "Ag"] {
            #expect(entry(symbol).primary.representationKind == .fcc, "\(symbol) should be FCC")
            let scene = form(symbol)
            #expect(scene.kind == .metallicLattice)
            #expect(scene.isMetallic)
            // A conventional FCC cell: 8 corners and 6 face centers.
            #expect(scene.atoms.count == 14, "\(symbol) cell has \(scene.atoms.count) atoms")
            #expect(scene.coordination == 12)
            #expect(scene.representationLabel == "Representative crystal unit cell")
            #expect(!scene.isSimplified)
        }
    }

    @Test("Iron is body-centered cubic at ordinary conditions, with the FCC form offered as an allotrope")
    func ironIsBCC() {
        let iron = entry("Fe")
        #expect(iron.primary.representationKind == .bcc)
        #expect(iron.alternatives.first?.representationKind == .fcc)
        let alpha = form("Fe")
        #expect(alpha.kind == .metallicLattice)
        // 8 corners plus the body center.
        #expect(alpha.atoms.count == 9)
        #expect(alpha.coordination == 8)
        #expect(alpha.allotropeName?.contains("α") == true)
        let gamma = form("Fe", index: 1)
        #expect(gamma.atoms.count == 14)
        #expect(gamma.allotropeName?.contains("γ") == true)
        // The two really are different pictures.
        #expect(alpha.id != gamma.id)
        #expect(alpha.nodes.count != gamma.nodes.count)
    }

    @Test("Magnesium is hexagonal close-packed")
    func magnesiumIsHCP() {
        #expect(entry("Mg").primary.representationKind == .hcp)
        let scene = form("Mg")
        #expect(scene.kind == .metallicLattice)
        // A seven-atom hexagonal layer with three atoms above and three below.
        #expect(scene.atoms.count == 13)
        #expect(scene.coordination == 12)
        // The central atom of the prism touches twelve neighbors.
        let center = scene.atoms.min { magnitude($0.position) < magnitude($1.position) }
        let contacts = scene.bonds.filter { $0.from == center?.id || $0.to == center?.id }.count
        #expect(contacts == 12, "the HCP center atom should show 12 contacts, found \(contacts)")
    }

    @Test("Silicon and germanium are diamond cubic with real covalent bonds")
    func siliconIsDiamondCubic() {
        for symbol in ["Si", "Ge"] {
            #expect(entry(symbol).primary.representationKind == .diamondCubic)
            let scene = form(symbol)
            #expect(scene.kind == .covalentNetwork)
            #expect(!scene.isMetallic)
            // 8 corners, 6 face centers, 4 interior atoms.
            #expect(scene.atoms.count == 18)
            #expect(scene.bonds.allSatisfy { $0.isDiscreteBond })
            // Each interior atom is bonded to four neighbors.
            let interior = scene.atoms.filter { atom in
                scene.bonds.filter { $0.from == atom.id || $0.to == atom.id }.count == 4
            }
            #expect(interior.count == 4, "\(symbol) should have four fully bonded interior atoms")
        }
    }

    @Test("Carbon is graphite by default and offers diamond as an allotrope")
    func carbonAllotropes() {
        let carbon = entry("C")
        #expect(carbon.primary.representationKind == .graphite)
        #expect(carbon.alternatives.map(\.representationKind) == [.diamondCubic])
        let options = StructureSceneBuilder.representations(for: TestCatalog.element("C"))
        #expect(options.map(\.title) == ["Graphite", "Diamond", "Atom"])
        let graphite = form("C")
        // Two layers with no struts between them: only weak forces hold them.
        #expect(graphite.atoms.count == 24)
        let layerHeights = Set(graphite.atoms.map { Int(($0.position.y * 100).rounded()) })
        #expect(layerHeights.count == 2)
        for bond in graphite.bonds {
            guard let a = graphite.node(id: bond.from), let b = graphite.node(id: bond.to) else { continue }
            #expect(abs(a.position.y - b.position.y) < 0.001, "graphite must not bond across layers")
        }
        #expect(form("C", index: 1).atoms.count == 18)
    }

    @Test("Phosphorus and tin name their allotropes instead of pretending to have one form")
    func namedAllotropes() {
        #expect(entry("P").primary.allotropeName?.contains("White") == true)
        #expect(entry("P").alternatives.first?.allotropeName == "Black phosphorus")
        #expect(entry("Sn").primary.allotropeName?.contains("White") == true)
        #expect(entry("Sn").alternatives.first?.allotropeName?.contains("Gray") == true)
        #expect(form("P").atoms.count == 4)
        #expect(form("P", index: 1).kind == .covalentNetwork)
        #expect(form("Sn").kind == .metallicLattice)
        #expect(form("Sn", index: 1).kind == .covalentNetwork)
    }

    @Test("Nitrogen has a triple bond and oxygen a double bond")
    func realBondOrders() {
        #expect(entry("N").primary.bondOrders == [3])
        #expect(entry("O").primary.bondOrders == [2])
        #expect(form("N").bonds.first?.order == .triple)
        #expect(form("O").bonds.first?.order == .double)
        #expect(form("H").bonds.first?.order == .single)
    }

    @Test("The noble gases are monatomic and never bonded")
    func nobleGasesAreMonatomic() {
        for symbol in ["He", "Ne", "Ar", "Kr", "Xe", "Rn"] {
            #expect(entry(symbol).primary.representationKind == .monatomicGas, "\(symbol)")
            #expect(entry(symbol).primary.bondOrders == nil)
            #expect(form(symbol).bonds.isEmpty)
        }
    }

    @Test("Mercury is a liquid metal and bromine a molecular liquid, not rigid crystals")
    func liquidsAreLiquids() {
        #expect(entry("Hg").primary.representationKind == .liquidMetal)
        #expect(entry("Hg").primary.phase == .liquid)
        let mercury = form("Hg")
        #expect(mercury.kind == .liquid)
        #expect(mercury.isMetallic)
        #expect(mercury.bonds.isEmpty, "a liquid has no fixed neighbors to draw")
        #expect(mercury.isSimplified)
        #expect(entry("Br").primary.representationKind == .molecularLiquid)
        #expect(form("Br").kind == .liquid)
    }

    @Test("Sulfur is S₈ and white phosphorus P₄")
    func molecularSolids() {
        #expect(entry("S").primary.representationKind == .molecularCrystal)
        #expect(form("S").atoms.count == 8)
        #expect(form("S").kind == .molecularCrystal)
        #expect(form("P").kind == .molecularCrystal)
    }

    @Test("Superheavy elements are never given a confident bulk lattice")
    func superheaviesAreUnknown() {
        for number in 100...118 {
            let entry = structures.entry(atomicNumber: number)
            #expect(entry.isUnknown, "element \(number) has never been made in bulk")
            let element = TestCatalog.shared.element(atomicNumber: number)
            guard let element else { continue }
            let options = StructureSceneBuilder.representations(for: element)
            #expect(options.map(\.representation) == [.atom], "\(element.symbol) should offer only the atom")
            let scene = StructureSceneBuilder.scene(for: element, representation: .form(0))
            #expect(scene.kind == .atomModel, "\(element.symbol) must not be drawn as a lattice")
            #expect(scene.representationLabel == "Bulk structure not established")
            #expect(scene.detail == "Bulk crystal structure not established")
        }
        #expect(entry("At").isUnknown)
        #expect(entry("Fr").isUnknown)
    }

    @Test("Polonium is the one simple cubic element")
    func poloniumIsSimpleCubic() {
        #expect(entry("Po").primary.representationKind == .simpleCubic)
        #expect(form("Po").atoms.count == 8)
        #expect(form("Po").coordination == 6)
        let others = catalog.elements.filter {
            structures.entry(atomicNumber: $0.atomicNumber).primary.representationKind == .simpleCubic
        }
        #expect(others.map(\.symbol) == ["Po"])
    }

    @Test("Explicit cells draw the real connectivity: gallium pairs, tin's four-plus-two, iodine molecules")
    func explicitCellsAreRight() {
        let gallium = form("Ga")
        #expect(gallium.isMetallic)
        // Every atom in the cell touches exactly one partner: the Ga₂ dimer.
        for atom in gallium.atoms {
            let contacts = gallium.bonds.filter { $0.from == atom.id || $0.to == atom.id }.count
            #expect(contacts <= 1, "gallium should show dimers, not a network")
        }
        #expect(gallium.bonds.count >= 2)

        let iodine = form("I")
        #expect(iodine.kind == .molecularCrystal)
        #expect(iodine.bonds.allSatisfy { $0.isDiscreteBond })
        for atom in iodine.atoms {
            let bonds = iodine.bonds.filter { $0.from == atom.id || $0.to == atom.id }.count
            #expect(bonds <= 1, "an iodine atom belongs to one I₂ molecule")
        }

        let uranium = form("U")
        #expect(uranium.kind == .metallicLattice)
        #expect(uranium.atoms.count > 4)
    }

    @Test("Metals carry their own color: gold is gold, copper copper, silver silver")
    func metalTints() {
        #expect(ElementRenderPalette.tintHex(atomicNumber: 79) == 0xE0B44A)
        #expect(ElementRenderPalette.tintHex(atomicNumber: 29) == 0xC97F4A)
        #expect(ElementRenderPalette.tintHex(atomicNumber: 47) == 0xCDD1D6)
        #expect(form("Au").nodes.allSatisfy { $0.tintHex == 0xE0B44A })
        // Oxygen is drawn in the conventional red, nitrogen blue.
        #expect(form("O").nodes.allSatisfy { $0.tintHex == 0xE8412F })
        #expect(form("N").nodes.allSatisfy { $0.tintHex == 0x3A64E6 })
        // Every established form has a tint, so no element renders in a
        // family color by accident.
        for element in catalog.elements where !structures.entry(atomicNumber: element.atomicNumber).isUnknown {
            let scene = StructureSceneBuilder.scene(for: element, representation: .form(0))
            #expect(scene.atoms.allSatisfy { $0.tintHex != nil }, "\(element.symbol) has untinted atoms")
        }
    }

    @Test("Every scene says what it is, and a cell is not called simplified")
    func honestLabelsEverywhere() {
        for element in catalog.elements {
            for option in StructureSceneBuilder.representations(for: element) {
                let scene = StructureSceneBuilder.scene(for: element, representation: option.representation)
                #expect(!scene.representationLabel.isEmpty, "\(element.symbol) has no honesty label")
                #expect(scene.representationLabel != "Simplified atomic model" || scene.kind == .atomModel)
                if scene.kind == .atomModel {
                    #expect(scene.isSimplified)
                }
                if scene.representationLabel == "Representative crystal unit cell" {
                    #expect(!scene.isSimplified, "\(element.symbol): a unit cell is drawn whole")
                }
            }
        }
    }

    @Test("The detail-page preview and the explorer build from the same source")
    func previewAndExplorerAgree() {
        // Both call StructureSceneBuilder.scene(for:representation:) with the
        // first representation; there is no second code path. This pins that
        // the call is deterministic, so the two can never show different
        // pictures of the same element.
        for element in catalog.elements {
            let first = StructureSceneBuilder.representations(for: element).first?.representation ?? .atom
            let preview = StructureSceneBuilder.scene(for: element, representation: first)
            let explorer = StructureSceneBuilder.scene(for: element, representation: first)
            #expect(preview == explorer, "\(element.symbol) preview and explorer differ")
        }
    }

    @Test("Lattice parameters format for display")
    func latticeParameterSummary() {
        let cubic = LatticeParameters(a: 4.078, b: nil, c: nil, alpha: nil, beta: nil, gamma: nil)
        #expect(cubic.summary == "a = 4.078 Å")
        let hexagonal = LatticeParameters(a: 3.209, b: nil, c: 5.211, alpha: nil, beta: nil, gamma: nil)
        #expect(hexagonal.summary == "a = 3.209 Å, c = 5.211 Å")
        #expect(entry("Au").primary.latticeSummary?.contains("Fm-3m") == true)
        #expect(entry("Au").primary.latticeSummary?.contains("4.078") == true)
    }

    @Test("The facts for a lattice atom name the lattice and the coordination")
    func latticeAtomFacts() {
        let gold = TestCatalog.element("Au")
        let scene = form("Au")
        guard let atom = scene.atoms.first else {
            Issue.record("gold has no atoms")
            return
        }
        let facts = StructureFactsBuilder.facts(for: .node(atom.id), in: scene, element: gold)
        #expect(facts?.rows.contains { $0.label == "Coordination" && $0.value.contains("12") } == true)
        #expect(facts?.rows.contains { $0.label == "Structure" } == true)
    }

    private func magnitude(_ vector: SIMD3<Float>) -> Float {
        (vector.x * vector.x + vector.y * vector.y + vector.z * vector.z).squareRoot()
    }
}
