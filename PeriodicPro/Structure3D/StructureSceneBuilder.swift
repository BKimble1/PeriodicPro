import Foundation

/// Turns an element's structure profile into a renderable scene.
///
/// Every scene is generated from `structures.json` through a small set of
/// geometry generators: conventional unit cells for the cubic lattices,
/// hexagonal prisms for close packing, explicit cells for the awkward metals
/// (gallium, tin, uranium), and molecule generators for the rest. Which one an
/// element uses is decided by its profile, never by guesswork — an element
/// whose profile says `unknown` gets the atom model and a label that says so.
///
/// Scientific honesty rules this file:
/// * a metallic lattice is never called a molecule, and its struts are marked
///   `isDiscreteBond: false` so the inspector cannot claim they are covalent
///   bonds;
/// * a noble gas gets separate atoms, not an invented dimer;
/// * every scene carries a `representationLabel` — a real unit cell says so,
///   a fragment or a liquid says it is representative, and the atom model is
///   always flagged `isSimplified`, with its electrons spread over a sphere so
///   it does not teach planetary orbits;
/// * where a nucleus is too large to draw nucleon-for-nucleon, the scene says
///   so rather than quietly showing the wrong number.
///
/// The detail page's preview and the full explorer both call `scene(for:)`
/// with the same arguments, so they can never disagree about what an element
/// looks like.
enum StructureSceneBuilder {
    /// Nucleons drawn at most. Beyond this the nucleus is a representative
    /// sample and `nucleonSampleNote` explains that.
    static let maximumDrawnNucleons = 44

    /// What a learner can look at for one element: each of its profiles
    /// (the primary form plus any allotropes), and the atom itself.
    enum Representation: Hashable, Identifiable, Sendable {
        /// The profile at this index in `ElementStructureEntry.allProfiles`.
        case form(Int)
        /// One atom: nucleus and electron shells.
        case atom

        var id: String {
            switch self {
            case .form(let index): return "form-\(index)"
            case .atom: return "atom"
            }
        }
    }

    /// A representation with the word the picker shows for it.
    struct RepresentationOption: Identifiable, Hashable, Sendable {
        let representation: Representation
        let title: String
        var id: Representation { representation }
    }

    static func entry(
        for element: ChemicalElement,
        catalog: ElementStructureCatalog = .shared
    ) -> ElementStructureEntry {
        catalog.entry(atomicNumber: element.atomicNumber)
    }

    /// Which representations are worth offering for an element. An element
    /// whose bulk form is not established offers only the atom, because the
    /// atom is all anyone has observed.
    static func representations(
        for element: ChemicalElement,
        catalog: ElementStructureCatalog = .shared
    ) -> [RepresentationOption] {
        let entry = entry(for: element, catalog: catalog)
        var options: [RepresentationOption] = []
        if !entry.isUnknown {
            for (index, profile) in entry.allProfiles.enumerated() {
                options.append(RepresentationOption(representation: .form(index), title: profile.title))
            }
        }
        options.append(RepresentationOption(representation: .atom, title: "Atom"))
        return options
    }

    /// The profile behind a representation, or `nil` for the atom model.
    static func profile(
        for element: ChemicalElement,
        representation: Representation,
        catalog: ElementStructureCatalog = .shared
    ) -> ElementStructureProfile? {
        guard case .form(let index) = representation else { return nil }
        let entry = entry(for: element, catalog: catalog)
        guard !entry.isUnknown, entry.allProfiles.indices.contains(index) else { return nil }
        return entry.allProfiles[index]
    }

    static func scene(
        for element: ChemicalElement,
        representation: Representation,
        catalog: ElementStructureCatalog = .shared
    ) -> StructureScene {
        let entry = entry(for: element, catalog: catalog)
        if let profile = profile(for: element, representation: representation, catalog: catalog) {
            return formScene(for: element, profile: profile)
        }
        return atomScene(for: element, entry: entry)
    }

    // MARK: - Elemental form

