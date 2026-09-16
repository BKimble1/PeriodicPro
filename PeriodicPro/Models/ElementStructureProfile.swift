import Foundation

/// The kind of thing an element's representative structure is.
///
/// This is the vocabulary of `structures.json`, and the renderer routes on it.
/// The cases are deliberately specific — gold and iron and magnesium are three
/// different lattices, not three copies of "metal" — and `unknown` is a real
/// case rather than a fallback, so an element whose bulk form has never been
/// observed is shown as an atom and labeled that way.
enum StructureRepresentationKind: String, Codable, CaseIterable, Hashable, Sendable {
    // Molecules, gases and liquids
    case monatomicGas
    case diatomicMolecule
    case polyatomicMolecule
    case molecularCrystal
    case molecularLiquid
    case liquidMetal
    // Crystals
    case fcc
    case bcc
    case hcp
    case dhcp
    case simpleCubic
    case diamondCubic
    case graphite
    case rhombohedral
    case orthorhombic
    case tetragonal
    case helicalChain
    case complexCrystal
    // Honest absence
    case unknown

    var displayName: String {
        switch self {
        case .monatomicGas: return "Monatomic gas"
        case .diatomicMolecule: return "Diatomic molecule"
        case .polyatomicMolecule: return "Polyatomic molecule"
        case .molecularCrystal: return "Molecular crystal"
        case .molecularLiquid: return "Molecular liquid"
        case .liquidMetal: return "Liquid metal"
        case .fcc: return "Face-centered cubic"
        case .bcc: return "Body-centered cubic"
        case .hcp: return "Hexagonal close-packed"
        case .dhcp: return "Double hexagonal close-packed"
        case .simpleCubic: return "Simple cubic"
        case .diamondCubic: return "Diamond cubic"
        case .graphite: return "Layered hexagonal"
        case .rhombohedral: return "Rhombohedral"
        case .orthorhombic: return "Orthorhombic"
        case .tetragonal: return "Tetragonal"
        case .helicalChain: return "Helical chains"
        case .complexCrystal: return "Complex crystal"
        case .unknown: return "Not established"
        }
    }

    /// A periodic solid drawn as a cell or a fragment of one.
    var isCrystal: Bool {
        switch self {
        case .fcc, .bcc, .hcp, .dhcp, .simpleCubic, .diamondCubic, .graphite,
             .rhombohedral, .orthorhombic, .tetragonal, .helicalChain, .complexCrystal:
            return true
        case .monatomicGas, .diatomicMolecule, .polyatomicMolecule, .molecularCrystal,
             .molecularLiquid, .liquidMetal, .unknown:
            return false
        }
    }

    /// Whether the atoms share electrons across the whole structure, which is
    /// what makes the rendering read as metal and the struts read as contacts
    /// rather than bonds.
    var isMetallic: Bool {
        switch self {
        case .fcc, .bcc, .hcp, .dhcp, .simpleCubic, .tetragonal, .complexCrystal, .liquidMetal:
            return true
        case .orthorhombic, .rhombohedral:
            // Gallium, uranium and neptunium are metals; arsenic, antimony and
            // bismuth are semimetals with real three-fold bonding. The profile
            // decides through `bondOrders`, not the kind alone.
            return false
        case .monatomicGas, .diatomicMolecule, .polyatomicMolecule, .molecularCrystal,
             .molecularLiquid, .diamondCubic, .graphite, .helicalChain, .unknown:
            return false
        }
    }

    /// The one-line honesty label every scene carries.
    var honestLabel: String {
        switch self {
        case .monatomicGas: return "Single atoms, no bonds"
        case .diatomicMolecule, .polyatomicMolecule, .molecularCrystal, .molecularLiquid:
            return "Representative molecular structure"
        case .liquidMetal: return "Representative liquid arrangement"
        case .fcc, .bcc, .hcp, .dhcp, .simpleCubic, .diamondCubic, .graphite,
             .rhombohedral, .orthorhombic, .tetragonal, .helicalChain:
            return "Representative crystal unit cell"
        case .complexCrystal: return "Simplified crystal fragment"
        case .unknown: return "Bulk structure not established"
        }
    }
}

