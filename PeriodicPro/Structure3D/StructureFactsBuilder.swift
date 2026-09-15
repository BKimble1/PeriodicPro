import Foundation

/// The copy shown when the learner taps something in a structure.
///
/// Built as data rather than inline in a view so every sentence is unit-tested.
/// This is the part of the 3D feature most likely to drift into saying
/// something untrue, so the rules are enforced here in one place:
///
/// * a strut in a metallic lattice is never called a bond;
/// * an electron is never described as orbiting;
/// * a nucleus that is drawn as a sample says so.
enum StructureFactsBuilder {
    static func facts(
        for selection: StructureSelection,
        in scene: StructureScene,
        element: ChemicalElement
    ) -> StructureFacts? {
        switch selection {
        case .none:
            return nil
        case .node(let id):
            guard let node = scene.node(id: id) else { return nil }
            return facts(for: node, in: scene, element: element)
        case .bond(let id):
            guard let bond = scene.bond(id: id) else { return nil }
            return facts(for: bond, in: scene, element: element)
        }
    }

    // MARK: - Nodes

    private static func facts(
        for node: StructureNode,
        in scene: StructureScene,
        element: ChemicalElement
    ) -> StructureFacts {
        switch node.role {
        case .atom:
            return StructureFacts(
                title: "\(element.name) atom",
                subtitle: "\(element.symbol) · Atomic number \(element.atomicNumber)",
                rows: [
                    .init(label: "Protons", value: "\(element.atomicNumber)"),
                    .init(label: "Electrons", value: "\(element.atomicNumber)"),
                    .init(label: "Family", value: element.category.displayName),
                    .init(label: "In this structure", value: neighborSummary(for: node, in: scene)),
                ]
            )

        case .proton:
            return StructureFacts(
                title: "Proton",
                subtitle: "One of the particles in the nucleus",
                rows: [
                    .init(label: "Charge", value: "Positive (+1)"),
                    .init(label: "Location", value: "Nucleus"),
                    .init(label: "Mass", value: "≈ 1 u"),
                    .init(label: "In \(element.name)", value: "\(element.atomicNumber) protons"),
                ]
            )

        case .neutron:
            return StructureFacts(
                title: "Neutron",
                subtitle: "One of the particles in the nucleus",
                rows: [
                    .init(label: "Charge", value: "None"),
                    .init(label: "Location", value: "Nucleus"),
                    .init(label: "Mass", value: "≈ 1 u"),
                    .init(label: "In \(element.name)", value: neutronCountDescription(for: element)),
                ]
            )

        case .electron:
            var rows: [StructureFacts.Row] = [
                .init(label: "Charge", value: "Negative (−1)"),
                .init(label: "Location", value: "In a cloud around the nucleus, not on a fixed path"),
                .init(label: "Mass", value: "About 1/1836 of a proton"),
            ]
            if let shell = node.shellIndex {
                rows.append(.init(
                    label: "Energy level",
                    value: "Shell \(shell) of \(element.shellElectrons.filter { $0 > 0 }.count)"
                ))
            }
            return StructureFacts(
                title: "Electron",
                subtitle: "Shown at a representative position",
                rows: rows
            )
        }
    }

    /// How many neighbors this atom is joined to, phrased differently for a
    /// lattice — where the struts mark contact — than for a molecule.
    private static func neighborSummary(for node: StructureNode, in scene: StructureScene) -> String {
        let links = scene.bonds.filter { $0.from == node.id || $0.to == node.id }
        guard !links.isEmpty else { return "Not bonded to another atom" }
        let discrete = links.allSatisfy(\.isDiscreteBond)
        let count = links.count
        if discrete {
            return count == 1 ? "Bonded to 1 atom" : "Bonded to \(count) atoms"
        }
        return count == 1 ? "Touching 1 neighbor" : "Touching \(count) neighbors"
    }

    private static func neutronCountDescription(for element: ChemicalElement) -> String {
        let massNumber = max(element.atomicNumber, Int(element.atomicMass.rounded()))
        let neutrons = massNumber - element.atomicNumber
        // The neutron count is a property of an isotope, not of an element, so
        // this never claims a single true value.
        return "\(neutrons) at mass number \(massNumber); other isotopes differ"
    }

    // MARK: - Bonds

    private static func facts(
        for bond: StructureBond,
        in scene: StructureScene,
        element: ChemicalElement
    ) -> StructureFacts {
        guard bond.isDiscreteBond else {
            return StructureFacts(
                title: "Nearest neighbors",
                subtitle: "Two atoms in contact in the lattice",
                rows: [
                    .init(label: "What this line shows", value: "Which atoms touch, not a bond between them"),
                    .init(
                        label: "Why",
                        value: "In a metal the outer electrons are shared across the whole lattice "
                            + "rather than being held between pairs of atoms"
                    ),
                    .init(label: "Element", value: "\(element.name) (\(element.symbol))"),
                ]
            )
        }

        let notation = "\(element.symbol)\(bond.order.notation)\(element.symbol)"
        var rows: [StructureFacts.Row] = [
            .init(label: "Notation", value: notation),
            .init(label: "Shared electrons", value: "\(bond.order.rawValue * 2)"),
        ]
        if scene.kind == .diatomicMolecule {
            rows.append(.init(label: "Molecule", value: scene.formula))
        } else {
            rows.append(.init(label: "Structure", value: scene.formula))
        }
        return StructureFacts(
            title: bond.order.displayName,
            subtitle: notation,
            rows: rows
        )
    }

    // MARK: - Accessible summary

    /// The VoiceOver fallback. A 3D scene cannot expose a useful accessibility
    /// hierarchy on its own, so the viewer offers this summary plus a plain list
    /// of selectable parts alongside it.
    static func summary(of scene: StructureScene, element: ChemicalElement) -> String {
        var parts: [String] = []
        switch scene.kind {
        case .diatomicMolecule:
            parts.append("\(element.name) exists as \(scene.formula), two atoms joined by a "
                + "\(StructureSceneBuilder.bondOrder(forDiatomic: element.symbol).displayName.lowercased()).")
        case .polyatomicMolecule:
            parts.append("\(element.name) forms \(scene.formula), a molecule of \(scene.atoms.count) atoms.")
        case .metallicLattice:
            parts.append("\(element.name) forms a metallic lattice. "
                + "\(scene.atoms.count) atoms are shown: one central atom and the neighbors touching it.")
        case .covalentNetwork:
            parts.append("\(element.name) forms a covalent network. "
                + "\(scene.atoms.count) atoms of the network are shown.")
        case .atomModel:
            let protons = scene.nodes.filter { $0.role == .proton }.count
            let neutrons = scene.nodes.filter { $0.role == .neutron }.count
            let shells = element.shellElectrons.filter { $0 > 0 }
            parts.append("A simplified model of one \(element.name) atom.")
            parts.append("The nucleus shows \(protons) protons and \(neutrons) neutrons.")
            parts.append("\(shells.count) electron shells hold "
                + shells.enumerated()
                    .map { "\($0.element) in shell \($0.offset + 1)" }
                    .joined(separator: ", ")
                + ".")
        }
        parts.append(scene.caption)
        return parts.joined(separator: " ")
    }
}
