import Foundation

/// The ten element families used throughout the app.
///
/// The classification follows the most widely agreed convention: the six
/// universally accepted metalloids (B, Si, Ge, As, Sb, Te), polonium grouped
/// with the post-transition metals, and astatine with the halogens.
/// See `DATA_SOURCES.md` for the full rationale.
enum ElementCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case alkaliMetal
    case alkalineEarthMetal
    case transitionMetal
    case postTransitionMetal
    case metalloid
    case reactiveNonmetal
    case halogen
    case nobleGas
    case lanthanide
    case actinide

    var id: String { rawValue }

    /// Full name used in headings and detail copy.
    var displayName: String {
        switch self {
        case .alkaliMetal: return "Alkali Metal"
        case .alkalineEarthMetal: return "Alkaline Earth Metal"
        case .transitionMetal: return "Transition Metal"
        case .postTransitionMetal: return "Post-Transition Metal"
        case .metalloid: return "Metalloid"
        case .reactiveNonmetal: return "Reactive Nonmetal"
        case .halogen: return "Halogen"
        case .nobleGas: return "Noble Gas"
        case .lanthanide: return "Lanthanide"
        case .actinide: return "Actinide"
        }
    }

    /// Pluralised name used in the legend and the progress breakdown.
    var pluralName: String {
        switch self {
        case .alkaliMetal: return "Alkali Metals"
        case .alkalineEarthMetal: return "Alkaline Earth Metals"
        case .transitionMetal: return "Transition Metals"
        case .postTransitionMetal: return "Post-Transition Metals"
        case .metalloid: return "Metalloids"
        case .reactiveNonmetal: return "Reactive Nonmetals"
        case .halogen: return "Halogens"
        case .nobleGas: return "Noble Gases"
        case .lanthanide: return "Lanthanides"
        case .actinide: return "Actinides"
        }
    }

    /// Compact label for tight spaces such as the table legend.
    var shortName: String {
        switch self {
        case .alkaliMetal: return "Alkali"
        case .alkalineEarthMetal: return "Alkaline Earth"
        case .transitionMetal: return "Transition"
        case .postTransitionMetal: return "Post-Transition"
        case .metalloid: return "Metalloid"
        case .reactiveNonmetal: return "Nonmetal"
        case .halogen: return "Halogen"
        case .nobleGas: return "Noble Gas"
        case .lanthanide: return "Lanthanide"
        case .actinide: return "Actinide"
        }
    }

    /// A short, non-color cue so category is never communicated by color alone.
    var glyph: String {
        switch self {
        case .alkaliMetal: return "circle.fill"
        case .alkalineEarthMetal: return "square.fill"
        case .transitionMetal: return "diamond.fill"
        case .postTransitionMetal: return "triangle.fill"
        case .metalloid: return "hexagon.fill"
        case .reactiveNonmetal: return "circle"
        case .halogen: return "square"
        case .nobleGas: return "diamond"
        case .lanthanide: return "triangle"
        case .actinide: return "hexagon"
        }
    }

    var family: ElementFamily {
        switch self {
        case .alkaliMetal, .alkalineEarthMetal, .transitionMetal,
             .postTransitionMetal, .lanthanide, .actinide:
            return .metal
        case .metalloid:
            return .metalloid
        case .reactiveNonmetal, .halogen, .nobleGas:
            return .nonmetal
        }
    }

    /// Display order used by the legend and the progress screen.
    static let displayOrder: [ElementCategory] = [
        .alkaliMetal, .alkalineEarthMetal, .transitionMetal, .postTransitionMetal,
        .metalloid, .reactiveNonmetal, .halogen, .nobleGas, .lanthanide, .actinide,
    ]
}

/// The three-way split surfaced by the primary filter chips.
enum ElementFamily: String, CaseIterable, Identifiable, Hashable, Sendable {
    case metal
    case nonmetal
    case metalloid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .metal: return "Metals"
        case .nonmetal: return "Nonmetals"
        case .metalloid: return "Metalloids"
        }
    }
}

/// State of the pure element at 298.15 K and 1 atm.
enum MatterPhase: String, Codable, CaseIterable, Hashable, Sendable {
    case solid
    case liquid
    case gas
    case unknown

    var displayName: String {
        switch self {
        case .solid: return "Solid"
        case .liquid: return "Liquid"
        case .gas: return "Gas"
        case .unknown: return "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .solid: return "cube.fill"
        case .liquid: return "drop.fill"
        case .gas: return "wind"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// How the element exists as a pure substance. Drives the secondary diagram
/// on the detail screen so an atom is never mislabelled as a molecule.
enum ElementStructure: String, Codable, CaseIterable, Hashable, Sendable {
    case atom
    case diatomic
    case polyatomicMolecule
    case metallicLattice
    case covalentNetwork
    case monatomicGas

    var displayName: String {
        switch self {
        case .atom: return "Single atoms"
        case .diatomic: return "Diatomic molecule"
        case .polyatomicMolecule: return "Polyatomic molecule"
        case .metallicLattice: return "Metallic lattice"
        case .covalentNetwork: return "Covalent network"
        case .monatomicGas: return "Monatomic gas"
        }
    }
}
