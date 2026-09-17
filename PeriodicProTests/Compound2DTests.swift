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
