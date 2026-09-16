import Foundation

/// The selectable parts of a structure, as a short list.
///
/// A 3D scene cannot expose a useful accessibility hierarchy, so the explorer
/// shows this list beside the model: a row of chips that select the same parts
/// a tap would. It is not a VoiceOver-only affordance — it is quicker than
/// hunting for a particular sphere for everybody, and it means the feature works
/// with Switch Control and Voice Control too.
///
/// The list is representative rather than exhaustive. An atom model holds up to
/// 162 particles, and one chip per proton would be useless; what a learner
/// wants is "what is a proton", not "which proton".
enum StructurePartList {
    struct Part: Identifiable, Hashable, Sendable {
        let label: String
        let selection: StructureSelection
        var id: StructureSelection { selection }
    }

    /// At most this many atom chips before the list switches to representatives.
    static let individualAtomLimit = 8

    static func parts(of scene: StructureScene) -> [Part] {
        switch scene.kind {
        case .atomModel:
            return atomModelParts(of: scene)
        case .metallicLattice, .covalentNetwork:
            return latticeParts(of: scene)
        case .diatomicMolecule, .polyatomicMolecule, .molecularCrystal, .compound:
            return moleculeParts(of: scene)
        case .monatomicGas, .liquid:
            return looseParts(of: scene)
        }
    }

    private static func atomModelParts(of scene: StructureScene) -> [Part] {
        var parts: [Part] = []
        if let proton = scene.nodes.first(where: { $0.role == .proton }) {
            parts.append(Part(label: "Proton", selection: .node(proton.id)))
        }
        if let neutron = scene.nodes.first(where: { $0.role == .neutron }) {
            parts.append(Part(label: "Neutron", selection: .node(neutron.id)))
        }
        // One electron per shell: the shell is the interesting distinction.
        let shells = Set(scene.electrons.compactMap(\.shellIndex)).sorted()
        for shell in shells {
            guard let electron = scene.nodes.first(where: {
                $0.role == .electron && $0.shellIndex == shell
            }) else { continue }
            parts.append(Part(label: "Shell \(shell) electron", selection: .node(electron.id)))
        }
        return parts
    }

    /// The atom nearest the middle — the one with the most neighbors drawn —
    /// a neighbor of it, and one contact or bond.
    private static func latticeParts(of scene: StructureScene) -> [Part] {
        var parts: [Part] = []
        let atoms = scene.atoms
        guard let center = atoms.min(by: { magnitude($0.position) < magnitude($1.position) }) else {
            return parts
        }
        parts.append(Part(label: "Atom", selection: .node(center.id)))
        let neighborLink = scene.bonds.first { $0.from == center.id || $0.to == center.id }
        if let link = neighborLink {
            let neighborID = link.from == center.id ? link.to : link.from
            if scene.node(id: neighborID) != nil {
                parts.append(Part(label: "Neighboring atom", selection: .node(neighborID)))
            }
            parts.append(Part(label: link.isDiscreteBond ? "Bond" : "Contact", selection: .bond(link.id)))
        } else if atoms.count > 1, let other = atoms.first(where: { $0.id != center.id }) {
            parts.append(Part(label: "Another atom", selection: .node(other.id)))
        }
        return parts
    }

    private static func moleculeParts(of scene: StructureScene) -> [Part] {
        var parts: [Part] = []
        let atoms = scene.atoms

        if atoms.count <= individualAtomLimit {
            for (index, atom) in atoms.enumerated() {
                parts.append(Part(
                    label: atoms.count == 1 ? "Atom" : "Atom \(index + 1)",
                    selection: .node(atom.id)
                ))
            }
        } else if let first = atoms.first {
            parts.append(Part(label: "Atom", selection: .node(first.id)))
        }

        // One chip per distinct bond order, since every bond of the same order
        // says the same thing.
        var seenOrders: Set<Int> = []
        for bond in scene.bonds where bond.isDiscreteBond {
            guard seenOrders.insert(bond.order.rawValue).inserted else { continue }
            parts.append(Part(label: bond.order.displayName, selection: .bond(bond.id)))
        }
        return parts
    }

    /// A gas or a liquid: one atom stands for all of them, plus a bond if the
    /// liquid is molecular.
    private static func looseParts(of scene: StructureScene) -> [Part] {
        var parts: [Part] = []
        if let atom = scene.atoms.first {
            parts.append(Part(label: "Atom", selection: .node(atom.id)))
        }
        if let bond = scene.bonds.first(where: \.isDiscreteBond) {
            parts.append(Part(label: bond.order.displayName, selection: .bond(bond.id)))
        }
        return parts
    }

    private static func magnitude(_ vector: SIMD3<Float>) -> Float {
        (vector.x * vector.x + vector.y * vector.y + vector.z * vector.z).squareRoot()
    }
}
