import Foundation

/// Encodes a selection into a RealityKit entity name and back.
///
/// RealityKit hit testing hands back an `Entity`, and the only thing carried
/// across that boundary is the entity's name. Getting this mapping wrong is how
/// "tapping an atom selects the wrong one" happens, so the whole mapping is a
/// pure string function with tests rather than string building scattered
/// through the scene builder.
enum StructureEntityName {
    private static let nodePrefix = "node-"
    private static let bondPrefix = "bond-"
    /// The container every part is parented to. Named so the renderer can find
    /// it without holding a reference across a view update.
    static let root = "structure-root"

    static func node(_ id: Int) -> String { "\(nodePrefix)\(id)" }
    static func bond(_ id: Int) -> String { "\(bondPrefix)\(id)" }

    /// The selection a tapped entity name refers to, or `.none` when the name
    /// belongs to something that is not selectable — a light, the camera, the
    /// root, or an entity from some future addition to the scene.
    static func selection(for name: String) -> StructureSelection {
        if let id = identifier(name, prefix: nodePrefix) { return .node(id) }
        if let id = identifier(name, prefix: bondPrefix) { return .bond(id) }
        return .none
    }

    private static func identifier(_ name: String, prefix: String) -> Int? {
        guard name.hasPrefix(prefix) else { return nil }
        return Int(name.dropFirst(prefix.count))
    }
}
