import Foundation

/// What a node in a structure scene actually represents.
///
/// Keeping protons, neutrons and electrons in the same scene type as whole
/// atoms means the viewer, the hit testing, the inspector and the VoiceOver
/// fallback are written once rather than twice.
enum StructureNodeRole: String, Hashable, Sendable {
    /// A whole atom in a molecule or lattice.
    case atom
    case proton
    case neutron
    case electron
}

/// One sphere in the scene.
struct StructureNode: Identifiable, Hashable, Sendable {
    /// Unique within its scene. Used as the RealityKit entity name, as the
    /// selection identity, and as the row identity in the accessible list.
    let id: Int
    let role: StructureNodeRole
    /// Model-space position. Scenes are normalized to roughly fit a sphere of
    /// radius 1, so the viewer can frame any structure with one camera distance.
    let position: SIMD3<Float>
    /// Model-space radius.
    let radius: Float
    /// Which electron shell this node belongs to, 1-based. Only meaningful for
    /// `.electron`; `nil` everywhere else.
    let shellIndex: Int?
    /// The element this atom is, for scenes that mix elements — a compound.
    /// `nil` means the scene's own element.
    let atomicNumber: Int?
    /// Packed RGB for the atom's own color: gold for gold, red for oxygen.
    /// `nil` means the renderer falls back to the family accent.
    let tintHex: UInt32?

    init(
        id: Int,
        role: StructureNodeRole,
        position: SIMD3<Float>,
        radius: Float,
        shellIndex: Int? = nil,
        atomicNumber: Int? = nil,
        tintHex: UInt32? = nil
    ) {
        self.id = id
        self.role = role
        self.position = position
        self.radius = radius
        self.shellIndex = shellIndex
        self.atomicNumber = atomicNumber
        self.tintHex = tintHex
    }
}

/// How strongly two atoms are held together. Used for the visual (one, two or
/// three struts) and for the inspector copy.
enum StructureBondOrder: Int, Hashable, Sendable {
    case single = 1
    case double = 2
    case triple = 3

    var displayName: String {
        switch self {
        case .single: return "Single bond"
        case .double: return "Double bond"
        case .triple: return "Triple bond"
        }
    }

    var notation: String {
        switch self {
        case .single: return "—"
        case .double: return "="
        case .triple: return "≡"
        }
    }
}

/// A link between two nodes.
struct StructureBond: Identifiable, Hashable, Sendable {
    let id: Int
    let from: Int
    let to: Int
    let order: StructureBondOrder
    /// Metallic and network structures are drawn with connecting struts for
    /// legibility, but those struts are not discrete two-electron bonds. Marking
    /// them keeps the inspector from claiming otherwise.
    let isDiscreteBond: Bool
}

/// The kind of thing being shown, which decides the caption and the inspector's
/// vocabulary.
enum StructureSceneKind: String, Hashable, Sendable {
    case diatomicMolecule
    case polyatomicMolecule
    /// A solid made of discrete molecules (S₈, I₂, P₄); one molecule is shown.
    case molecularCrystal
    case metallicLattice
    case covalentNetwork
    /// Separate closed-shell atoms — a noble gas.
    case monatomicGas
    /// Mercury, bromine: close contact, no lattice.
    case liquid
    case atomModel
    /// A molecule or ionic unit of more than one element.
    case compound
}

/// A complete, renderer-independent description of one structure.
///
/// Nothing in this file imports SwiftUI or RealityKit. The whole mapping from
/// an element to its geometry is therefore testable without a GPU, which is the
/// only part of the 3D feature that can be verified off a device.
struct StructureScene: Identifiable, Hashable, Sendable {
    let id: String
    let atomicNumber: Int
    let symbol: String
    let elementName: String
    let kind: StructureSceneKind
    let nodes: [StructureNode]
    let bonds: [StructureBond]
    /// Short label, e.g. "O₂" or "Au".
    let formula: String
    /// One honest paragraph about what is being shown.
    let caption: String
    /// True when the picture is a teaching simplification or a fragment
    /// rather than a faithful cell or molecule. The viewer always shows a
    /// badge when so.
    let isSimplified: Bool
    /// Set when the nucleus shows fewer nucleons than the element really has,
    /// so the caption can say so rather than implying a miscount.
    let nucleonSampleNote: String?
    /// The honesty label: "Representative crystal unit cell", "Simplified
    /// atomic model", "Bulk structure not established", and so on.
    let representationLabel: String
    /// The lattice or molecule in one line: "face-centered cubic (Fm-3m) ·
    /// a = 4.078 Å". `nil` when there is nothing established to say.
    let detail: String?
    /// "Graphite", "α-iron (ferrite)": the allotrope, when it has a name.
    let allotropeName: String?
    /// Nearest-neighbor count in the real structure, when known.
    let coordination: Int?
    /// Electrons shared across the whole structure: rendered as metal, and
    /// its struts described as contacts rather than bonds.
    let isMetallic: Bool
    /// False when the bulk form has never been observed.
    let isEstablished: Bool
    /// Where the numbers come from, in a few words.
    let source: String?

