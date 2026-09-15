import Foundation

/// The visual vocabulary the decorative element artwork is drawn from.
///
/// Ten treatments cover all 118 elements. Every one of them is procedural — no
/// raster assets, nothing downloaded, nothing per-element to maintain — so the
/// app stays offline and the bundle stays small. Which treatment an element
/// gets is decided by `ElementArtwork.kind(for:)` from data the dataset already
/// carries, with a short list of named exceptions for the elements people
/// picture most vividly.
enum ElementArtworkKind: String, CaseIterable, Hashable, Sendable {
    /// Rounded, faceted nugget forms. Gold, copper, silver, the soft metals.
    case nuggets
    /// Angular cut gems. Diamond-phase carbon, silicon, germanium.
    case facetedGems
    /// A connected grid of nodes: metallic crystal structure.
    case lattice
    /// Paired glossy spheres, for the elements that go about in twos.
    case pairedSpheres
    /// Reflective liquid beads. Mercury, bromine.
    case droplets
    /// Angular crystal shards, for the yellow-crystal non-metals.
    case crystalShards
    /// Soft luminous blooms, for the gases that glow when excited.
    case luminousGas
    /// Brushed, softly reflective sheets. The bright reactive metals.
    case metallicSheen
    /// Stacked hexagonal plates. Graphite-like layered solids.
    case hexPlates
    /// Abstract orbital arcs. Reserved for elements whose bulk form is not
    /// something anyone has ever seen — the synthetic superheavies — where
    /// drawing a confident lump of metal would be a small lie.
    case orbitalArcs

    /// A short, honest caption. Shown to VoiceOver so the decoration is
    /// described rather than silently skipped, and used in tests.
    var accessibilityDescription: String {
        switch self {
        case .nuggets: return "soft metallic nugget shapes"
        case .facetedGems: return "cut crystal facets"
        case .lattice: return "a metallic lattice of connected nodes"
        case .pairedSpheres: return "pairs of glossy spheres"
        case .droplets: return "reflective liquid beads"
        case .crystalShards: return "angular crystal shards"
        case .luminousGas: return "a soft luminous glow"
        case .metallicSheen: return "brushed metallic sheets"
        case .hexPlates: return "stacked hexagonal plates"
        case .orbitalArcs: return "abstract orbital arcs"
        }
    }
}

/// How strongly a treatment should read. The brief for this artwork is that it
/// is felt rather than looked at, so every value here is deliberately low.
enum ElementArtworkProminence: Sendable {
    /// Behind an expanded hero.
    case hero
    /// Beside a large favorite or study card.
    case card

    var opacity: Double {
        switch self {
        case .hero: return 0.24
        case .card: return 0.16
        }
    }

    /// Forms are drawn softly out of focus so they never pull the eye off the
    /// symbol. The hero can afford a touch more definition than a small card.
    var blurRadius: Double {
        switch self {
        case .hero: return 1.5
        case .card: return 2.5
        }
    }
}

/// Everything the renderer needs, resolved once from an element.
///
/// This is a plain value type with no SwiftUI in it, so the mapping from 118
/// elements to a visual treatment is unit-testable on its own.
struct ElementArtworkDescriptor: Hashable, Sendable {
    let kind: ElementArtworkKind
    /// Deterministic per element: the same element always gets the same
    /// arrangement of forms, on every launch and every redraw. Artwork that
    /// reshuffled while you scrolled would read as a glitch.
    let seed: UInt64
    /// How many forms to scatter. Kept low — this is texture, not a scene.
    let formCount: Int
    /// Named elements carry their own color so gold looks like gold rather
    /// than like the transition-metal family tint. `nil` means "use the
    /// element's family accent", which is what most elements do.
    let tintHex: UInt32?

    static let fallback = ElementArtworkDescriptor(
        kind: .orbitalArcs,
        seed: 0x5EED,
        formCount: 4,
        tintHex: nil
    )
}

/// Resolves an element to its decorative treatment.
enum ElementArtwork {
    // MARK: - Named exceptions

