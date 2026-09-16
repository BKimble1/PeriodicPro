import CoreGraphics
import Foundation
import Testing
@testable import PeriodicPro

@Suite("Element artwork")
struct ElementArtworkTests {
    private let catalog = TestCatalog.shared

    @Test("Every one of the 118 elements resolves to a treatment")
    func everyElementResolves() {
        #expect(catalog.count == 118)
        for element in catalog.elements {
            let descriptor = ElementArtwork.descriptor(for: element)
            #expect(descriptor.formCount > 0,
                    "\(element.symbol) resolved to artwork that draws nothing")
        }
    }

    @Test("Artwork is stable: the same element always resolves identically")
    func resolutionIsDeterministic() {
        for element in catalog.elements {
            let first = ElementArtwork.descriptor(for: element)
            let second = ElementArtwork.descriptor(for: element)
            #expect(first == second)
        }
    }

    @Test("Two elements never share a seed, so no two look alike by accident")
    func seedsAreDistinct() {
        let seeds = catalog.elements.map { ElementArtwork.descriptor(for: $0).seed }
        #expect(Set(seeds).count == seeds.count)
    }

    @Test("The elements people can picture get the treatment they expect")
    func namedElementsLookRight() {
        let expectations: [String: ElementArtworkKind] = [
            "Au": .nuggets,
            "Cu": .nuggets,
            "C": .facetedGems,
            "Si": .facetedGems,
            "O": .pairedSpheres,
            "Hg": .droplets,
            "S": .crystalShards,
            "Na": .metallicSheen,
            "Fe": .lattice,
        ]
        for (symbol, expected) in expectations {
            #expect(ElementArtwork.kind(for: TestCatalog.element(symbol)) == expected,
                    "\(symbol) should be drawn as \(expected.rawValue)")
        }
    }

    @Test("Noble gases glow and superheavies stay abstract")
    func ruleBasedFallbacksAreSensible() {
        #expect(ElementArtwork.kind(for: TestCatalog.element("Ne")) == .luminousGas)
        #expect(ElementArtwork.kind(for: TestCatalog.element("Ar")) == .luminousGas)
        // Nobody has ever seen bulk oganesson, so it must not be drawn as a
        // confident lump of metal.
        #expect(ElementArtwork.kind(for: TestCatalog.element("Og")) == .orbitalArcs)
        #expect(ElementArtwork.kind(for: TestCatalog.element("Lv")) == .orbitalArcs)
    }

    @Test("Artwork stays decoration: never more than a third opaque")
    func prominenceIsRestrained() {
        #expect(ElementArtworkProminence.hero.opacity <= 0.35)
        #expect(ElementArtworkProminence.card.opacity <= ElementArtworkProminence.hero.opacity)
    }
}

@Suite("Structure scenes")
struct StructureSceneTests {
    private let catalog = TestCatalog.shared

    private func allScenes() -> [(ChemicalElement, StructureScene)] {
        catalog.elements.flatMap { element in
            StructureSceneBuilder.representations(for: element).map { option in
                (element, StructureSceneBuilder.scene(for: element, representation: option.representation))
            }
        }
    }

    /// The primary elemental form of an element.
    private func form(_ symbol: String) -> StructureScene {
        StructureSceneBuilder.scene(for: TestCatalog.element(symbol), representation: .form(0))
    }