/// Cell edges in ångströms and angles in degrees. Only the ones that are not
/// implied by the crystal system are given; a cubic cell carries `a` alone.
struct LatticeParameters: Codable, Hashable, Sendable {
    let a: Double?
    let b: Double?
    let c: Double?
    let alpha: Double?
    let beta: Double?
    let gamma: Double?

    /// "a = 4.078 Å" / "a = 3.209 Å, c = 5.211 Å".
    var summary: String? {
        var parts: [String] = []
        if let a { parts.append("a = \(Self.format(a)) Å") }
        if let b { parts.append("b = \(Self.format(b)) Å") }
        if let c { parts.append("c = \(Self.format(c)) Å") }
        if let alpha { parts.append("α = \(Self.format(alpha))°") }
        if let beta { parts.append("β = \(Self.format(beta))°") }
        if let gamma { parts.append("γ = \(Self.format(gamma))°") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func format(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        if rounded == rounded.rounded() { return "\(Int(rounded))" }
        return "\(rounded)"
    }
}

/// How the geometry generator should build the scene for a profile.
///
/// Most kinds imply their generator (`fcc`, `hcp` and so on). `lattice` is the
/// explicit form: a conventional cell from `LatticeParameters` plus fractional
/// atom positions, with contacts drawn between every pair closer than
/// `contactFactor` times the nearest-neighbor distance.
struct StructureGeometrySpec: Codable, Hashable, Sendable {
    let template: String
    let cOverA: Double?
    let basis: [[Double]]?
    let contactFactor: Double?
    let discreteBonds: Bool?
}

/// One representative structure for an element: what it is, where the numbers
/// come from, and how sure anyone is.
struct ElementStructureProfile: Codable, Hashable, Sendable {
    let representationKind: StructureRepresentationKind
    let allotropeName: String?
    let phase: MatterPhase
    let crystalSystem: String?
    let latticeType: String?
    let spaceGroup: String?
    let latticeParameters: LatticeParameters?
    let molecularGeometry: String?
    let bondOrders: [Int]?
    let bondLengthAngstrom: Double?
    let coordination: Int?
    let temperatureContext: String
    let isExperimentallyEstablished: Bool
    let source: String
    let notes: String?
    let geometry: StructureGeometrySpec?
    /// The short word on the allotrope picker. `nil` means the kind's default.
    let pickerTitle: String?

    /// The bond order used for a diatomic or a uniform molecule.
    var primaryBondOrder: StructureBondOrder {
        StructureBondOrder(rawValue: bondOrders?.first ?? 1) ?? .single
    }

    /// Bonds in this structure are discrete two-electron bonds rather than
    /// the shared sea of a metal. Set explicitly by the geometry, otherwise
    /// inferred from whether the profile names bond orders.
    var hasDiscreteBonds: Bool {
        if let explicit = geometry?.discreteBonds { return explicit }
        return bondOrders != nil
    }

    /// "Face-centered cubic (Fm-3m), a = 4.078 Å" — the lattice in one line.
    var latticeSummary: String? {
        guard representationKind.isCrystal || representationKind == .molecularCrystal else { return nil }
        var line = latticeType ?? representationKind.displayName
        if let spaceGroup { line += " (\(spaceGroup))" }
        if let parameters = latticeParameters?.summary { line += " · \(parameters)" }
        return line
    }

    /// The word on the segmented picker.
    var title: String {
        if let pickerTitle { return pickerTitle }
        switch representationKind {
        case .monatomicGas: return "Gas"
        case .diatomicMolecule, .polyatomicMolecule: return "Molecule"
        case .molecularCrystal: return "Molecule"
        case .molecularLiquid, .liquidMetal: return "Liquid"
        case .unknown: return "Atom"
        default: return "Crystal"
        }
    }

    /// The heading above the preview on the detail page.
    var headline: String {
        if let allotropeName { return allotropeName }
        return representationKind.displayName
    }
}

/// An element's primary structure plus any allotropes worth offering.
struct ElementStructureEntry: Codable, Hashable, Identifiable, Sendable {
    let atomicNumber: Int
    let primary: ElementStructureProfile
    let alternatives: [ElementStructureProfile]

    var id: Int { atomicNumber }

    var allProfiles: [ElementStructureProfile] { [primary] + alternatives }

    /// True when nothing about the bulk form is known — the atom is all the
    /// app can honestly show.
    var isUnknown: Bool { primary.representationKind == .unknown }
}
