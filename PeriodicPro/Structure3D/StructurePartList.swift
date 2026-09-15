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
        case .metallicLattice:
            return latticeParts(of: scene)
        case .diatomicMolecule, .polyatomicMolecule, .covalentNetwork:
            return moleculeParts(of: scene)
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

    private static func latticeParts(of scene: StructureScene) -> [Part] {
        var parts: [Part] = []
        let atoms = scene.atoms
        if let center = atoms.first {
            parts.append(Part(label: "Center atom", selection: .node(center.id)))
        }
        if atoms.count > 1 {
            parts.append(Part(label: "Neighboring atom", selection: .node(atoms[1].id)))
        }
        if let contact = scene.bonds.first {
            parts.append(Part(label: "Contact", selection: .bond(contact.id)))
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
}