    @Test("Every element produces a scene with something in it")
    func noEmptyScenes() {
        for (element, scene) in allScenes() {
            #expect(!scene.nodes.isEmpty,
                    "\(element.symbol) \(scene.kind.rawValue) has no nodes at all")
        }
    }

    @Test("Node identifiers are unique within a scene")
    func identifiersAreUnique() {
        for (element, scene) in allScenes() {
            let nodeIDs = scene.nodes.map(\.id)
            #expect(Set(nodeIDs).count == nodeIDs.count,
                    "\(element.symbol) has duplicate node ids")
            let bondIDs = scene.bonds.map(\.id)
            #expect(Set(bondIDs).count == bondIDs.count,
                    "\(element.symbol) has duplicate bond ids")
        }
    }

    @Test("Every bond joins two nodes that exist, and never joins one to itself")
    func bondsReferenceRealNodes() {
        for (element, scene) in allScenes() {
            let ids = Set(scene.nodes.map(\.id))
            for bond in scene.bonds {
                #expect(ids.contains(bond.from), "\(element.symbol): bond from a missing node")
                #expect(ids.contains(bond.to), "\(element.symbol): bond to a missing node")
                #expect(bond.from != bond.to, "\(element.symbol): bond from a node to itself")
            }
        }
    }

    @Test("Geometry is finite and normalized, so nothing renders off-screen")
    func geometryIsSane() {
        for (element, scene) in allScenes() {
            for node in scene.nodes {
                #expect(node.position.x.isFinite && node.position.y.isFinite
                        && node.position.z.isFinite,
                        "\(element.symbol) has a node at a non-finite position")
                #expect(node.radius > 0, "\(element.symbol) has a node with no size")
            }
            // Every scene is scaled to a bounding radius of 1 so one camera
            // distance frames all of them.
            #expect(abs(scene.boundingRadius - 1) < 0.01,
                    "\(element.symbol) \(scene.kind.rawValue) is not normalized (radius \(scene.boundingRadius))")
        }
    }

    @Test("The scene knows which element it belongs to")
    func sceneCarriesItsElement() {
        for (element, scene) in allScenes() {
            #expect(scene.atomicNumber == element.atomicNumber)
            #expect(scene.symbol == element.symbol)
            #expect(scene.elementName == element.name)
        }
    }

    @Test("Every structure kind the dataset contains is actually produced")
    func everyKindIsReachable() {
        let kinds = Set(allScenes().map { $0.1.kind })
        #expect(kinds.contains(.diatomicMolecule))
        #expect(kinds.contains(.molecularCrystal))
        #expect(kinds.contains(.metallicLattice))
        #expect(kinds.contains(.covalentNetwork))
        #expect(kinds.contains(.monatomicGas))
        #expect(kinds.contains(.liquid))
        #expect(kinds.contains(.atomModel))
    }

    // MARK: - Chemistry

    @Test("Diatomic bond orders are the real ones")
    func diatomicBondOrders() {
        let expectations: [String: StructureBondOrder] = [
            "H": .single, "N": .triple, "O": .double,
            "F": .single, "Cl": .single,
        ]
        for (symbol, order) in expectations {
            let scene = form(symbol)
            #expect(scene.kind == .diatomicMolecule)
            #expect(scene.atoms.count == 2, "\(symbol) is not drawn as two atoms")
            #expect(scene.bonds.count == 1)
            #expect(scene.bonds.first?.order == order,
                    "\(symbol) should have a \(order.displayName.lowercased())")
        }
        // Bromine is a liquid of Br₂ molecules: several molecules, each with
        // one single bond, and no bonds between them.
        let bromine = form("Br")
        #expect(bromine.kind == .liquid)
        #expect(bromine.atoms.count == bromine.bonds.count * 2)
        #expect(bromine.bonds.allSatisfy { $0.order == .single && $0.isDiscreteBond })
    }

    @Test("A metallic lattice is never described as a molecule or as bonds")
    func latticesAreHonest() {
        for element in catalog.elements {
            let entry = StructureSceneBuilder.entry(for: element)
            guard entry.primary.representationKind.isMetallic else { continue }
            let scene = StructureSceneBuilder.scene(for: element, representation: .form(0))
            #expect(scene.kind == .metallicLattice || scene.kind == .liquid,
                    "\(element.symbol) is metallic but drawn as \(scene.kind.rawValue)")
            #expect(scene.isMetallic, "\(element.symbol) should render as metal")
            #expect(scene.bonds.allSatisfy { !$0.isDiscreteBond },
                    "\(element.symbol): a lattice contact must not be marked a discrete bond")
            #expect(!scene.caption.lowercased().contains("molecule"),
                    "\(element.symbol): a lattice must not be called a molecule")
        }
    }

    @Test("A noble gas is shown as separate atoms, never an invented molecule")
    func nobleGasesAreSingleAtoms() {
        for symbol in ["He", "Ne", "Ar", "Kr", "Xe", "Rn"] {
            let element = TestCatalog.element(symbol)
            let options = StructureSceneBuilder.representations(for: element)
            #expect(options.map(\.representation) == [.form(0), .atom],
                    "\(symbol) should offer the gas and the atom")
            let gas = StructureSceneBuilder.scene(for: element, representation: .form(0))
            #expect(gas.kind == .monatomicGas)
            #expect(gas.atoms.count > 1, "\(symbol) should show several separate atoms")
            #expect(gas.bonds.isEmpty, "\(symbol) must not be drawn with bonds")
            let atom = StructureSceneBuilder.scene(for: element, representation: .atom)
            #expect(atom.kind == .atomModel)
            #expect(atom.bonds.isEmpty)
        }
    }

    @Test("Named molecular structures have the right number of atoms")
    func namedStructuresAreRight() {
        let expectations: [String: Int] = [
            "P": 4,    // P₄ tetrahedron
            "S": 8,    // S₈ crown ring
            "B": 12,   // B₁₂ icosahedron
        ]
        for (symbol, atomCount) in expectations {
            #expect(form(symbol).atoms.count == atomCount,
                    "\(symbol) should be built from \(atomCount) atoms")
        }
    }

    @Test("Selenium and tellurium are open chains, not closed rings")
    func chainsStayOpen() {
        for symbol in ["Se", "Te"] {
            let scene = form(symbol)
            // An open chain of n atoms has n-1 links; a ring would have n.
            #expect(scene.bonds.count == scene.atoms.count - 1,
                    "\(symbol) should be an open chain")
            #expect(scene.isSimplified)
        }
    }

    // MARK: - Atom model

    @Test("The atom model counts protons and electrons correctly")
    func atomModelParticleCounts() {
        for symbol in ["H", "He", "C", "O", "Na", "Fe", "Au"] {
            let element = TestCatalog.element(symbol)
            let scene = StructureSceneBuilder.scene(for: element, representation: .atom)
            let electrons = scene.nodes.filter { $0.role == .electron }.count
            let protons = scene.nodes.filter { $0.role == .proton }.count
            let neutrons = scene.nodes.filter { $0.role == .neutron }.count

            // Electrons are always exact: the shell counts are the whole point
            // of the picture, and there are never more than 118 of them.
            #expect(electrons == element.shellElectrons.reduce(0, +),
                    "\(symbol) should show every electron in its shells")
            #expect(scene.isSimplified, "the atom model is always labeled a simplification")

            if scene.nucleonSampleNote == nil {
                // A nucleus small enough to draw in full is drawn in full.
                #expect(protons == element.atomicNumber,
                        "\(symbol) should show \(element.atomicNumber) protons")
            } else {
                // Iron's 56 nucleons and gold's 197 are past the cap, so the
                // nucleus is a proportional sample — and must say so rather
                // than quietly showing the wrong number.
                #expect(protons + neutrons == StructureSceneBuilder.maximumDrawnNucleons)
                #expect(protons < element.atomicNumber)
                #expect(protons > 0, "a sampled nucleus must still contain protons")
            }
        }
    }

    @Test("A sampled nucleus keeps the real proton-to-neutron proportion")
    func sampledNucleiStayProportional() {
        for symbol in ["Fe", "Au", "U", "Og"] {
            let element = TestCatalog.element(symbol)
            let scene = StructureSceneBuilder.scene(for: element, representation: .atom)
            let protons = Double(scene.nodes.filter { $0.role == .proton }.count)
            let neutrons = Double(scene.nodes.filter { $0.role == .neutron }.count)
            guard protons + neutrons > 0 else {
                Issue.record("\(symbol) drew no nucleons")
                continue
            }
            let massNumber = Double(max(element.atomicNumber,
                                        Int(element.atomicMass.rounded())))
            let realShare = Double(element.atomicNumber) / massNumber
            let drawnShare = protons / (protons + neutrons)
            #expect(abs(drawnShare - realShare) < 0.03,
                    "\(symbol): drew \(drawnShare) protons but the real share is \(realShare)")
        }
    }

    @Test("A heavy nucleus is sampled, and the scene says so")
    func heavyNucleiAreLabeledAsSamples() {
        let scene = StructureSceneBuilder.scene(
            for: TestCatalog.element("U"), representation: .atom
        )
        let nucleons = scene.nodes.filter { $0.role == .proton || $0.role == .neutron }.count
        #expect(nucleons == StructureSceneBuilder.maximumDrawnNucleons)
        #expect(scene.nucleonSampleNote != nil,
                "a sampled nucleus must say that it is a sample")
    }

    @Test("Electrons are spread over a sphere, not marched around a ring")
    func electronsAreNotOnOrbits() {
        // A ring would leave every electron in one shell at the same y.
        let scene = StructureSceneBuilder.scene(
            for: TestCatalog.element("Ar"), representation: .atom
        )
        let outerShell = scene.electrons.filter { $0.shellIndex == 3 }
        #expect(outerShell.count > 2)
        let distinctHeights = Set(outerShell.map { Int(($0.position.y * 100).rounded()) })
        #expect(distinctHeights.count > 1,
                "electrons in a shell must not all sit at the same height")
        #expect(scene.caption.lowercased().contains("not follow fixed paths")
                || scene.caption.lowercased().contains("do not follow"),
                "the atom model must say electrons do not follow fixed paths")
    }

    @Test("Nucleon roles always total the number asked for")
    func nucleonRolesAreExact() {
        for (protons, neutrons) in [(1, 0), (6, 6), (22, 22), (0, 5), (3, 1), (1, 40)] {
            let roles = StructureSceneBuilder.interleavedNucleons(
                protons: protons, neutrons: neutrons
            )
            #expect(roles.count == protons + neutrons)
            #expect(roles.filter { $0 == .proton }.count == protons)
            #expect(roles.filter { $0 == .neutron }.count == neutrons)
        }
    }

    // MARK: - Selection plumbing

    @Test("Entity names round-trip to the selection they came from")
    func entityNamesRoundTrip() {
        for id in [0, 1, 7, 42, 161] {
            #expect(StructureEntityName.selection(for: StructureEntityName.node(id)) == .node(id))
            #expect(StructureEntityName.selection(for: StructureEntityName.bond(id)) == .bond(id))
        }
        #expect(StructureEntityName.selection(for: StructureEntityName.root) == .none)
        #expect(StructureEntityName.selection(for: "strut") == .none)
        #expect(StructureEntityName.selection(for: "node-") == .none)
        #expect(StructureEntityName.selection(for: "node-abc") == .none)
    }

    @Test("Every scene offers at least one selectable part")
    func everySceneHasParts() {
        for (element, scene) in allScenes() {
            let parts = StructurePartList.parts(of: scene)
            #expect(!parts.isEmpty, "\(element.symbol) \(scene.kind.rawValue) offers nothing to tap")
            let ids = parts.map(\.selection)
            #expect(Set(ids).count == ids.count, "\(element.symbol) lists a part twice")
            // Every listed part must actually exist in the scene, or tapping the
            // chip would select nothing.
            for part in parts {
                switch part.selection {
                case .node(let id): #expect(scene.node(id: id) != nil)
                case .bond(let id): #expect(scene.bond(id: id) != nil)
                case .none: Issue.record("a part list entry selected nothing")
                }
            }
        }
    }

    @Test("Projected geometry lands inside the canvas at every rotation")
    func projectionStaysOnScreen() {
        let size = CGSize(width: 320, height: 320)
        let scene = StructureSceneBuilder.scene(
            for: TestCatalog.element("Au"), representation: .form(0)
        )
        for step in 0..<12 {
            let projection = StructureProjection(
                yaw: Double(step) / 12 * 2 * .pi,
                pitch: StructureProjection.clampPitch(Double(step) - 6),
                zoom: 1,
                size: size
            )
            for node in scene.nodes {
                let placed = projection.project(node.position)
                #expect(placed.point.x.isFinite && placed.point.y.isFinite)
                #expect(placed.scale > 0)
                // The camera sits four units back and no scene reaches past one,
                // so nothing can cross the camera plane and invert.
                #expect(placed.depth < StructureProjection.cameraDistance)
                #expect(placed.point.x > -size.width && placed.point.x < size.width * 2)
                #expect(placed.point.y > -size.height && placed.point.y < size.height * 2)
            }
        }
    }

    @Test("The draw list is sorted back to front")
    func drawOrderIsPainterly() {
        let scene = StructureSceneBuilder.scene(
            for: TestCatalog.element("S"), representation: .form(0)
        )
        let projection = StructureProjection(yaw: 0.6, pitch: 0.3, zoom: 1,
                                             size: CGSize(width: 200, height: 200))
        let items = StructureDrawList.items(scene: scene, projection: projection)
        #expect(items.count == scene.nodes.count + scene.bonds.count)
        for (earlier, later) in zip(items, items.dropFirst()) {
            #expect(earlier.depth <= later.depth)
        }
    }

    @Test("Zoom and pitch are clamped, so the model can never be lost")
    func cameraLimitsHold() {
        #expect(StructureProjection.clampZoom(0.01) == StructureProjection.zoomRange.lowerBound)
        #expect(StructureProjection.clampZoom(99) == StructureProjection.zoomRange.upperBound)
        #expect(StructureProjection.clampPitch(10) == StructureProjection.pitchLimit)
        #expect(StructureProjection.clampPitch(-10) == -StructureProjection.pitchLimit)
    }
}

