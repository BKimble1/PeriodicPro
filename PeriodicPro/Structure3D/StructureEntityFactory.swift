import RealityKit
import SwiftUI
import UIKit
import simd

/// Builds the RealityKit entities for a structure, and restyles them when the
/// selection changes.
///
/// Meshes and materials are shared aggressively. A scene has at most a handful
/// of distinct sphere radii and strut lengths, so the whole model is built from
/// a few resources no matter how many parts it has.
@MainActor
enum StructureEntityFactory {
    /// Thickness of a bond strut, in model units.
    private static let strutThickness: Float = 0.035

    // MARK: - Building

    /// Builds the model and returns the palette, which the caller keeps so
    /// selection changes can restyle without rebuilding and without this type
    /// holding any shared mutable state.
    @discardableResult
    static func build(scene: StructureScene, accent: Color, into root: Entity) -> MaterialPalette {
        let palette = MaterialPalette(scene: scene, accent: accent)
        var sphereMeshes: [Int: MeshResource] = [:]
        var strutMeshes: [Int: MeshResource] = [:]

        for node in scene.nodes {
            let key = Self.key(node.radius)
            let mesh: MeshResource
            if let cached = sphereMeshes[key] {
                mesh = cached
            } else {
                mesh = MeshResource.generateSphere(radius: node.radius)
                sphereMeshes[key] = mesh
            }

            let entity = ModelEntity(mesh: mesh, materials: [palette.material(for: node.role, state: .normal)])
            entity.name = StructureEntityName.node(node.id)
            entity.position = node.position
            // Hit testing is RealityKit's own, against a sphere that matches the
            // drawn geometry exactly — which is what stops a tap from selecting
            // a neighbor.
            entity.components.set(InputTargetComponent())
            entity.components.set(
                CollisionComponent(shapes: [ShapeResource.generateSphere(radius: node.radius)])
            )
            root.addChild(entity)
        }

        let positions = Dictionary(
            scene.nodes.map { ($0.id, $0.position) },
            uniquingKeysWith: { first, _ in first }
        )

        for bond in scene.bonds {
            guard let from = positions[bond.from], let to = positions[bond.to] else { continue }
            let offsets = strutOffsets(for: bond, from: from, to: to)
            for (index, offset) in offsets.enumerated() {
                guard let entity = makeStrut(
                    bond: bond,
                    strutIndex: index,
                    from: from + offset,
                    to: to + offset,
                    palette: palette,
                    cache: &strutMeshes
                ) else { continue }
                root.addChild(entity)
            }
        }

        return palette
    }

