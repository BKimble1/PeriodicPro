import Foundation

/// Turns an element into a renderable structure, using only data the app
/// already ships.
///
/// Every scene is built from shared generators — there are no 118 hand-authored
/// scenes. Which generator an element uses is decided by its `structure` field,
/// with named routing for the elements whose real geometry is well known and
/// specific (P₄ tetrahedra, S₈ crowns, B₁₂ icosahedra, selenium's helical
/// chains).
///
/// Scientific honesty rules this file:
/// * a metallic lattice is never called a molecule, and its struts are marked
///   `isDiscreteBond: false` so the inspector cannot claim they are covalent
///   bonds;
/// * a noble gas gets an atom, not an invented dimer;
/// * the atom model is always flagged `isSimplified`, and its electrons are
///   spread over a sphere rather than around a ring, so it does not teach
///   planetary orbits;
/// * where a nucleus is too large to draw nucleon-for-nucleon, the scene says
///   so rather than quietly showing the wrong number.
enum StructureSceneBuilder {
    /// Nucleons drawn at most. Beyond this the nucleus is a representative
    /// sample and `nucleonSampleNote` explains that.
    static let maximumDrawnNucleons = 44

    /// The two things a learner can look at for one element.
    enum Representation: String, CaseIterable, Identifiable, Hashable, Sendable {
        /// How the element exists as a substance: a molecule, a lattice, a
        /// network, or a lone atom.
        case elementalForm
        /// One atom: nucleus and electron shells.
        case atom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .elementalForm: return "Elemental form"
            case .atom: return "Atom"
            }
        }
    }

    /// Which representations are worth offering for an element. For a noble gas
    /// the elemental form *is* a single atom, so only one is offered rather
    /// than showing the same picture twice under two names.
    static func representations(for element: ChemicalElement) -> [Representation] {
        switch element.structure {
        case .monatomicGas, .atom: return [.atom]
        default: return [.elementalForm, .atom]
        }
    }

    static func scene(
        for element: ChemicalElement,
        representation: Representation
    ) -> StructureScene {
        switch representation {
        case .atom: return atomScene(for: element)
        case .elementalForm: return elementalFormScene(for: element)
        }
    }

    // MARK: - Elemental form

    private static func elementalFormScene(for element: ChemicalElement) -> StructureScene {
        switch element.structure {
        case .diatomic:
            return finish(
                element: element,
                kind: .diatomicMolecule,
                geometry: diatomic(order: bondOrder(forDiatomic: element.symbol)),
                caption: "Two atoms joined by a \(bondOrder(forDiatomic: element.symbol).displayName.lowercased()). "
                    + "This is how the free element exists.",
                isSimplified: false
            )

        case .polyatomicMolecule:
            switch element.symbol {
            case "P":
                return finish(
                    element: element,
                    kind: .polyatomicMolecule,
                    geometry: tetrahedron(),
                    caption: "White phosphorus is built from P₄ tetrahedra — four atoms, "
                        + "each bonded to the other three.",
                    isSimplified: false
                )
            case "Se":
                return finish(
                    element: element,
                    kind: .polyatomicMolecule,
                    geometry: helicalChain(atomCount: 7),
                    caption: "Gray selenium is built from helical chains of atoms, shown here as "
                        + "one open fragment. The chain continues at both ends.",
                    isSimplified: true
                )
            default:
                return finish(
                    element: element,
                    kind: .polyatomicMolecule,
                    geometry: crownRing(atomCount: 8),
                    caption: "Sulfur rings are puckered: eight atoms alternating above and below "
                        + "the plane, each bonded to its two neighbors.",
                    isSimplified: false
                )
            }

        case .covalentNetwork:
            switch element.symbol {
            case "B":
                return finish(
                    element: element,
                    kind: .covalentNetwork,
                    geometry: icosahedron(),
                    caption: "Boron is built from B₁₂ icosahedra — twelve atoms at the corners of "
                        + "a twenty-faced solid — linked into a network.",
                    isSimplified: true
                )
            case "As", "Sb":
                return finish(
                    element: element,
                    kind: .covalentNetwork,
                    geometry: puckeredLayer(),
                    caption: "A fragment of one puckered layer. The layers stack, and the network "
                        + "continues beyond the atoms shown.",
                    isSimplified: true
                )
            case "Te":
                return finish(
                    element: element,
                    kind: .covalentNetwork,
                    geometry: helicalChain(atomCount: 7),
                    caption: "Tellurium is built from helical covalent chains, shown here as one "
                        + "open fragment. The chain continues at both ends.",
                    isSimplified: true
                )
            default:
                return finish(
                    element: element,
                    kind: .covalentNetwork,
                    geometry: diamondNetwork(),
                    caption: "Each atom is bonded to four neighbors in a continuous network. "
                        + "This is a fragment — the network has no molecules in it.",
                    isSimplified: true
                )
            }

        case .metallicLattice:
            return finish(
                element: element,
                kind: .metallicLattice,
                geometry: closePackedCluster(),
                caption: "A fragment of a metallic lattice: a regular array of atoms sharing "
                    + "their outer electrons. The struts show which atoms touch, not "
                    + "individual bonds.",
                isSimplified: true
            )

        case .monatomicGas, .atom:
            // Not reachable through `representations(for:)`, which offers only
            // the atom for these. Handled anyway so the switch is total and a
            // future caller cannot fall into an empty scene.
            return atomScene(for: element)
        }
    }

    /// Real bond orders. Nitrogen's triple bond and oxygen's double bond are the
    /// reason these molecules behave so differently, so getting them right
    /// matters more here than the geometry does.
    static func bondOrder(forDiatomic symbol: String) -> StructureBondOrder {
        switch symbol {
        case "N": return .triple
        case "O": return .double
        default: return .single
        }
    }

    // MARK: - Atom model

    private static func atomScene(for element: ChemicalElement) -> StructureScene {
        var nodes: [StructureNode] = []
        var nextID = 0

        let protons = element.atomicNumber
        let massNumber = max(protons, Int(element.atomicMass.rounded()))
        let neutrons = max(0, massNumber - protons)
        let totalNucleons = protons + neutrons

        // A uranium nucleus is 238 nucleons. Drawing them all would be an
        // unreadable ball and a pointless number of entities, so past a cap the
        // nucleus becomes a representative sample and says so.
        let drawnNucleons = min(totalNucleons, maximumDrawnNucleons)
        let isSampled = drawnNucleons < totalNucleons
        let drawnProtons = totalNucleons == 0
            ? 0
            : max(1, Int((Double(drawnNucleons) * Double(protons) / Double(totalNucleons)).rounded()))
        let drawnNeutrons = max(0, drawnNucleons - drawnProtons)

        let nucleusRadius: Float = 0.20
        let nucleonPositions = packedCluster(count: drawnNucleons, radius: nucleusRadius)
        let nucleonRoles = interleavedNucleons(protons: drawnProtons, neutrons: drawnNeutrons)
        for (position, role) in zip(nucleonPositions, nucleonRoles) {
            nodes.append(StructureNode(
                id: nextID,
                role: role,
                position: position,
                radius: 0.042,
                shellIndex: nil
            ))
            nextID += 1
        }

        let shells = element.shellElectrons.filter { $0 > 0 }
        for (shellIndex, count) in shells.enumerated() {
            let radius = shellRadius(index: shellIndex, of: shells.count)
            for position in sphereDistribution(count: count, radius: radius, phase: Double(shellIndex) * 0.7) {
                nodes.append(StructureNode(
                    id: nextID,
                    role: .electron,
                    position: position,
                    radius: 0.032,
                    shellIndex: shellIndex + 1
                ))
                nextID += 1
            }
        }

        let electronCount = shells.reduce(0, +)
        var caption = "A simplified model. Electrons do not follow fixed paths — they are spread "
            + "through a cloud around the nucleus, and the shells here stand for energy levels, "
            + "not orbits."
        var sampleNote: String?
        if isSampled {
            sampleNote = "Nucleus drawn with \(drawnNucleons) of its \(totalNucleons) nucleons."
            caption += " The nucleus shows a representative sample of its particles."
        }

        return normalized(StructureScene(
            id: "\(element.symbol)-atom",
            atomicNumber: element.atomicNumber,
            symbol: element.symbol,
            elementName: element.name,
            kind: .atomModel,
            nodes: nodes,
            bonds: [],
            formula: "\(protons) protons · \(neutrons) neutrons · \(electronCount) electrons",
            caption: caption,
            isSimplified: true,
            nucleonSampleNote: sampleNote
        ))
    }

    /// Alternates protons and neutrons so the nucleus does not read as two
    /// separately colored hemispheres, and spends whichever runs out first
    /// before filling the remainder with the other. Always returns exactly
    /// `protons + neutrons` roles.
    static func interleavedNucleons(protons: Int, neutrons: Int) -> [StructureNodeRole] {
        var remainingProtons = max(0, protons)
        var remainingNeutrons = max(0, neutrons)
        var roles: [StructureNodeRole] = []
        roles.reserveCapacity(remainingProtons + remainingNeutrons)
        while remainingProtons > 0 || remainingNeutrons > 0 {
            let takeProton = remainingNeutrons == 0
                || (remainingProtons > 0 && roles.count.isMultiple(of: 2))
            if takeProton {
                roles.append(.proton)
                remainingProtons -= 1
            } else {
                roles.append(.neutron)
                remainingNeutrons -= 1
            }
        }
        return roles
    }

    /// Shell radii march outward with a little breathing room so the innermost
    /// shell never collides with the nucleus.
    private static func shellRadius(index: Int, of total: Int) -> Float {
        let inner: Float = 0.42
        let outer: Float = 1.0
        guard total > 1 else { return outer }
        return inner + (outer - inner) * Float(index) / Float(total - 1)
    }

    // MARK: - Geometry generators

    /// Positions plus the links between them, before an element is attached.
    private struct Geometry {
        var positions: [SIMD3<Float>]
        var links: [(Int, Int, StructureBondOrder, Bool)]
        var atomRadius: Float
    }

    private static func diatomic(order: StructureBondOrder) -> Geometry {
        Geometry(
            positions: [SIMD3(-0.42, 0, 0), SIMD3(0.42, 0, 0)],
            links: [(0, 1, order, true)],
            atomRadius: 0.34
        )
    }

    private static func tetrahedron() -> Geometry {
        // The four alternating corners of a cube: the standard construction.
        let s: Float = 0.42
        let positions = [
            SIMD3<Float>(s, s, s),
            SIMD3<Float>(s, -s, -s),
            SIMD3<Float>(-s, s, -s),
            SIMD3<Float>(-s, -s, s),
        ]
        var links: [(Int, Int, StructureBondOrder, Bool)] = []
        for a in 0..<positions.count {
            for b in (a + 1)..<positions.count {
                links.append((a, b, .single, true))
            }
        }
        return Geometry(positions: positions, links: links, atomRadius: 0.26)
    }

    /// The puckered eight-membered ring of orthorhombic sulfur: alternate atoms
    /// sit above and below the mean plane, which is why it is called a crown.
    private static func crownRing(atomCount: Int) -> Geometry {
        var positions: [SIMD3<Float>] = []
        var links: [(Int, Int, StructureBondOrder, Bool)] = []
        let radius: Float = 0.62
        for index in 0..<atomCount {
            let angle = Float(index) / Float(atomCount) * 2 * .pi
            positions.append(SIMD3(
                cos(angle) * radius,
                index.isMultiple(of: 2) ? 0.16 : -0.16,
                sin(angle) * radius
            ))
            links.append((index, (index + 1) % atomCount, .single, true))
        }
        return Geometry(positions: positions, links: links, atomRadius: 0.22)
    }

    /// An open helix. Used for selenium and tellurium, whose chains genuinely do
    /// not close into rings.
    private static func helicalChain(atomCount: Int) -> Geometry {
        var positions: [SIMD3<Float>] = []
        var links: [(Int, Int, StructureBondOrder, Bool)] = []
        let radius: Float = 0.34
        let rise: Float = 0.26
        let span = Float(atomCount - 1) * rise
        for index in 0..<atomCount {
            let angle = Float(index) * 2.1
            positions.append(SIMD3(
                cos(angle) * radius,
                Float(index) * rise - span / 2,
                sin(angle) * radius
            ))
            if index > 0 { links.append((index - 1, index, .single, true)) }
        }
        return Geometry(positions: positions, links: links, atomRadius: 0.20)
    }

    /// Twelve vertices of a regular icosahedron — the B₁₂ unit.
    private static func icosahedron() -> Geometry {
        let phi: Float = (1 + 5.0.squareRoot().float) / 2
        var positions: [SIMD3<Float>] = []
        for sx in [Float(-1), 1] {
            for sy in [Float(-1), 1] {
                positions.append(SIMD3(0, sx * 1, sy * phi))
                positions.append(SIMD3(sx * 1, sy * phi, 0))
                positions.append(SIMD3(sx * phi, 0, sy * 1))
            }
        }
        let scale: Float = 0.34
        positions = positions.map { $0 * scale }

        // Link every pair at the icosahedron's edge length, which is 2 in the
        // unscaled construction.
        var links: [(Int, Int, StructureBondOrder, Bool)] = []
        let edge = 2 * scale
        for a in 0..<positions.count {
            for b in (a + 1)..<positions.count where distance(positions[a], positions[b]) < edge * 1.15 {
                links.append((a, b, .single, true))
            }
        }
        return Geometry(positions: positions, links: links, atomRadius: 0.17)
    }

    /// One atom with its four tetrahedral neighbors, plus a second shell on one
    /// of them, so the network reads as continuing rather than as a molecule.
    private static func diamondNetwork() -> Geometry {
        let s: Float = 0.40
        var positions: [SIMD3<Float>] = [SIMD3(0, 0, 0)]
        let directions = [
            SIMD3<Float>(1, 1, 1),
            SIMD3<Float>(1, -1, -1),
            SIMD3<Float>(-1, 1, -1),
            SIMD3<Float>(-1, -1, 1),
        ]
        var links: [(Int, Int, StructureBondOrder, Bool)] = []
        for direction in directions {
            positions.append(direction * s)
            links.append((0, positions.count - 1, .single, true))
        }
        // Second shell hanging off the first neighbor, in the three directions
        // that are not back toward the center.
        let anchor = positions[1]
        for direction in directions where direction != directions[0] {
            positions.append(anchor - direction * s)
            links.append((1, positions.count - 1, .single, true))
        }
        return Geometry(positions: positions, links: links, atomRadius: 0.20)
    }

    /// A six-membered ring puckered into a chair — one layer of gray arsenic.
    private static func puckeredLayer() -> Geometry {
        var positions: [SIMD3<Float>] = []
        var links: [(Int, Int, StructureBondOrder, Bool)] = []
        let radius: Float = 0.58
        for index in 0..<6 {
            let angle = Float(index) / 6 * 2 * .pi
            positions.append(SIMD3(
                cos(angle) * radius,
                index.isMultiple(of: 2) ? 0.20 : -0.20,
                sin(angle) * radius
            ))
            links.append((index, (index + 1) % 6, .single, true))
        }
        return Geometry(positions: positions, links: links, atomRadius: 0.22)
    }

    /// Coordination number twelve: one atom surrounded by the twelve that touch
    /// it in a close-packed metal. The struts mark contact, not covalent bonds.
    private static func closePackedCluster() -> Geometry {
        var positions: [SIMD3<Float>] = [SIMD3(0, 0, 0)]
        let d: Float = 0.52
        // The twelve cuboctahedron vertices: every permutation of (±1, ±1, 0).
        for axis in 0..<3 {
            for s1 in [Float(-1), 1] {
                for s2 in [Float(-1), 1] {
                    var point = SIMD3<Float>(0, 0, 0)
                    point[axis] = 0
                    point[(axis + 1) % 3] = s1
                    point[(axis + 2) % 3] = s2
                    positions.append(point * (d / 2.0.squareRoot().float))
                }
            }
        }
        let links = (1..<positions.count).map { (0, $0, StructureBondOrder.single, false) }
        return Geometry(positions: positions, links: links, atomRadius: 0.21)
    }

    // MARK: - Point distributions

    /// Evenly spread points over a sphere's surface, using the golden angle.
    ///
    /// Deliberately a sphere rather than a ring: electrons drawn marching round
    /// a circle is exactly the planetary-orbit picture this app is not willing
    /// to teach.
    static func sphereDistribution(count: Int, radius: Float, phase: Double = 0) -> [SIMD3<Float>] {
        guard count > 0 else { return [] }
        if count == 1 { return [SIMD3(0, radius, 0)] }
        let goldenAngle = Float.pi * (3 - 5.0.squareRoot().float)
        return (0..<count).map { index in
            let y = 1 - (Float(index) / Float(count - 1)) * 2
            let ringRadius = max(0, 1 - y * y).squareRoot()
            let theta = goldenAngle * Float(index) + Float(phase)
            return SIMD3(cos(theta) * ringRadius * radius, y * radius, sin(theta) * ringRadius * radius)
        }
    }

    /// Points filling a ball rather than its surface, for the nucleus.
    static func packedCluster(count: Int, radius: Float) -> [SIMD3<Float>] {
        guard count > 0 else { return [] }
        if count == 1 { return [SIMD3(0, 0, 0)] }
        let goldenAngle = Float.pi * (3 - 5.0.squareRoot().float)
        return (0..<count).map { index in
            // Cube-rooting the index spreads points evenly through the volume
            // instead of crowding them at the center.
            let t = Float(index) / Float(count - 1)
            let shellRadius = radius * pow(t, Float(1.0) / Float(3.0))
            let y = 1 - t * 2
            let ringRadius = max(0, 1 - y * y).squareRoot()
            let theta = goldenAngle * Float(index)
            return SIMD3(
                cos(theta) * ringRadius * shellRadius,
                y * shellRadius,
                sin(theta) * ringRadius * shellRadius
            )
        }
    }

    // MARK: - Assembly

    private static func finish(
        element: ChemicalElement,
        kind: StructureSceneKind,
        geometry: Geometry,
        caption: String,
        isSimplified: Bool
    ) -> StructureScene {
        let nodes = geometry.positions.enumerated().map { index, position in
            StructureNode(
                id: index,
                role: .atom,
                position: position,
                radius: geometry.atomRadius,
                shellIndex: nil
            )
        }
        let bonds = geometry.links.enumerated().map { index, link in
            StructureBond(
                id: index,
                from: link.0,
                to: link.1,
                order: link.2,
                isDiscreteBond: link.3
            )
        }
        return normalized(StructureScene(
            id: "\(element.symbol)-form",
            atomicNumber: element.atomicNumber,
            symbol: element.symbol,
            elementName: element.name,
            kind: kind,
            nodes: nodes,
            bonds: bonds,
            formula: element.elementalFormFormula,
            caption: caption,
            isSimplified: isSimplified,
            nucleonSampleNote: nil
        ))
    }

    /// Scales a scene so its bounding radius is 1, letting the viewer frame
    /// every structure — a lone diatomic or a thirteen-atom cluster — with the
    /// same camera distance.
    private static func normalized(_ scene: StructureScene) -> StructureScene {
        let radius = scene.boundingRadius
        guard radius > 0.0001, abs(radius - 1) > 0.0001 else { return scene }
        let factor = 1 / radius
        let scaled = scene.nodes.map { node in
            StructureNode(
                id: node.id,
                role: node.role,
                position: node.position * factor,
                radius: node.radius * factor,
                shellIndex: node.shellIndex
            )
        }
        return StructureScene(
            id: scene.id,
            atomicNumber: scene.atomicNumber,
            symbol: scene.symbol,
            elementName: scene.elementName,
            kind: scene.kind,
            nodes: scaled,
            bonds: scene.bonds,
            formula: scene.formula,
            caption: scene.caption,
            isSimplified: scene.isSimplified,
            nucleonSampleNote: scene.nucleonSampleNote
        )
    }
}

// MARK: - Small helpers

private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let d = a - b
    return (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
}

private extension Double {
    /// `5.0.squareRoot()` is a `Double`; the geometry above is all `Float`.
    var float: Float { Float(self) }
}