@Suite("Structure facts")
struct StructureFactsTests {
    @Test("A lattice contact is never described as a bond")
    func latticeContactsAreNotBonds() {
        let gold = TestCatalog.element("Au")
        let scene = StructureSceneBuilder.scene(for: gold, representation: .form(0))
        guard let bond = scene.bonds.first else {
            Issue.record("gold's lattice should have contacts to select")
            return
        }
        let facts = StructureFactsBuilder.facts(
            for: .bond(bond.id), in: scene, element: gold
        )
        #expect(facts?.title == "Nearest neighbors")
        let text = ((facts?.title ?? "") + (facts?.subtitle ?? "")).lowercased()
        #expect(!text.contains("bond"), "a lattice contact must not be titled a bond")
    }

    @Test("A real bond reports the right number of shared electrons")
    func bondFactsAreRight() {
        let oxygen = TestCatalog.element("O")
        let scene = StructureSceneBuilder.scene(for: oxygen, representation: .form(0))
        let facts = StructureFactsBuilder.facts(
            for: .bond(scene.bonds[0].id), in: scene, element: oxygen
        )
        #expect(facts?.title == "Double bond")
        #expect(facts?.rows.contains { $0.label == "Shared electrons" && $0.value == "4" } == true)
    }

    @Test("An electron is never described as orbiting")
    func electronsAreDescribedHonestly() {
        let carbon = TestCatalog.element("C")
        let scene = StructureSceneBuilder.scene(for: carbon, representation: .atom)
        guard let electron = scene.electrons.first else {
            Issue.record("carbon's atom model should contain electrons")
            return
        }
        let facts = StructureFactsBuilder.facts(
            for: .node(electron.id), in: scene, element: carbon
        )
        let text = (facts?.rows.map(\.value).joined(separator: " ") ?? "").lowercased()
        #expect(text.contains("not on a fixed path"))
        #expect(!text.contains("orbit"))
    }

