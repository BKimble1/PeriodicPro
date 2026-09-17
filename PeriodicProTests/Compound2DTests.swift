import CoreGraphics
import Foundation
import Testing
@testable import PeriodicPro

/// The 2D depiction: what it draws, what it hides, and above all what it is
/// allowed to call itself.
@Suite("2D structure drawings")
struct Compound2DLayoutTests {
    private let catalog = TestCatalog.shared

    private func drawing(_ name: String) -> Compound2DDrawing {
        Compound2DLayout.drawing(for: TestCompounds.compound(name), catalog: catalog)
    }

    @Test("Each compound gets the depiction its chemistry actually supports")
    func representations() {
        #expect(drawing("Ethanol").representation == .skeletal)
        #expect(drawing("Dimethyl ether").representation == .skeletal)
        #expect(drawing("Acetic acid").representation == .skeletal)
        #expect(drawing("Caffeine").representation == .skeletal)
        #expect(drawing("Benzene").representation == .skeletal)
        // One carbon is not a skeleton, and neither is no carbon at all.
        #expect(drawing("Water").representation == .structural)
        #expect(drawing("Carbon dioxide").representation == .structural)
        #expect(drawing("Ammonia").representation == .structural)
        // And a lattice has no molecule to draw.
        #expect(drawing("Sodium chloride").representation == .formulaUnit)
    }

    @Test("Sodium chloride is never called a skeletal formula")
    func honestLabels() {
        let salt = drawing("Sodium chloride")
        #expect(salt.representation.label == "Formula unit")
        #expect(!salt.representation.label.lowercased().contains("skeletal"))
        #expect(!salt.hasGeometry)
        #expect(salt.formula == "NaCl")
        #expect(Compound2DRepresentation.skeletal.label == "Skeletal formula")
        #expect(Compound2DRepresentation.structural.label == "2D structure")
    }

    @Test("Line-angle notation hides the carbon labels and the hydrogens on carbon")
    func skeletalHidesImplicitHydrogens() {
        let ethanol = drawing("Ethanol")
        // C₂H₆O: two carbons, one oxygen drawn; the six hydrogens are implied.
        #expect(ethanol.atoms.count == 3)
        let carbons = ethanol.atoms.filter { $0.atomicNumber == 6 }
        #expect(carbons.count == 2)
        #expect(carbons.allSatisfy { $0.label == nil }, "a carbon vertex carries no label")
        let oxygen = ethanol.atoms.first { $0.atomicNumber == 8 }
        #expect(oxygen?.label == "OH", "the hydroxyl hydrogen is written into the oxygen's label")
        #expect(ethanol.bonds.count == 2)
    }

    @Test("A structural drawing keeps every atom, hydrogens included")
    func structuralKeepsHydrogens() {
        let water = drawing("Water")
        #expect(water.atoms.count == 3)
        #expect(water.atoms.filter { $0.atomicNumber == 1 }.count == 2)
        #expect(water.atoms.allSatisfy { $0.label != nil })
        #expect(water.atoms.contains { $0.label == "O" })
        #expect(water.bonds.count == 2)
        #expect(water.bonds.allSatisfy { $0.order == 1 })
    }

    @Test("Double and triple bonds survive into the drawing")
    func bondOrders() {
        // O=C=O: two double bonds, and nothing else.
        let carbonDioxide = drawing("Carbon dioxide")
        #expect(carbonDioxide.bonds.count == 2)
        #expect(carbonDioxide.bonds.allSatisfy { $0.order == 2 })

        // Acetic acid has exactly one C=O.
        let acid = drawing("Acetic acid")
        #expect(acid.bonds.filter { $0.order == 2 }.count == 1)

        // Benzene's Kekulé structure alternates around the ring.
        let benzene = drawing("Benzene")
        #expect(benzene.bonds.filter { $0.order == 2 }.count == 3)
        #expect(benzene.bonds.filter { $0.order == 1 }.count == 3)

        // A triple bond drawn from a record that has one.
        let nitrogen = CompoundStructure(
            is3D: false, source: .pubChem2D, note: nil,
            atoms: [
                CompoundAtom(id: 1, atomicNumber: 7, x: 0, y: 0, z: 0, formalCharge: 0),
                CompoundAtom(id: 2, atomicNumber: 7, x: 1.1, y: 0, z: 0, formalCharge: 0),
            ],
            bonds: [CompoundBond(id: 1, from: 1, to: 2, order: 3, isContact: false)]
        )
        let drawn = Compound2DLayout.drawing(for: compound(with: nitrogen), catalog: catalog)
        #expect(drawn.bonds.first?.order == 3)
    }