    init(
        id: String,
        atomicNumber: Int,
        symbol: String,
        elementName: String,
        kind: StructureSceneKind,
        nodes: [StructureNode],
        bonds: [StructureBond],
        formula: String,
        caption: String,
        isSimplified: Bool,
        nucleonSampleNote: String? = nil,
        representationLabel: String,
        detail: String? = nil,
        allotropeName: String? = nil,
        coordination: Int? = nil,
        isMetallic: Bool = false,
        isEstablished: Bool = true,
        source: String? = nil
    ) {
        self.id = id
        self.atomicNumber = atomicNumber
        self.symbol = symbol
        self.elementName = elementName
        self.kind = kind
        self.nodes = nodes
        self.bonds = bonds
        self.formula = formula
        self.caption = caption
        self.isSimplified = isSimplified
        self.nucleonSampleNote = nucleonSampleNote
        self.representationLabel = representationLabel
        self.detail = detail
        self.allotropeName = allotropeName
        self.coordination = coordination
        self.isMetallic = isMetallic
        self.isEstablished = isEstablished
        self.source = source
    }

    var atoms: [StructureNode] { nodes.filter { $0.role == .atom } }
    var electrons: [StructureNode] { nodes.filter { $0.role == .electron } }

    func node(id: Int) -> StructureNode? { nodes.first { $0.id == id } }
    func bond(id: Int) -> StructureBond? { bonds.first { $0.id == id } }

    /// The largest distance from the origin to any node surface. The camera uses
    /// this to frame the scene, so a lone atom and a lattice both fill the view.
    var boundingRadius: Float {
        nodes.reduce(Float(0)) { longest, node in
            max(longest, length(node.position) + node.radius)
        }
    }

    /// The same scene with every node and bond scaled so the bounding radius
    /// is 1, which lets the viewer frame every structure with one camera.
    func normalized() -> StructureScene {
        let radius = boundingRadius
        guard radius > 0.0001, abs(radius - 1) > 0.0001 else { return self }
        let factor = 1 / radius
        let scaled = nodes.map { node in
            StructureNode(
                id: node.id,
                role: node.role,
                position: node.position * factor,
                radius: node.radius * factor,
                shellIndex: node.shellIndex,
                atomicNumber: node.atomicNumber,
                tintHex: node.tintHex
            )
        }
        return StructureScene(
            id: id,
            atomicNumber: atomicNumber,
            symbol: symbol,
            elementName: elementName,
            kind: kind,
            nodes: scaled,
            bonds: bonds,
            formula: formula,
            caption: caption,
            isSimplified: isSimplified,
            nucleonSampleNote: nucleonSampleNote,
            representationLabel: representationLabel,
            detail: detail,
            allotropeName: allotropeName,
            coordination: coordination,
            isMetallic: isMetallic,
            isEstablished: isEstablished,
            source: source
        )
    }
}

/// Euclidean length. Written out rather than pulled from `simd` so this file
/// has no import beyond Foundation and stays trivially testable.
private func length(_ vector: SIMD3<Float>) -> Float {
    (vector.x * vector.x + vector.y * vector.y + vector.z * vector.z).squareRoot()
}

// MARK: - Selection

/// What the learner has tapped, if anything.
enum StructureSelection: Hashable, Sendable {
    case none
    case node(Int)
    case bond(Int)

    var nodeID: Int? {
        if case .node(let id) = self { return id }
        return nil
    }

    var bondID: Int? {
        if case .bond(let id) = self { return id }
        return nil
    }

    var isEmpty: Bool { self == .none }
}

/// The contents of the compact panel that appears when something is selected.
///
/// Built as data so the wording can be unit-tested — this is the part of the
/// feature most likely to drift into saying something untrue about physics.
struct StructureFacts: Hashable, Sendable {
    let title: String
    let subtitle: String
    let rows: [Row]

    struct Row: Hashable, Sendable {
        let label: String
        let value: String
    }
}