    private static func formScene(for element: ChemicalElement, profile: ElementStructureProfile) -> StructureScene {
        let template = profile.geometry?.template ?? "atom"
        let order = profile.primaryBondOrder
        let isMetallic = profile.representationKind.isMetallic
            || (profile.representationKind.isCrystal && !profile.hasDiscreteBonds)

        let built: (geometry: Geometry, kind: StructureSceneKind, isSimplified: Bool)
        switch template {
        case "diatomic":
            built = (diatomic(order: order), .diatomicMolecule, false)
        case "monatomicGas":
            built = (monatomicGas(), .monatomicGas, true)
        case "tetrahedron":
            built = (tetrahedron(), .molecularCrystal, false)
        case "crownRing":
            built = (crownRing(atomCount: 8), .molecularCrystal, false)
        case "helicalChain":
            built = (helicalChain(atomCount: 7), .covalentNetwork, true)
        case "icosahedron":
            built = (icosahedron(), .covalentNetwork, true)
        case "puckeredLayer":
            built = (hexagonalSheet(layers: 1, pucker: 0.24, stackShift: 0), .covalentNetwork, true)
        case "graphite":
            built = (hexagonalSheet(layers: 2, pucker: 0, stackShift: 2.36), .covalentNetwork, true)
        case "fcc":
            built = (cubicCell(basis: Self.fccBasis, contactFactor: 1.06, discrete: false, order: .single,
                               radiusFactor: 0.30), .metallicLattice, false)
        case "bcc":
            built = (cubicCell(basis: Self.bccBasis, contactFactor: 1.06, discrete: false, order: .single,
                               radiusFactor: 0.30), .metallicLattice, false)
        case "simpleCubic":
            built = (cubicCell(basis: Self.simpleCubicBasis, contactFactor: 1.06, discrete: false,
                               order: .single, radiusFactor: 0.30), .metallicLattice, false)
        case "diamondCubic":
            built = (cubicCell(basis: Self.diamondBasis, contactFactor: 1.10, discrete: true, order: .single,
                               radiusFactor: 0.24), .covalentNetwork, false)
        case "hcp":
            built = (hexagonalPrism(stacking: .abab, cOverA: Float(profile.geometry?.cOverA ?? 1.633)),
                     .metallicLattice, false)
        case "dhcp":
            built = (hexagonalPrism(stacking: .abac, cOverA: Float(profile.geometry?.cOverA ?? 3.26)),
                     .metallicLattice, false)
        case "lattice":
            if let geometry = explicitCell(profile: profile, order: order) {
                let kind: StructureSceneKind = profile.representationKind == .molecularCrystal
                    ? .molecularCrystal
                    : (isMetallic ? .metallicLattice : .covalentNetwork)
                built = (geometry, kind, false)
            } else {
                built = (closePackedCluster(), .metallicLattice, true)
            }
        case "closePackedCluster":
            built = (closePackedCluster(), .metallicLattice, true)
        case "liquidMetal":
            built = (liquidCluster(), .liquid, true)
        case "molecularLiquid":
            built = (molecularLiquid(order: order), .liquid, true)
        default:
            return atomScene(for: element, entry: ElementStructureEntry(
                atomicNumber: element.atomicNumber, primary: profile, alternatives: []
            ))
        }

        let tint = ElementRenderPalette.tintHex(atomicNumber: element.atomicNumber)
            ?? (isMetallic ? ElementRenderPalette.steel : nil)

        return finish(
            element: element,
            profile: profile,
            kind: built.kind,
            geometry: built.geometry,
            caption: caption(for: profile, kind: built.kind, element: element),
            isSimplified: built.isSimplified,
            isMetallic: isMetallic,
            tintHex: tint
        )
    }

    /// One honest paragraph per profile: what the picture is, and what it is
    /// standing in for.
    private static func caption(
        for profile: ElementStructureProfile,
        kind: StructureSceneKind,
        element: ChemicalElement
    ) -> String {
        var sentences: [String] = []
        switch kind {
        case .diatomicMolecule:
            sentences.append("Two atoms joined by a \(profile.primaryBondOrder.displayName.lowercased()). "
                             + "This is how the free element exists.")
        case .molecularCrystal:
            sentences.append("One \(element.elementalFormFormula) molecule from a solid built of them.")
        case .metallicLattice where profile.representationKind == .complexCrystal:
            break
        case .metallicLattice where profile.representationKind == .rhombohedral
            || profile.representationKind == .orthorhombic:
            sentences.append("A conventional unit cell. The struts show which atoms are nearest neighbors; "
                             + "in a metal the outer electrons are shared across the whole lattice.")
        case .metallicLattice:
            sentences.append("A conventional unit cell of the \(profile.representationKind.displayName.lowercased()) "
                             + "lattice. The struts show which atoms touch, not individual bonds: in a "
                             + "metal the outer electrons are shared across the whole lattice.")
        case .covalentNetwork where profile.representationKind == .diamondCubic:
            sentences.append("A conventional unit cell: every atom is bonded to four neighbors in a "
                             + "continuous network. There are no molecules in it.")
        case .covalentNetwork:
            sentences.append("A fragment of the structure. The bonds continue beyond the atoms shown.")
        case .monatomicGas:
            sentences.append("Separate atoms: a noble gas does not bond to itself, so there is no "
                             + "molecule to draw.")
        case .liquid:
            sentences.append("Liquid at room temperature, so there is no lattice — the arrangement "
                             + "shown is representative and changes constantly.")
        case .polyatomicMolecule, .atomModel, .compound:
            break
        }
        if let notes = profile.notes, !notes.isEmpty {
            sentences.append(notes)
        }
        return sentences.joined(separator: " ")
    }

