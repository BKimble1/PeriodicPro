import RealityKit
import SwiftUI
import UIKit
import simd

/// The real 3D viewer: a RealityKit scene the learner can turn, zoom and tap.
///
/// Geometry comes from `StructureScene`, which is pure data and fully tested.
/// This file is only the rendering and the gestures.
///
/// Performance notes, because a structure can hold a couple of hundred parts:
/// * one `MeshResource` per distinct radius and one `Material` per role are
///   built up front and shared by every part that uses them, so a 162-particle
///   atom model allocates three meshes and four materials, not 324 resources;
/// * the scene is built once, in `make`, and afterwards only the root entity's
///   transform changes — turning the model never rebuilds it;
/// * this view is only ever created inside the full-screen explorer, never
///   inside a scrolling card, so nothing here runs while the detail page
///   scrolls.
struct StructureRealityView: View {
    let scene: StructureScene
    /// Family accent for atoms. Identify mode never reaches this view.
    let accent: Color
    @Binding var selection: StructureSelection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The container everything is parented to. Held here so `update` can move
    /// it without searching the scene graph.
    @State private var root = Entity()
    @State private var builtSceneID: String?
    /// Kept from the last build so a selection change restyles the existing
    /// entities instead of rebuilding the model.
    @State private var palette: StructureEntityFactory.MaterialPalette?

    @State private var yaw: Double = 0.55
    @State private var pitch: Double = 0.28
    @State private var zoom: Double = 1
    /// Rotation at the moment a drag began, so the drag is absolute rather than
    /// accumulating rounding error each frame.
    @State private var yawAtDragStart: Double = 0
    @State private var pitchAtDragStart: Double = 0
    @State private var zoomAtPinchStart: Double = 1
    @State private var isInteracting = false
    /// The slow automatic turn. Separate from `yaw` so releasing a drag does
    /// not snap the model back.
    @State private var idleYaw: Double = 0

    private var idleRotates: Bool { !reduceMotion && !isInteracting && selection.isEmpty }

    var body: some View {
        RealityView { content in
            root.name = StructureEntityName.root
            rebuildIfNeeded()
            content.add(root)
            content.add(Self.makeCamera())
            for light in Self.makeLights() { content.add(light) }
            applyTransform()
        } update: { _ in
            rebuildIfNeeded()
            applyTransform()
            applyHighlight()
        }
        .gesture(
            // Double tap frames the model again. Exclusive so a double tap does
            // not also register as a selection.
            SpatialTapGesture(count: 2)
                .onEnded { _ in resetView() }
                .exclusively(
                    before: SpatialTapGesture()
                        .targetedToAnyEntity()
                        .onEnded { value in handleTap(on: value.entity) }
                )
        )
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
        .task(id: idleRotates) {
            guard idleRotates else { return }
            // A plain async loop rather than a Timer publisher: it is canceled
            // automatically when the view goes away or the id changes, so it
            // can never outlive the screen.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                if Task.isCancelled { return }
                idleYaw += 0.0035
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isInteracting {
                    isInteracting = true
                    yawAtDragStart = yaw
                    pitchAtDragStart = pitch
                }
                yaw = yawAtDragStart + Double(value.translation.width) * 0.011
                pitch = StructureProjection.clampPitch(
                    pitchAtDragStart + Double(value.translation.height) * 0.011
                )
            }
            .onEnded { _ in isInteracting = false }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if !isInteracting {
                    isInteracting = true
                    zoomAtPinchStart = zoom
                }
                zoom = StructureProjection.clampZoom(zoomAtPinchStart * value.magnification)
            }
            .onEnded { _ in isInteracting = false }
    }

    private func resetView() {
        Haptics.tap()
        withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
            yaw = 0.55
            pitch = 0.28
            zoom = 1
            idleYaw = 0
            selection = .none
        }
    }

    private func handleTap(on entity: Entity) {
        let tapped = StructureEntityName.selection(for: entity.name)
        guard !tapped.isEmpty else { return }
        Haptics.tap()
        withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
            selection = (tapped == selection) ? .none : tapped
        }
    }

    // MARK: - Scene construction

    private func rebuildIfNeeded() {
        guard builtSceneID != scene.id else { return }
        root.children.removeAll()
        palette = StructureEntityFactory.build(scene: scene, accent: accent, into: root)
        // Assigning @State from `make`/`update` is safe here because it is
        // guarded by the identity check above: it happens once per scene, not
        // once per frame, so it cannot loop.
        builtSceneID = scene.id
    }

    /// Zoom scales the model rather than moving the camera. Nothing can then
    /// cross the near plane however far the learner pinches in, which is the
    /// usual way a 3D viewer turns inside out.
    ///
    /// Selecting a part slides that part to the middle of the view and pushes
    /// in a little — the "camera focus" the model gets on selection, done by
    /// moving the model rather than the camera for the same reason.
    private func applyTransform() {
        let turn = yaw + (idleRotates ? idleYaw : 0)
        let rotation = simd_quatf(angle: Float(pitch), axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: Float(turn), axis: SIMD3(0, 1, 0))
        let effectiveZoom = Float(zoom) * (selection.isEmpty ? 1 : 1.25)

        var translation = SIMD3<Float>(repeating: 0)
        if let id = selection.nodeID, let node = scene.node(id: id) {
            // Rotate the node into view space, then move the model so that
            // point lands at the origin.
            translation = -(rotation.act(node.position) * effectiveZoom)
        }

        root.transform = Transform(
            scale: SIMD3(repeating: effectiveZoom),
            rotation: rotation,
            translation: translation
        )
    }

    /// Selection dims everything else rather than hiding it, so the learner
    /// keeps the context of where the selected part sits.
    private func applyHighlight() {
        guard let palette else { return }
        StructureEntityFactory.applyHighlight(selection: selection, palette: palette, in: root)
    }

    // MARK: - Camera and lighting

    private static func makeCamera() -> Entity {
        let camera = PerspectiveCamera()
        // Scenes are normalized to a bounding radius of 1. At this distance and
        // field of view the whole model sits inside the frame with margin at
        // every rotation, and the near plane is never approached.
        camera.camera.fieldOfViewInDegrees = 38
        camera.position = SIMD3(0, 0, 4)
        return camera
    }

    /// A three-point rig: a key light for form, a fill to keep the shadow side
    /// readable, and a rim from behind to separate the model from the
    /// background. This is what makes the spheres read as lit objects.
    private static func makeLights() -> [Entity] {
        let key = DirectionalLight()
        key.light.intensity = 3_200
        key.light.color = .white
        key.look(at: .zero, from: SIMD3(2.2, 3.0, 3.4), relativeTo: nil)

        let fill = DirectionalLight()
        fill.light.intensity = 1_100
        fill.light.color = UIColor(white: 0.92, alpha: 1)
        fill.look(at: .zero, from: SIMD3(-3.0, -0.6, 2.4), relativeTo: nil)

        let rim = DirectionalLight()
        rim.light.intensity = 1_600
        rim.light.color = UIColor(white: 1, alpha: 1)
        rim.look(at: .zero, from: SIMD3(-1.2, 1.8, -3.2), relativeTo: nil)

        return [key, fill, rim]
    }
}
