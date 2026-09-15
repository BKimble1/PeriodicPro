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
    case metallicLattice
    case covalentNetwork
    case atomModel
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
    /// Short label, e.g. "O₂" or "Metallic lattice".
    let formula: String
    /// One honest sentence about what is being shown.
    let caption: String
    /// True when the picture is a teaching simplification rather than a
    /// depiction of measured structure. The viewer always shows a note when so.
    let isSimplified: Bool
    /// Set when the nucleus shows fewer nucleons than the element really has,
    /// so the caption can say so rather than implying a miscount.
    let nucleonSampleNote: String?

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
