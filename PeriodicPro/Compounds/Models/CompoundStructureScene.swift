import Foundation

/// How a compound's atoms are drawn.
enum CompoundRenderStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Small spheres joined by struts: the bonds are the point.
    case ballAndStick
    /// Spheres at van der Waals radii: the molecule's real bulk.
    case spaceFill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ballAndStick: return "Ball & Stick"
        case .spaceFill: return "Space Fill"
        }
    }
}

/// Turns a `CompoundStructure` into the same `StructureScene` the element
/// explorer renders, so compounds get the whole viewer — rotation, zoom,
/// selection, the accessible parts list — for free, and one renderer cannot
/// disagree with another about what a molecule looks like.
enum CompoundStructureScene {
    /// Van der Waals radii in ångströms (Bondi, with the usual later
    /// revisions), for space-fill rendering.
    static let vanDerWaalsRadii: [Int: Float] = [
        1: 1.20, 5: 1.92, 6: 1.70, 7: 1.55, 8: 1.52, 9: 1.47, 11: 2.27, 12: 1.73, 13: 1.84,
        14: 2.10, 15: 1.80, 16: 1.80, 17: 1.75, 19: 2.75, 20: 2.31, 26: 2.05, 29: 1.40, 30: 1.39,
        35: 1.85, 53: 1.98,
    ]

    /// Ball radii for ball-and-stick, scaled so hydrogen reads smaller.
    static func ballRadius(atomicNumber: Int) -> Float {
        switch atomicNumber {
        case 1: return 0.24
        case 6, 7, 8, 9: return 0.32
        default: return 0.38
        }
    }

    static func scene(
        for compound: ChemicalCompound,
        style: CompoundRenderStyle = .ballAndStick
    ) -> StructureScene? {
        guard let structure = compound.structure, !structure.atoms.isEmpty else { return nil }
        let nodes = structure.atoms.map { atom in
            let radius: Float
            switch style {
            case .ballAndStick: radius = ballRadius(atomicNumber: atom.atomicNumber)
            case .spaceFill: radius = vanDerWaalsRadii[atom.atomicNumber] ?? 1.8
            }
            return StructureNode(
                id: atom.id,
                role: .atom,
                position: SIMD3(Float(atom.x), Float(atom.y), Float(atom.z)),
                radius: radius,
                atomicNumber: atom.atomicNumber,
                tintHex: ElementRenderPalette.tintHex(atomicNumber: atom.atomicNumber) ?? 0x9AA0A8
            )
        }
        // Space-fill hides the struts inside the spheres anyway; leaving them
        // out keeps the part list to atoms, which is what can be seen.
        let bonds: [StructureBond] = style == .spaceFill ? [] : structure.bonds.map { bond in
            StructureBond(
                id: bond.id,
                from: bond.from,
                to: bond.to,
                order: StructureBondOrder(rawValue: min(max(bond.order, 1), 3)) ?? .single,
                isDiscreteBond: !bond.isContact
            )
        }
        let is3D = structure.is3D
        var caption = structure.note ?? structure.source.displayName
        if !is3D {
            caption = "Drawn from the 2D connectivity record: the bonds are real, the flat "
                + "layout is not a shape. " + caption
        }
        return StructureScene(
            id: "\(compound.id)-\(style.rawValue)",
            atomicNumber: 0,
            symbol: compound.formula,
            elementName: compound.preferredName,
            kind: .compound,
            nodes: nodes,
            bonds: bonds,
            formula: compound.displayFormula,
            caption: caption,
            isSimplified: !is3D || structure.source == .curatedLattice,
            representationLabel: structure.source.representationLabel,
            detail: compound.bondingClass == .unknown ? nil : compound.bondingClass.displayName,
            allotropeName: nil,
            coordination: nil,
            isMetallic: false,
            isEstablished: true,
            source: compound.dataSource == .curated ? "Elemora catalog" : "PubChem"
        ).normalized()
    }
}