    @Test("Every drawn point lands inside the unit square, and geometry is the record's own")
    func projection() {
        for name in ["Water", "Ethanol", "Caffeine", "Benzene", "Glucose", "Acetic acid"] {
            let drawn = drawing(name)
            for atom in drawn.atoms {
                #expect(atom.point.x >= -0.001 && atom.point.x <= 1.001, "\(name) x out of range")
                #expect(atom.point.y >= -0.001 && atom.point.y <= 1.001, "\(name) y out of range")
            }
        }

        // For a molecule that is genuinely flat, the plane of best fit is its
        // own plane, so no two atoms may land on top of each other. This is
        // not asserted for a three-dimensional molecule, where an honest
        // orthographic projection can legitimately put one atom behind
        // another.
        for name in ["Water", "Carbon dioxide", "Benzene", "Acetic acid"] {
            let atoms = drawing(name).atoms
            for (index, atom) in atoms.enumerated() {
                for other in atoms[(index + 1)...] {
                    let distance = hypot(atom.point.x - other.point.x, atom.point.y - other.point.y)
                    #expect(distance > 0.02, "\(name) draws two atoms on the same spot")
                }
            }
        }
    }

    @Test("A planar molecule projects onto its own plane exactly")
    func planarProjection() {
        // Four points on the z = 3 plane, laid out as a rectangle.
        let atoms = [
            CompoundAtom(id: 1, atomicNumber: 6, x: 0, y: 0, z: 3, formalCharge: 0),
            CompoundAtom(id: 2, atomicNumber: 6, x: 2, y: 0, z: 3, formalCharge: 0),
            CompoundAtom(id: 3, atomicNumber: 6, x: 2, y: 1, z: 3, formalCharge: 0),
            CompoundAtom(id: 4, atomicNumber: 6, x: 0, y: 1, z: 3, formalCharge: 0),
        ]
        let points = Compound2DLayout.project(atoms)
        #expect(points.count == 4)
        // The rectangle is twice as wide as it is tall, and normalization
        // preserves that: the x spread is 1, the y spread is 0.5.
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let width = (xs.max() ?? 0) - (xs.min() ?? 0)
        let height = (ys.max() ?? 0) - (ys.min() ?? 0)
        #expect(abs(width - 1) < 0.01)
        #expect(abs(height - 0.5) < 0.01)
    }

    @Test("A single atom sits in the middle rather than dividing by zero")
    func degenerate() {
        let points = Compound2DLayout.project([
            CompoundAtom(id: 1, atomicNumber: 10, x: 5, y: 5, z: 5, formalCharge: 0),
        ])
        #expect(points == [CGPoint(x: 0.5, y: 0.5)])
    }