    /// The elements people can picture. Everything else is resolved by rule.
    ///
    /// This list is deliberately short. It exists so that the handful of
    /// elements a learner already has a mental image of — gold, sulfur, neon —
    /// look the way they expect, which is what makes the rest of the system
    /// read as designed rather than generated.
    private static let namedKinds: [String: ElementArtworkKind] = [
        "H": .pairedSpheres,
        "C": .facetedGems,
        "N": .pairedSpheres,
        "O": .pairedSpheres,
        "Na": .metallicSheen,
        "Mg": .metallicSheen,
        "Al": .facetedGems,
        "Si": .facetedGems,
        "P": .crystalShards,
        "S": .crystalShards,
        "Ti": .lattice,
        "Cr": .lattice,
        "Fe": .lattice,
        "Ni": .lattice,
        "Cu": .nuggets,
        "Zn": .nuggets,
        "Ge": .facetedGems,
        "Se": .crystalShards,
        "Ag": .nuggets,
        "Sn": .nuggets,
        "I": .crystalShards,
        "W": .lattice,
        "Pt": .nuggets,
        "Au": .nuggets,
        "Hg": .droplets,
        "Pb": .nuggets,
    ]

    /// Warm gold, copper and the other colors a family accent cannot supply.
    /// Stored as packed RGB so this file stays free of SwiftUI.
    private static let namedTints: [String: UInt32] = [
        "C": 0x3A4048,   // graphite gray, with a diamond-bright highlight
        "Na": 0xB9C2CC,  // soft silver
        "Mg": 0xC3C9CE,
        "Al": 0xC9D2DA,
        "P": 0xE8B04B,   // white phosphorus waxy yellow
        "S": 0xE3C037,   // sulfur yellow
        "Ti": 0xB6BEC6,
        "Fe": 0x9AA4AE,
        "Cu": 0xC87B45,  // copper
        "Zn": 0xAEB8C0,
        "Se": 0xA8544A,  // red selenium
        "Ag": 0xC5CCD3,  // silver
        "Sn": 0xB4BCC3,
        "I": 0x6B4C8A,   // iodine violet
        "W": 0x8E979F,
        "Pt": 0xCBD1D6,
        "Au": 0xD9A441,  // gold
        "Hg": 0xB7BEC6,  // quicksilver
        "Pb": 0x8E939B,
    ]

    // MARK: - Resolution

    /// The treatment for an element. Total: every element resolves.
    static func kind(for element: ChemicalElement) -> ElementArtworkKind {
        if let named = namedKinds[element.symbol] { return named }

        // Nobody has ever seen a gram of livermorium. An abstract treatment is
        // the honest one; a confident metallic ingot would not be.
        if element.phase == .unknown { return .orbitalArcs }
        if element.phase == .liquid { return .droplets }

        switch element.structure {
        case .monatomicGas: return .luminousGas
        case .diatomic: return .pairedSpheres
        case .polyatomicMolecule: return .crystalShards
        case .covalentNetwork: return .facetedGems
        case .atom: return .orbitalArcs
        case .metallicLattice:
            switch element.category {
            case .alkaliMetal, .alkalineEarthMetal, .lanthanide, .actinide:
                return .metallicSheen
            case .postTransitionMetal:
                return .nuggets
            case .transitionMetal:
                return .lattice
            case .metalloid:
                return .facetedGems
            // A non-metal in a metallic lattice is not something the dataset
            // currently contains, but the switch stays exhaustive so adding a
            // row to elements.json can never fall through to nothing.
            case .reactiveNonmetal, .halogen, .nobleGas:
                return .hexPlates
            }
        }
    }

    /// How many forms a treatment scatters. Sparse on purpose.
    static func formCount(for kind: ElementArtworkKind) -> Int {
        switch kind {
        case .nuggets: return 6
        case .facetedGems: return 5
        case .lattice: return 7
        case .pairedSpheres: return 4
        case .droplets: return 7
        case .crystalShards: return 6
        case .luminousGas: return 4
        case .metallicSheen: return 5
        case .hexPlates: return 6
        case .orbitalArcs: return 3
        }
    }

    static func descriptor(for element: ChemicalElement) -> ElementArtworkDescriptor {
        let kind = kind(for: element)
        return ElementArtworkDescriptor(
            kind: kind,
            // Mixed with a constant so two elements with adjacent atomic
            // numbers do not produce near-identical layouts.
            seed: UInt64(element.atomicNumber) &* 0x9E37_79B9 &+ 0x7F4A_7C15,
            formCount: formCount(for: kind),
            tintHex: namedTints[element.symbol]
        )
    }
}
