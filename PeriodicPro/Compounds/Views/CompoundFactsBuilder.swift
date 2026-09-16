import Foundation

/// The inspector copy for a compound's structure, the sibling of
/// `StructureFactsBuilder` — which needs an element, where a compound has
/// several.
///
/// The same rules apply: a lattice contact is never called a bond, a
/// computed conformer is never called a measurement, and nothing is said
/// that the record does not support.
enum CompoundFactsBuilder {
    static func facts(
        for selection: StructureSelection,
        in scene: StructureScene,
        compound: ChemicalCompound,
        catalog: ElementCatalog
    ) -> StructureFacts? {
        switch selection {
        case .none:
            return nil
        case .node(let id):
            guard let node = scene.node(id: id) else { return nil }
            return facts(for: node, in: scene, compound: compound, catalog: catalog)
        case .bond(let id):
            guard let bond = scene.bond(id: id) else { return nil }
            return facts(for: bond, in: scene, compound: compound, catalog: catalog)
        }
    }

    private static func facts(
        for node: StructureNode,
        in scene: StructureScene,
        compound: ChemicalCompound,
        catalog: ElementCatalog
    ) -> StructureFacts {
        let element = node.atomicNumber.flatMap { catalog.element(atomicNumber: $0) }
        let name = element?.name ?? "Atom"
        let symbol = element?.symbol ?? "?"
        var rows: [StructureFacts.Row] = []
        if let element {
            rows.append(.init(label: "Element", value: "\(element.name) (\(element.symbol))"))
            rows.append(.init(label: "Family", value: element.category.displayName))
        }
        if let atom = compound.structure?.atoms.first(where: { $0.id == node.id }), atom.formalCharge != 0 {
            rows.append(.init(label: "Formal charge", value: atom.formalCharge > 0
                              ? "+\(atom.formalCharge)" : "\(atom.formalCharge)"))
        }
        let links = scene.bonds.filter { $0.from == node.id || $0.to == node.id }
        let partners = links.compactMap { link -> String? in
            let otherID = link.from == node.id ? link.to : link.from
            guard let other = scene.node(id: otherID),
                  let number = other.atomicNumber,
                  let partner = catalog.element(atomicNumber: number) else { return nil }
            return partner.symbol
        }
        if links.isEmpty {
            rows.append(.init(label: "In this picture", value: "Not bonded to another atom"))
        } else if links.allSatisfy(\.isDiscreteBond) {
            rows.append(.init(label: "Bonded to", value: partners.joined(separator: ", ")))
        } else {
            rows.append(.init(label: "Touching", value: partners.joined(separator: ", ")))
        }
        return StructureFacts(
            title: "\(name) atom",
            subtitle: "\(symbol) in \(compound.displayFormula)",
            rows: rows
        )
    }

    private static func facts(
        for bond: StructureBond,
        in scene: StructureScene,
        compound: ChemicalCompound,
        catalog: ElementCatalog
    ) -> StructureFacts {
        let from = scene.node(id: bond.from)?.atomicNumber.flatMap { catalog.element(atomicNumber: $0) }
        let to = scene.node(id: bond.to)?.atomicNumber.flatMap { catalog.element(atomicNumber: $0) }
        let left = from?.symbol ?? "?"
        let right = to?.symbol ?? "?"
        guard bond.isDiscreteBond else {
            return StructureFacts(
                title: "Ionic contact",
                subtitle: "\(left) and \(right) in the lattice",
                rows: [
                    .init(label: "What this line shows", value: "Which ions touch, not a covalent bond"),
                    .init(label: "Why", value: "In an ionic solid each ion is held by the charges of all "
                          + "its neighbors rather than by a shared pair of electrons"),
                ]
            )
        }
        let notation = "\(left)\(bond.order.notation)\(right)"
        return StructureFacts(
            title: bond.order.displayName,
            subtitle: notation,
            rows: [
                .init(label: "Notation", value: notation),
                .init(label: "Shared electrons", value: "\(bond.order.rawValue * 2)"),
                .init(label: "Compound", value: compound.preferredName),
            ]
        )
    }

    /// The VoiceOver summary of a compound scene.
    static func summary(of scene: StructureScene, compound: ChemicalCompound, catalog: ElementCatalog) -> String {
        let counts = compound.composition
        let described = counts.keys.sorted().compactMap { number -> String? in
            guard let element = catalog.element(atomicNumber: number), let count = counts[number] else { return nil }
            return count == 1 ? "1 \(element.name.lowercased())" : "\(count) \(element.name.lowercased())"
        }
        var parts = ["\(compound.preferredName), \(CompoundFormula.spoken(compound.formula))."]
        if !described.isEmpty {
            parts.append("Atoms shown: " + described.joined(separator: ", ") + ".")
        }
        let discrete = scene.bonds.filter(\.isDiscreteBond).count
        if discrete > 0 {
            parts.append(discrete == 1 ? "1 bond." : "\(discrete) bonds.")
        } else if !scene.bonds.isEmpty {
            parts.append("Ionic contacts are drawn between neighboring ions.")
        }
        parts.append(scene.representationLabel + ".")
        parts.append(scene.caption)
        return parts.joined(separator: " ")
    }
}