    @Test("Implicit hydrogens are written into the heteroatom's own label")
    func heteroatomLabels() {
        func oxygen(_ hydrogens: Int) -> String? {
            Compound2DLayout.label(
                for: CompoundAtom(id: 1, atomicNumber: 8, x: 0, y: 0, z: 0, formalCharge: 0),
                representation: .skeletal,
                implicitHydrogens: hydrogens,
                catalog: catalog
            )
        }
        #expect(oxygen(0) == "O")
        #expect(oxygen(1) == "OH")

        let nitrogen = Compound2DLayout.label(
            for: CompoundAtom(id: 1, atomicNumber: 7, x: 0, y: 0, z: 0, formalCharge: 0),
            representation: .skeletal,
            implicitHydrogens: 2,
            catalog: catalog
        )
        #expect(nitrogen == "NH\u{2082}", "a count of two is a real subscript, not a plain 2")

        // A carbon is the vertex; a charged one is spelled out so the charge
        // has something to sit beside.
        let carbon = CompoundAtom(id: 1, atomicNumber: 6, x: 0, y: 0, z: 0, formalCharge: 0)
        #expect(Compound2DLayout.label(for: carbon, representation: .skeletal,
                                       implicitHydrogens: 3, catalog: catalog) == nil)
        #expect(Compound2DLayout.label(for: carbon, representation: .structural,
                                       implicitHydrogens: 0, catalog: catalog) == "C")
    }

    @Test("A charge on an atom is carried into the drawing")
    func charges() {
        let structure = CompoundStructure(
            is3D: false, source: .pubChem2D, note: nil,
            atoms: [
                CompoundAtom(id: 1, atomicNumber: 7, x: 0, y: 0, z: 0, formalCharge: 1),
                CompoundAtom(id: 2, atomicNumber: 8, x: 1.2, y: 0, z: 0, formalCharge: -1),
            ],
            bonds: [CompoundBond(id: 1, from: 1, to: 2, order: 1, isContact: false)]
        )
        let drawn = Compound2DLayout.drawing(for: compound(with: structure), catalog: catalog)
        #expect(drawn.atoms.first { $0.atomicNumber == 7 }?.formalCharge == 1)
        #expect(drawn.atoms.first { $0.atomicNumber == 8 }?.formalCharge == -1)
    }

    @Test("A compound with no structure at all falls back to its formula")
    func noStructure() {
        let hypothetical = ChemicalCompound.hypothetical(composition: [79: 1, 2: 1], catalog: catalog)
        let drawn = Compound2DLayout.drawing(for: hypothetical, catalog: catalog)
        #expect(drawn.representation == .unknownStructure,
                "an unknown composition is not the same claim as a lattice")
        #expect(drawn.representation.label == "Composition")
        #expect(!drawn.hasGeometry)
        #expect(drawn.atoms.isEmpty)
    }

    /// A minimal molecular record around a structure, for the cases the
    /// bundled catalog does not happen to contain.
    private func compound(with structure: CompoundStructure) -> ChemicalCompound {
        ChemicalCompound(
            id: "test-\(structure.atoms.count)",
            pubChemCID: nil,
            preferredName: "Test compound",
            formula: "X",
            hillFormula: "X",
            iupacName: nil,
            molarMass: nil,
            canonicalSMILES: nil,
            charge: 0,
            bondingClass: .molecular,
            tags: [],
            alternateNames: [],
            summary: nil,
            classificationSource: nil,
            dataSource: .pubChem,
            isLocalCurated: false,
            lastUpdated: nil,
            structure: structure
        )
    }
}

/// The claims the structure views are allowed to make, and the ones they are
/// not. Every one of these is a way an app could quietly teach a learner
/// something false.
@Suite("What a structure may claim")
struct StructureHonestyTests {
    private let catalog = TestCompounds.catalog
    private let elements = TestCatalog.shared