    // MARK: - Atom model

    private static func atomScene(for element: ChemicalElement, entry: ElementStructureEntry) -> StructureScene {
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
            nodes.append(StructureNode(id: nextID, role: role, position: position, radius: 0.042))
            nextID += 1
        }

        let shells = element.shellElectrons.filter { $0 > 0 }
        for (shellIndex, count) in shells.enumerated() {
            let radius = shellRadius(index: shellIndex, of: shells.count)
            for position in sphereDistribution(count: count, radius: radius, phase: Double(shellIndex) * 0.7) {
                nodes.append(StructureNode(
                    id: nextID, role: .electron, position: position, radius: 0.032, shellIndex: shellIndex + 1
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
        var detail: String?
        if entry.isUnknown {
            detail = "Bulk crystal structure not established"
            caption = "Only individual atoms of \(element.name) have ever been made, so its bulk "
                + "structure is not known. " + caption
        }

        return StructureScene(
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
            nucleonSampleNote: sampleNote,
            representationLabel: entry.isUnknown
                ? StructureRepresentationKind.unknown.honestLabel
                : "Simplified atomic model",
            detail: detail,
            isEstablished: !entry.isUnknown,
            source: entry.isUnknown ? shortSource(entry.primary.source) : nil
        ).normalized()
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
    struct Geometry {
        var positions: [SIMD3<Float>]
        var links: [(Int, Int, StructureBondOrder, Bool)]
        var atomRadius: Float
    }

    static func diatomic(order: StructureBondOrder) -> Geometry {
        Geometry(
            positions: [SIMD3(-0.42, 0, 0), SIMD3(0.42, 0, 0)],
            links: [(0, 1, order, true)],
            atomRadius: 0.34
        )
    }

    /// Several separate atoms, far enough apart that nothing reads as a bond.
    static func monatomicGas() -> Geometry {
        Geometry(
            positions: sphereDistribution(count: 6, radius: 0.72, phase: 0.4),
            links: [],
            atomRadius: 0.19
        )
    }

    static func tetrahedron() -> Geometry {
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
    static func crownRing(atomCount: Int) -> Geometry {
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

    /// An open helix, three atoms per turn. Used for selenium and tellurium,
    /// whose chains genuinely do not close into rings.
    static func helicalChain(atomCount: Int) -> Geometry {
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
    static func icosahedron() -> Geometry {
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

    /// A fragment of a hexagonal sheet — one central ring with its six outer
    /// neighbors, so every ring atom shows its three bonds.
    ///
    /// With `pucker` the two sublattices are displaced above and below the
    /// plane, which is the corrugated layer of gray arsenic, antimony and
    /// bismuth. With two `layers` and a `stackShift` the second sheet sits
    /// above the first offset by one bond length, which is the AB stacking of
    /// graphite; no struts join the layers, because nothing but weak forces
    /// does.
    static func hexagonalSheet(layers: Int, pucker: Float, stackShift: Float) -> Geometry {
        // Bond length 1. Sublattice A at the hexagon corners, sublattice B one
        // bond away, laid out around a hexagon center at the origin.
        var positions: [SIMD3<Float>] = []
        var links: [(Int, Int, StructureBondOrder, Bool)] = []
        let ringRadius: Float = 1
        let layerSpacing: Float = 2.36   // graphite: 3.35 Å over a 1.42 Å bond
        for layer in 0..<layers {
            let base = positions.count
            let y = (Float(layer) - Float(layers - 1) / 2) * layerSpacing
            // AB stacking: the second layer is shifted by one bond so its
            // hexagon center sits over an atom of the first.
            let shift = layer.isMultiple(of: 2) ? 0 : stackShift * ringRadius
            for index in 0..<6 {
                let angle = Float(index) / 6 * 2 * .pi + .pi / 6
                let sublatticeUp = index.isMultiple(of: 2)
                let lift = sublatticeUp ? pucker : -pucker
                positions.append(SIMD3(cos(angle) * ringRadius + shift, y + lift, sin(angle) * ringRadius))
            }
            for index in 0..<6 {
                let angle = Float(index) / 6 * 2 * .pi + .pi / 6
                // The outer neighbor of each ring atom lies straight out
                // from the center, one bond further.
                let sublatticeUp = !index.isMultiple(of: 2)
                let lift = sublatticeUp ? pucker : -pucker
                positions.append(SIMD3(cos(angle) * ringRadius * 2 + shift, y + lift, sin(angle) * ringRadius * 2))
            }
            for index in 0..<6 {
                links.append((base + index, base + (index + 1) % 6, .single, true))
                links.append((base + index, base + 6 + index, .single, true))
            }
        }
        return Geometry(positions: positions, links: links, atomRadius: 0.24)
    }

    /// The stacking sequence of a hexagonal close-packed prism.
    enum HexagonalStacking {
        /// ABAB: hexagonal close-packed. Layers at 0, ½ and 1 of the cell.
        case abab
        /// ABAC: double hexagonal close-packed. Layers at 0, ¼, ½, ¾ and 1.
        case abac
    }

    /// A hexagonal prism of close-packed layers: a seven-atom hexagon for
    /// every A layer, and the three atoms of the B (or C) layer that sit in
    /// its hollows. Contacts join every pair at the nearest-neighbor distance,
    /// so the twelve-fold coordination of the central atom is visible.
    static func hexagonalPrism(stacking: HexagonalStacking, cOverA: Float) -> Geometry {
        var positions: [SIMD3<Float>] = []
        let a: Float = 1
        let hollow = a / 3.0.squareRoot().float

        func hexagon(y: Float) {
            positions.append(SIMD3(0, y, 0))
            for index in 0..<6 {
                let angle = Float(index) / 6 * 2 * .pi
                positions.append(SIMD3(cos(angle) * a, y, sin(angle) * a))
            }
        }
        func hollows(y: Float, rotated: Bool) {
            for index in 0..<3 {
                let angle = Float(index) / 3 * 2 * .pi + (rotated ? .pi / 2 : .pi / 6)
                positions.append(SIMD3(cos(angle) * hollow, y, sin(angle) * hollow))
            }
        }

        let c = cOverA * a
        switch stacking {
        case .abab:
            // The full layer in the middle, three atoms above and below: the
            // central atom then touches six in its plane and three on each
            // side, the twelve neighbors that define close packing.
            hollows(y: -c / 2, rotated: false)
            hexagon(y: 0)
            hollows(y: c / 2, rotated: false)
        case .abac:
            hexagon(y: -c / 2)
            hollows(y: -c / 4, rotated: false)
            hexagon(y: 0)
            hollows(y: c / 4, rotated: true)
            hexagon(y: c / 2)
        }

        let links = contacts(among: positions, factor: 1.12, discrete: false, order: .single)
        return Geometry(positions: positions, links: links, atomRadius: 0.30 * a)
    }

    /// Fractional basis of the cubic cells, in the conventional setting.
    static let simpleCubicBasis: [SIMD3<Float>] = [SIMD3(0, 0, 0)]
    static let bccBasis: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(0.5, 0.5, 0.5)]
    static let fccBasis: [SIMD3<Float>] = [
        SIMD3(0, 0, 0), SIMD3(0.5, 0.5, 0), SIMD3(0.5, 0, 0.5), SIMD3(0, 0.5, 0.5),
    ]
    static let diamondBasis: [SIMD3<Float>] = [
        SIMD3(0, 0, 0), SIMD3(0.5, 0.5, 0), SIMD3(0.5, 0, 0.5), SIMD3(0, 0.5, 0.5),
        SIMD3(0.25, 0.25, 0.25), SIMD3(0.75, 0.75, 0.25), SIMD3(0.75, 0.25, 0.75), SIMD3(0.25, 0.75, 0.75),
    ]

    /// A conventional cubic cell with edge 1.
    static func cubicCell(
        basis: [SIMD3<Float>],
        contactFactor: Float,
        discrete: Bool,
        order: StructureBondOrder,
        radiusFactor: Float
    ) -> Geometry {
        cell(
            a: SIMD3(1, 0, 0), b: SIMD3(0, 1, 0), c: SIMD3(0, 0, 1),
            basis: basis, contactFactor: contactFactor, discrete: discrete, order: order,
            radiusFactor: radiusFactor
        )
    }

    /// The explicit cell a `lattice` profile describes, or `nil` when the
    /// profile is missing the numbers it needs.
    static func explicitCell(profile: ElementStructureProfile, order: StructureBondOrder) -> Geometry? {
        guard let geometry = profile.geometry, let rawBasis = geometry.basis,
              let parameters = profile.latticeParameters, let a = parameters.a else { return nil }
        let basis = rawBasis.compactMap { row -> SIMD3<Float>? in
            guard row.count == 3 else { return nil }
            return SIMD3(Float(row[0]), Float(row[1]), Float(row[2]))
        }
        guard !basis.isEmpty, basis.count == rawBasis.count else { return nil }
        let b = parameters.b ?? a
        let c = parameters.c ?? a
        let vectors = latticeVectors(
            a: Float(a), b: Float(b), c: Float(c),
            alpha: Float(parameters.alpha ?? 90), beta: Float(parameters.beta ?? 90),
            gamma: Float(parameters.gamma ?? 90)
        )
        let discrete = geometry.discreteBonds ?? profile.hasDiscreteBonds
        return cell(
            a: vectors.0, b: vectors.1, c: vectors.2,
            basis: basis, contactFactor: Float(geometry.contactFactor ?? 1.06),
            discrete: discrete, order: order, radiusFactor: discrete ? 0.24 : 0.28
        )
    }

    /// Lattice vectors from cell edges and angles, in the usual convention:
    /// a along x, b in the xy plane.
    static func latticeVectors(
        a: Float, b: Float, c: Float, alpha: Float, beta: Float, gamma: Float
    ) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        let radians = Float.pi / 180
        let cosAlpha = cos(alpha * radians)
        let cosBeta = cos(beta * radians)
        let cosGamma = cos(gamma * radians)
        let sinGamma = max(sin(gamma * radians), 0.0001)
        let cy = (cosAlpha - cosBeta * cosGamma) / sinGamma
        let cz = max(0, 1 - cosBeta * cosBeta - cy * cy).squareRoot()
        return (
            SIMD3(a, 0, 0),
            SIMD3(b * cosGamma, b * sinGamma, 0),
            SIMD3(c * cosBeta, c * cy, c * cz)
        )
    }

    /// Every atom of the basis translated into the cell, including the copies
    /// on its far faces, edges and corners, so the cell is drawn whole; then
    /// contacts between every pair at the nearest-neighbor distance.
    static func cell(
        a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>,
        basis: [SIMD3<Float>],
        contactFactor: Float,
        discrete: Bool,
        order: StructureBondOrder,
        radiusFactor: Float
    ) -> Geometry {
        let tolerance: Float = 0.002
        var positions: [SIMD3<Float>] = []
        for atom in basis {
            for i in -1...1 {
                for j in -1...1 {
                    for k in -1...1 {
                        let fractional = atom + SIMD3(Float(i), Float(j), Float(k))
                        guard fractional.x >= -tolerance, fractional.x <= 1 + tolerance,
                              fractional.y >= -tolerance, fractional.y <= 1 + tolerance,
                              fractional.z >= -tolerance, fractional.z <= 1 + tolerance
                        else { continue }
                        let cartesian = a * fractional.x + b * fractional.y + c * fractional.z
                        if !positions.contains(where: { distance($0, cartesian) < 0.001 }) {
                            positions.append(cartesian)
                        }
                    }
                }
            }
        }
        let center = (a + b + c) / 2
        positions = positions.map { $0 - center }
        let links = contacts(among: positions, factor: contactFactor, discrete: discrete, order: order)
        let nearest = nearestDistance(among: positions)
        return Geometry(positions: positions, links: links, atomRadius: radiusFactor * nearest)
    }

    /// Links between every pair closer than `factor` times the shortest
    /// distance in the set.
    static func contacts(
        among positions: [SIMD3<Float>],
        factor: Float,
        discrete: Bool,
        order: StructureBondOrder
    ) -> [(Int, Int, StructureBondOrder, Bool)] {
        let nearest = nearestDistance(among: positions)
        guard nearest > 0 else { return [] }
        var links: [(Int, Int, StructureBondOrder, Bool)] = []
        for a in 0..<positions.count {
            for b in (a + 1)..<positions.count where distance(positions[a], positions[b]) <= nearest * factor {
                links.append((a, b, order, discrete))
            }
        }
        return links
    }

    static func nearestDistance(among positions: [SIMD3<Float>]) -> Float {
        var nearest = Float.greatestFiniteMagnitude
        for a in 0..<positions.count {
            for b in (a + 1)..<positions.count {
                nearest = min(nearest, distance(positions[a], positions[b]))
            }
        }
        return nearest == Float.greatestFiniteMagnitude ? 1 : nearest
    }

    /// Coordination number twelve: one atom surrounded by the twelve that touch
    /// it in a close-packed metal. The struts mark contact, not covalent bonds.
    static func closePackedCluster() -> Geometry {
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

    /// A liquid metal: close-packed positions with each atom nudged off its
    /// site by a seeded jitter, and no struts, because a liquid has no fixed
    /// neighbors. The seed is fixed so the picture is the same every time.
    static func liquidCluster() -> Geometry {
        var generator = SeededGenerator(seed: 0x80)
        var positions = closePackedCluster().positions
        let d: Float = 0.52
        for axis in 0..<3 {
            for sign in [Float(-1), 1] {
                var point = SIMD3<Float>(0, 0, 0)
                point[axis] = sign * d * 1.02
                positions.append(point)
            }
        }
        positions = positions.map { point in
            let jitter = SIMD3<Float>(
                Float.random(in: -0.11...0.11, using: &generator),
                Float.random(in: -0.11...0.11, using: &generator),
                Float.random(in: -0.11...0.11, using: &generator)
            )
            return point + jitter * d
        }
        return Geometry(positions: positions, links: [], atomRadius: 0.24)
    }

    /// A molecular liquid: four diatomic molecules at seeded random
    /// orientations, bonded within each pair and not between them.
    static func molecularLiquid(order: StructureBondOrder) -> Geometry {
        var generator = SeededGenerator(seed: 0x35)
        let s: Float = 0.46
        let centers = [
            SIMD3<Float>(s, s, s), SIMD3<Float>(s, -s, -s),
            SIMD3<Float>(-s, s, -s), SIMD3<Float>(-s, -s, s),
        ]
        var positions: [SIMD3<Float>] = []
        var links: [(Int, Int, StructureBondOrder, Bool)] = []
        let half: Float = 0.21
        for center in centers {
            let theta = Float.random(in: 0...(2 * .pi), using: &generator)
            let phi = Float.random(in: 0...Float.pi, using: &generator)
            let axis = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
            let first = positions.count
            positions.append(center + axis * half)
            positions.append(center - axis * half)
            links.append((first, first + 1, order, true))
        }
        return Geometry(positions: positions, links: links, atomRadius: 0.19)
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
        profile: ElementStructureProfile,
        kind: StructureSceneKind,
        geometry: Geometry,
        caption: String,
        isSimplified: Bool,
        isMetallic: Bool,
        tintHex: UInt32?
    ) -> StructureScene {
        let nodes = geometry.positions.enumerated().map { index, position in
            StructureNode(
                id: index,
                role: .atom,
                position: position,
                radius: geometry.atomRadius,
                atomicNumber: element.atomicNumber,
                tintHex: tintHex
            )
        }
        let bonds = geometry.links.enumerated().map { index, link in
            StructureBond(id: index, from: link.0, to: link.1, order: link.2, isDiscreteBond: link.3)
        }
        var detail = profile.latticeSummary
        if detail == nil, let geometry = profile.molecularGeometry {
            var line = geometry.prefix(1).uppercased() + geometry.dropFirst()
            if let length = profile.bondLengthAngstrom { line += " · bond \(length) Å" }
            detail = line
        }
        let label = isSimplified && profile.representationKind.isCrystal
            ? "Representative crystal fragment"
            : profile.representationKind.honestLabel
        return StructureScene(
            id: "\(element.symbol)-\(profile.representationKind.rawValue)-\(profile.allotropeName ?? "form")",
            atomicNumber: element.atomicNumber,
            symbol: element.symbol,
            elementName: element.name,
            kind: kind,
            nodes: nodes,
            bonds: bonds,
            formula: element.elementalFormFormula,
            caption: caption,
            isSimplified: isSimplified,
            representationLabel: label,
            detail: detail,
            allotropeName: profile.allotropeName,
            coordination: profile.coordination,
            isMetallic: isMetallic,
            isEstablished: profile.isExperimentallyEstablished,
            source: shortSource(profile.source)
        ).normalized()
    }

    /// "CRC Handbook of Chemistry and Physics" from the full citation.
    static func shortSource(_ source: String) -> String {
        let head = source.split(separator: ",").first.map(String.init) ?? source
        return head.split(separator: ";").first.map(String.init) ?? head
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
