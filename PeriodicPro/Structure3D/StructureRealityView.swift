import RealityKit
import SwiftUI
import UIKit
import simd

/// Holds the scene graph across view updates.
///
/// A reference type rather than a set of `@State` values, for a specific
/// reason: `RealityView`'s `update` closure runs *during* a SwiftUI view
/// update, and assigning to `@State` there is the "Modifying state during view
/// update" hazard. Mutating the properties of an object SwiftUI is merely
/// holding is not a state write, so the scene can be rebuilt and restyled from
/// `update` safely.
@MainActor
final class StructureSceneHost {
    let root = Entity()
    var builtKey: String?
    var palette: StructureEntityFactory.MaterialPalette?
    /// The selection the entities are currently styled for. Restyling on every
    /// frame would rewrite ~160 material arrays thirty times a second while the
    /// model idles.
    var styledSelection: StructureSelection = .none

    init() {
        root.name = StructureEntityName.root
    }
}

/// The real 3D viewer: a RealityKit scene the learner can turn, zoom and tap.
///
/// Geometry comes from `StructureScene`, which is pure data and fully tested.
/// This file is only the rendering and the gestures.
///
/// Performance notes, because a structure can hold a couple of hundred parts:
/// * one `MeshResource` per distinct radius and one `Material` per role and
///   state are built up front and shared, so a 162-particle atom model
///   allocates three meshes and a handful of materials, not 324 resources;
/// * the scene is built once per element and restyled only when the selection
///   actually changes — afterwards each frame writes one transform;
/// * this view is only ever created inside the full-screen explorer, never
///   inside a scrolling card.
struct StructureRealityView: View {
    let scene: StructureScene
    /// Family accent for atoms. Identify mode never reaches this view.
    let accent: Color
    @Binding var selection: StructureSelection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var host = StructureSceneHost()

    /// Where the model is being asked to sit.
    @State private var targetYaw: Double = 0.55
    @State private var targetPitch: Double = 0.28
    @State private var targetZoom: Double = 1
    /// Where it currently sits. Eased toward the target when the learner is not
    /// dragging, so a reset or a selection focus glides instead of teleporting;
    /// snapped to it while dragging, so turning the model feels direct.
    @State private var shownYaw: Double = 0.55
    @State private var shownPitch: Double = 0.28
    @State private var shownZoom: Double = 1

    @State private var yawAtDragStart: Double = 0
    @State private var pitchAtDragStart: Double = 0
    @State private var zoomAtPinchStart: Double = 1
    @State private var isDragging = false
    @State private var isPinching = false

    private var isInteracting: Bool { isDragging || isPinching }
    private var idleDrifts: Bool { !reduceMotion && !isInteracting && selection.isEmpty }