    @Test("The 2D drawing and the 3D scene are the same molecule")
    func oneGraphTwoViews() throws {
        for compound in catalog.compounds where compound.hasStructure {
            let structure = try #require(compound.structure)
            let drawing = Compound2DLayout.drawing(for: compound, catalog: elements)
            guard drawing.hasGeometry else { continue }
            let scene = try #require(CompoundStructureScene.scene(for: compound, style: .ballAndStick))

            // Same atoms, in the same order, with the same elements.
            #expect(scene.nodes.count == structure.atoms.count)
            #expect(scene.nodes.compactMap(\.atomicNumber) == structure.atoms.map(\.atomicNumber))

            // And the same bonds, with the same orders. A 2D diagram showing
            // a double bond where the 3D scene shows a single one would be
            // two different molecules on one page.
            let drawn = Set(drawing.bonds.map(\.order))
            let modeled = Set(scene.bonds.map { $0.order.rawValue })
            if !drawn.isEmpty, !modeled.isEmpty {
                #expect(drawn == modeled,
                        "\(compound.preferredName): the diagram draws bond orders \(drawn.sorted()) "
                        + "and the scene models \(modeled.sorted())")
            }
        }
    }

    @Test("A flat record is never presented as a three-dimensional geometry")
    func noFabricatedConformers() throws {
        for compound in catalog.compounds {
            guard let structure = compound.structure, !structure.atoms.isEmpty else { continue }
            if structure.is3D {
                // Claiming 3D means actually having depth somewhere.
                #expect(structure.hasThreeDGeometry,
                        "\(compound.preferredName) claims a 3D record with every z at zero")
                #expect(structure.resolvedProvenance.hasThreeDCoordinates)
            } else {
                // And not claiming it means the provenance says so, so the
                // interface can tell the learner rather than guessing.
                #expect(!structure.resolvedProvenance.hasThreeDCoordinates,
                        "\(compound.preferredName) has no 3D record but reports a 3D source")
            }
        }
    }

    @Test("Sodium chloride is a lattice, not a two-atom molecule")
    func saltIsNotAMolecule() throws {
        let salt = TestCompounds.compound("Sodium chloride")
        #expect(salt.bondingClass == .ionic)
        let structure = try #require(salt.structure)
        #expect(structure.source == .curatedLattice)
        // Every join in it is a nearest-neighbor contact, not a covalent bond.
        #expect(structure.bonds.allSatisfy(\.isContact),
                "an ionic lattice has no covalent bonds to draw")
        // More than two ions, because a formula unit is not the structure.
        #expect(structure.atoms.count > 2,
                "NaCl drawn as one Na and one Cl would be a molecule, which it is not")
        // And the flat depiction calls itself a formula unit rather than a
        // skeletal formula.
        let drawing = Compound2DLayout.drawing(for: salt, catalog: elements)
        #expect(drawing.representation == .formulaUnit)
        #expect(drawing.representation.caption.contains("no discrete molecule"))
    }

    @Test("A composition with no record gets no structure at all")
    func nothingIsInventedForAMiss() {
        let composition = ChemicalCompound.hypothetical(composition: [113: 2, 8: 3], catalog: elements)
        #expect(composition.structure == nil)
        let drawing = Compound2DLayout.drawing(for: composition, catalog: elements)
        #expect(drawing.representation == .unknownStructure)
        #expect(!drawing.hasGeometry)
        #expect(drawing.bonds.isEmpty, "a formula alone never produces bonds")
        // The two claims are kept apart: "there is no molecule" and "we have
        // no record" are different sentences.
        #expect(Compound2DRepresentation.unknownStructure.caption
            != Compound2DRepresentation.formulaUnit.caption)
        #expect(drawing.representation.caption.contains("none is known"))
    }

    @Test("Coordinates say where they came from, in each dimension")
    func provenanceIsRecorded() throws {
        for compound in catalog.compounds where compound.hasStructure {
            let provenance = try #require(compound.structure).resolvedProvenance
            #expect(provenance.twoDSource != nil,
                    "\(compound.preferredName) draws a diagram from coordinates of unknown origin")
            if compound.structure?.is3D == true {
                #expect(provenance.threeDSource != nil)
            }
        }
        // A generated layout says so rather than passing for a published one.
        #expect(CompoundCoordinateSource.generatedFromConnectivity.displayName
            .contains("generated"))
        #expect(CompoundCoordinateSource.pubChemConformer3D.displayName.contains("conformer"))
    }

    @Test("A molecule too large to draw is a limit of the renderer, and is bounded")
    func renderingIsBounded() {
        #expect(CompoundStructure.renderableAtomLimit >= 100,
                "the limit must be well past anything a learner will meet")
        let tiny = CompoundStructure(
            is3D: true, source: .pubChem3D, note: nil,
            atoms: [CompoundAtom(id: 0, atomicNumber: 8, x: 0, y: 0, z: 0.1, formalCharge: 0)],
            bonds: []
        )
        #expect(tiny.isRenderable)
        let enormous = CompoundStructure(
            is3D: true, source: .pubChem3D, note: nil,
            atoms: (0..<(CompoundStructure.renderableAtomLimit + 1)).map {
                CompoundAtom(id: $0, atomicNumber: 6, x: Double($0), y: 0, z: 0.1, formalCharge: 0)
            },
            bonds: []
        )
        #expect(!enormous.isRenderable)
        // And every bundled compound is well inside it, so nothing ships in
        // the state the message is for.
        for compound in TestCompounds.catalog.compounds {
            #expect(compound.structure?.isRenderable ?? true,
                    "\(compound.preferredName) is too large for the viewer")
        }
    }

    @Test("C2H6O is two compounds in the catalog, and stays two")
    func ambiguityIsPreserved() {
        let matches = catalog.compounds(hillFormula: "C2H6O")
        #expect(matches.count >= 2)
        let names = Set(matches.map(\.preferredName))
        #expect(names.contains("Ethanol"))
        #expect(names.contains("Dimethyl ether"))
        // They are genuinely different molecules: same formula, different
        // connectivity. Nothing may collapse them.
        let structures = matches.compactMap(\.structure).filter { !$0.bonds.isEmpty }
        if structures.count >= 2 {
            let shapes = structures.map { structure in
                Set(structure.bonds.map { [structure.atoms[$0.from].atomicNumber,
                                           structure.atoms[$0.to].atomicNumber].sorted() })
            }
            #expect(shapes[0] != shapes[1],
                    "ethanol and dimethyl ether must not have identical connectivity")
        }
    }
}