    @Test("Proton and neutron panels state charge, place and mass")
    func nucleonFactsAreComplete() {
        let iron = TestCatalog.element("Fe")
        let scene = StructureSceneBuilder.scene(for: iron, representation: .atom)
        for role in [StructureNodeRole.proton, .neutron] {
            guard let node = scene.nodes.first(where: { $0.role == role }) else {
                Issue.record("iron's nucleus should contain a \(role.rawValue)")
                continue
            }
            let facts = StructureFactsBuilder.facts(for: .node(node.id), in: scene, element: iron)
            let labels = facts?.rows.map(\.label) ?? []
            #expect(labels.contains("Charge"))
            #expect(labels.contains("Location"))
            #expect(labels.contains("Mass"))
        }
    }

    @Test("The neutron count is never stated as if it were fixed")
    func neutronCountsAcknowledgeIsotopes() {
        let chlorine = TestCatalog.element("Cl")
        let scene = StructureSceneBuilder.scene(for: chlorine, representation: .atom)
        guard let neutron = scene.nodes.first(where: { $0.role == .neutron }) else {
            Issue.record("chlorine's nucleus should contain neutrons")
            return
        }
        let facts = StructureFactsBuilder.facts(
            for: .node(neutron.id), in: scene, element: chlorine
        )
        let value = facts?.rows.last?.value ?? ""
        #expect(value.contains("isotopes"),
                "the neutron count must say it depends on the isotope")
    }

    @Test("The VoiceOver summary describes every scene")
    func summariesExistForEveryElement() {
        for element in TestCatalog.shared.elements {
            for option in StructureSceneBuilder.representations(for: element) {
                let scene = StructureSceneBuilder.scene(for: element, representation: option.representation)
                let summary = StructureFactsBuilder.summary(of: scene, element: element)
                #expect(summary.count > 20, "\(element.symbol) has no usable spoken summary")
                #expect(summary.contains(element.name))
            }
        }
    }
}