    var body: some View {
        RealityView { content in
            synchronize()
            content.add(host.root)
            content.add(Self.makeCamera())
            for light in Self.makeLights() { content.add(light) }
        } update: { _ in
            synchronize()
        }
        // Selection is the primary gesture and fires immediately. Making it
        // exclusive-after a double tap would delay every single tap by the
        // double-tap timeout, which on a model meant to be poked at is the
        // difference between responsive and broken.
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in handleTap(on: value.entity) }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                // Deferred by a frame so it always lands after the two single
                // taps SwiftUI also delivers, whatever order those arrive in.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(40))
                    resetView()
                }
            }
        )
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
        .task(id: tickerKey) { await runTicker() }
        .accessibilityHidden(true)
    }

    // MARK: - Animation

    /// Restarts the ticker when what it needs to do changes.
    private var tickerKey: String {
        "\(reduceMotion)-\(isInteracting)-\(selection)"
    }

    /// One loop drives both the idle drift and the easing toward a new target.
    ///
    /// Thirty ticks a second, each writing a single transform. It is canceled
    /// automatically when the view goes away, so it can never outlive the screen.
    private func runTicker() async {
        if reduceMotion {
            // No drift and no easing: go straight to wherever the model has
            // been asked to be.
            //
            // But keep going while a finger is down. Reduce Motion asks an app
            // to stop moving things by itself; it does not ask a model to stop
            // following the hand turning it. Returning here after a single
            // snap meant the only thing that moved the model during a drag —
            // this loop — was not running, so the scene sat still until the
            // gesture ended and then jumped to its final pose. Direct
            // manipulation that does not track is not a calmer animation, it
            // is a broken control.
            repeat {
                shownYaw = targetYaw
                shownPitch = targetPitch
                shownZoom = targetZoom
                guard isInteracting else { return }
                try? await Task.sleep(for: .milliseconds(16))
            } while !Task.isCancelled
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            if Task.isCancelled { return }
            if idleDrifts { targetYaw += 0.0035 }
            if isInteracting {
                shownYaw = targetYaw
                shownPitch = targetPitch
                shownZoom = targetZoom
            } else {
                let ease = 0.18
                shownYaw += (targetYaw - shownYaw) * ease
                shownPitch += (targetPitch - shownPitch) * ease
                shownZoom += (targetZoom - shownZoom) * ease
            }
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    // Take the baseline from where the model is actually shown,
                    // so grabbing a model that has been drifting does not snap
                    // it back to where the drift began.
                    targetYaw = shownYaw
                    yawAtDragStart = shownYaw
                    pitchAtDragStart = shownPitch
                }
                targetYaw = yawAtDragStart + Double(value.translation.width) * 0.011
                targetPitch = StructureProjection.clampPitch(
                    pitchAtDragStart + Double(value.translation.height) * 0.011
                )
            }
            .onEnded { _ in isDragging = false }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                // Its own flag: sharing one with the drag meant whichever
                // gesture started second never captured its baseline and jumped.
                if !isPinching {
                    isPinching = true
                    zoomAtPinchStart = shownZoom
                }
                targetZoom = StructureProjection.clampZoom(
                    zoomAtPinchStart * value.magnification
                )
            }
            .onEnded { _ in isPinching = false }
    }

    private func resetView() {
        Haptics.tap()
        targetYaw = 0.55
        targetPitch = 0.28
        targetZoom = 1
        selection = .none
    }

    private func handleTap(on entity: Entity) {
        let tapped = StructureEntityName.selection(for: entity.name)
        guard !tapped.isEmpty else { return }
        Haptics.tap()
        selection = (tapped == selection) ? .none : tapped
    }

    // MARK: - Scene

    /// Rebuilds when the element or the appearance changes, restyles when the
    /// selection changes, and always writes the current transform.
    private func synchronize() {
        // Materials are built from resolved UIColors, so a light/dark change has
        // to rebuild them — otherwise the model keeps the old palette.
        let key = "\(scene.id)-\(colorScheme)"
        if host.builtKey != key {
            host.root.children.removeAll()
            host.palette = StructureEntityFactory.build(
                scene: scene, accent: accent, into: host.root
            )
            host.builtKey = key
            host.styledSelection = .none
        }

        if host.styledSelection != selection, let palette = host.palette {
            StructureEntityFactory.applyHighlight(
                selection: selection, palette: palette, in: host.root
            )
            host.styledSelection = selection
        }

        applyTransform()
    }

    /// Zoom scales the model rather than moving the camera, so nothing can cross
    /// the near plane however far the learner pinches in.
    ///
    /// Selecting a part slides it to the middle of the view and pushes in a
    /// little. The slide is deliberately in x and y only: translating along z as
    /// well could carry the far side of the model past the camera, which is the
    /// one way this arrangement could still turn itself inside out.
    private func applyTransform() {
        let rotation = simd_quatf(angle: Float(shownPitch), axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: Float(shownYaw), axis: SIMD3(0, 1, 0))
        let zoom = Float(shownZoom) * (selection.isEmpty ? 1 : 1.25)

        var translation = SIMD3<Float>(repeating: 0)
        if let focus = focusPoint {
            let rotated = rotation.act(focus) * zoom
            translation = SIMD3(-rotated.x, -rotated.y, 0)
        }

        host.root.transform = Transform(
            scale: SIMD3(repeating: zoom),
            rotation: rotation,
            translation: translation
        )
    }

    /// The model-space point the view centers on. A bond centers on its
    /// midpoint, so selecting one does not zoom in and leave it off-screen.
    private var focusPoint: SIMD3<Float>? {
        switch selection {
        case .none:
            return nil
        case .node(let id):
            return scene.node(id: id)?.position
        case .bond(let id):
            guard let bond = scene.bond(id: id),
                  let from = scene.node(id: bond.from)?.position,
                  let to = scene.node(id: bond.to)?.position
            else { return nil }
            return (from + to) / 2
        }
    }

    // MARK: - Camera and lighting

    private static func makeCamera() -> Entity {
        let camera = PerspectiveCamera()
        // Scenes are normalized to a bounding radius of 1. At this distance and
        // field of view the whole model sits inside the frame at every rotation,
        // and the near plane is never approached.
        camera.camera.fieldOfViewInDegrees = 38
        camera.position = SIMD3(0, 0, 4)
        return camera
    }

    /// A four-light rig: a key light for form, a fill to keep the shadow side
    /// readable, a rim from behind to separate the model from the background,
    /// and a low, cool bounce from below. The bounce is there for the metals:
    /// a metallic surface shows only what lights it, and with nothing under
    /// the model the lower half of a gold lattice went black.
    private static func makeLights() -> [Entity] {
        [
            directionalLight(from: SIMD3(2.2, 3.0, 3.4), intensity: 3_400, white: 1),
            directionalLight(from: SIMD3(-3.0, -0.6, 2.4), intensity: 1_200, white: 0.92),
            directionalLight(from: SIMD3(-1.2, 1.8, -3.2), intensity: 1_700, white: 1),
            directionalLight(from: SIMD3(0.6, -3.0, 1.0), intensity: 700, white: 0.88),
        ]
    }

    /// Aimed by setting the orientation directly rather than with `look(at:)`,
    /// whose argument list differs between platforms and SDK versions. A
    /// DirectionalLight shines along its own negative z axis.
    private static func directionalLight(
        from position: SIMD3<Float>,
        intensity: Float,
        white: CGFloat
    ) -> Entity {
        let light = DirectionalLight()
        light.light.intensity = intensity
        light.light.color = UIColor(white: white, alpha: 1)
        light.position = position
        light.orientation = StructureEntityFactory.orientation(
            alongNegativeZ: simd_normalize(-position)
        )
        return light
    }
}