    /// Where the parallel struts of a double or triple bond sit.
    ///
    /// Offset perpendicular to the bond, in a direction that is guaranteed not
    /// to be parallel to it — picking a fixed up-vector would collapse the
    /// struts onto each other for a vertical bond.
    static func strutOffsets(
        for bond: StructureBond,
        from: SIMD3<Float>,
        to: SIMD3<Float>
    ) -> [SIMD3<Float>] {
        let count = bond.isDiscreteBond ? bond.order.rawValue : 1
        guard count > 1 else { return [.zero] }

        let axis = to - from
        let length = simd_length(axis)
        guard length > 0.0001 else { return Array(repeating: .zero, count: count) }
        let direction = axis / length

        // Cross with whichever world axis is least aligned with the bond.
        let reference: SIMD3<Float> = abs(direction.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        var perpendicular = simd_cross(direction, reference)
        let perpendicularLength = simd_length(perpendicular)
        guard perpendicularLength > 0.0001 else { return Array(repeating: .zero, count: count) }
        perpendicular /= perpendicularLength

        let spacing = strutThickness * 1.9
        let start = -Float(count - 1) / 2
        return (0..<count).map { perpendicular * ((start + Float($0)) * spacing) }
    }

    private static func makeStrut(
        bond: StructureBond,
        strutIndex: Int,
        from: SIMD3<Float>,
        to: SIMD3<Float>,
        palette: MaterialPalette,
        cache: inout [Int: MeshResource]
    ) -> ModelEntity? {
        let axis = to - from
        let length = simd_length(axis)
        guard length > 0.0001 else { return nil }

        let key = Self.key(length)
        let mesh: MeshResource
        if let cached = cache[key] {
            mesh = cached
        } else {
            // A rounded box rather than a cylinder: it reads the same at these
            // sizes and uses only mesh generation that has been available since
            // RealityKit shipped.
            mesh = MeshResource.generateBox(
                width: strutThickness,
                height: length,
                depth: strutThickness,
                cornerRadius: strutThickness / 2
            )
            cache[key] = mesh
        }

        let entity = ModelEntity(mesh: mesh, materials: [palette.strutMaterial(state: .normal)])
        // Every bar of a multiple bond carries the bond's name, so selecting a
        // double bond highlights both of its bars rather than lighting one and
        // dimming the other. Only the first gets a collider, so the bond is one
        // tap target rather than two overlapping ones.
        entity.name = StructureEntityName.bond(bond.id)
        entity.position = (from + to) / 2
        entity.orientation = Self.orientation(alongY: axis / length)

        if strutIndex == 0 {
            entity.components.set(InputTargetComponent())
            entity.components.set(CollisionComponent(shapes: [
                ShapeResource.generateBox(
                    width: strutThickness * 2.4,
                    height: length,
                    depth: strutThickness * 2.4
                ),
            ]))
        }
        return entity
    }

    /// Rotation taking the box's +Y axis onto `direction`.
    ///
    /// `simd_quatf(from:to:)` is undefined for exactly opposed vectors, so the
    /// antiparallel case is handled explicitly as a half turn.
    static func orientation(alongY direction: SIMD3<Float>) -> simd_quatf {
        let up = SIMD3<Float>(0, 1, 0)
        let dot = simd_dot(up, direction)
        if dot > 0.9999 { return simd_quatf(angle: 0, axis: up) }
        if dot < -0.9999 { return simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0)) }
        return simd_quatf(from: up, to: direction)
    }

    /// Rotation taking the entity's -Z axis onto `direction`, which is how a
    /// `DirectionalLight` is aimed.
    static func orientation(alongNegativeZ direction: SIMD3<Float>) -> simd_quatf {
        let forward = SIMD3<Float>(0, 0, -1)
        let dot = simd_dot(forward, direction)
        if dot > 0.9999 { return simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)) }
        if dot < -0.9999 { return simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0)) }
        return simd_quatf(from: forward, to: direction)
    }

    private static func key(_ value: Float) -> Int { Int((value * 1_000).rounded()) }

    // MARK: - Selection

    /// Restyles the model for the current selection: the chosen part grows a
    /// little and brightens, everything else darkens. Nothing is hidden, so the
    /// learner keeps the context of where the part sits.
    static func applyHighlight(
        selection: StructureSelection,
        palette: MaterialPalette,
        in root: Entity
    ) {
        for child in root.children {
            guard let model = child as? ModelEntity else { continue }
            let identity = StructureEntityName.selection(for: child.name)
            let state: MaterialState
            if selection.isEmpty {
                state = .normal
            } else if identity == selection {
                state = .highlighted
            } else {
                state = .dimmed
            }
            model.scale = SIMD3(repeating: state == .highlighted ? 1.18 : 1)
            model.model?.materials = [
                palette.isStrut(entityNamed: child.name)
                    ? palette.strutMaterial(state: state)
                    : palette.material(for: palette.role(ofEntityNamed: child.name), state: state),
            ]
        }
    }

    // MARK: - Materials

    enum MaterialState: String {
        case normal
        case highlighted
        case dimmed
    }

    /// One material per (role, state), built once per scene.
    final class MaterialPalette {
        private var materials: [String: PhysicallyBasedMaterial] = [:]
        private var roles: [String: StructureNodeRole] = [:]
        private let accent: Color
        private let isMetal: Bool

        init(scene: StructureScene, accent: Color) {
            self.accent = accent
            self.isMetal = scene.kind == .metallicLattice
            for node in scene.nodes {
                roles[StructureEntityName.node(node.id)] = node.role
            }
        }

        func role(ofEntityNamed name: String) -> StructureNodeRole {
            roles[name] ?? .atom
        }

        /// A strut is anything the node table does not know about: the extra
        /// bars of a multiple bond, and the selectable first bar.
        func isStrut(entityNamed name: String) -> Bool {
            roles[name] == nil
        }

        func material(for role: StructureNodeRole, state: MaterialState) -> PhysicallyBasedMaterial {
            cached(key: "\(role.rawValue)-\(state.rawValue)") {
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: Self.tint(role: role, accent: accent, state: state))
                material.roughness = .init(floatLiteral: Self.roughness(role: role, isMetal: isMetal))
                // Not fully metallic. A metallic PBR surface gets almost all of
                // its color from reflections, and this scene has directional
                // lights but no environment map — at 1.0 a gold lattice renders
                // nearly black. Partly metallic keeps the sheen and keeps the
                // element's own color.
                material.metallic = .init(floatLiteral: role == .atom && isMetal ? 0.45 : 0.0)
                if state == .highlighted {
                    material.emissiveColor = .init(color: UIColor(AppColor.accent))
                    material.emissiveIntensity = 0.45
                }
                return material
            }
        }

        func strutMaterial(state: MaterialState) -> PhysicallyBasedMaterial {
            cached(key: "strut-\(state.rawValue)") {
                var material = PhysicallyBasedMaterial()
                let base: CGFloat = state == .dimmed ? 0.42 : 0.66
                material.baseColor = .init(tint: UIColor(white: base, alpha: 1))
                material.roughness = .init(floatLiteral: 0.42)
                material.metallic = .init(floatLiteral: 0.1)
                if state == .highlighted {
                    material.emissiveColor = .init(color: UIColor(AppColor.accent))
                    material.emissiveIntensity = 0.4
                }
                return material
            }
        }

        private func cached(
            key: String,
            _ make: () -> PhysicallyBasedMaterial
        ) -> PhysicallyBasedMaterial {
            if let existing = materials[key] { return existing }
            let material = make()
            materials[key] = material
            return material
        }

        private static func tint(
            role: StructureNodeRole,
            accent: Color,
            state: MaterialState
        ) -> UIColor {
            let base: UIColor
            switch role {
            case .atom: base = UIColor(accent)
            case .proton: base = UIColor(AppColor.warning)
            case .neutron: base = UIColor(white: 0.62, alpha: 1)
            case .electron: base = UIColor(AppColor.accent)
            }
            switch state {
            case .normal, .highlighted: return base
            // Dimming by darkening rather than by going transparent: a
            // translucent model needs depth sorting that ball-and-stick
            // geometry cannot give reliably.
            case .dimmed: return base.withAlphaComponent(1).darkened(by: 0.55)
            }
        }

        private static func roughness(role: StructureNodeRole, isMetal: Bool) -> Float {
            switch role {
            case .atom: return isMetal ? 0.28 : 0.16
            case .proton, .neutron: return 0.4
            case .electron: return 0.1
            }
        }
    }
}

private extension UIColor {
    /// Blends toward black. Used for the dimmed selection state.
    func darkened(by amount: CGFloat) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return self }
        let factor = max(0, 1 - amount)
        return UIColor(red: red * factor, green: green * factor, blue: blue * factor, alpha: alpha)
    }
}
