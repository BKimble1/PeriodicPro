import CoreGraphics
import Foundation

/// Projects a structure's model-space points onto a 2D canvas.
///
/// Pure maths, kept out of the drawing code so it can be tested: the failure
/// this guards against is a model that renders off-screen, or one whose nearest
/// atom crosses the camera plane and turns inside out.
struct StructureProjection {
    /// Yaw, then pitch, in radians.
    var yaw: Double
    var pitch: Double
    /// 1 fills the canvas with a scene of bounding radius 1.
    var zoom: Double
    /// Canvas size in points.
    var size: CGSize

    /// Distance from the eye to the origin, in model units. Scenes are
    /// normalized to a bounding radius of 1, so 4 keeps the whole model
    /// comfortably in front of the camera at every rotation: the nearest point
    /// any scene can reach is z = 1, leaving 3 units of clearance.
    static let cameraDistance: Double = 4

    /// A point's projected position and its depth.
    struct Projected {
        let point: CGPoint
        /// Rotated z. Larger is nearer the viewer; used for painter ordering.
        let depth: Double
        /// How much a unit of model-space size is magnified at this depth.
        let scale: Double
    }

    /// The radius, in points, that one model unit occupies at the origin.
    private var baseRadius: Double {
        Double(min(size.width, size.height)) * 0.5 * 0.86 * max(zoom, 0.01)
    }

    func project(_ position: SIMD3<Float>) -> Projected {
        let rotated = Self.rotate(position, yaw: yaw, pitch: pitch)

        // Perspective divide. Clamped so a point that somehow sits on the
        // camera plane produces a large-but-finite scale instead of an infinity
        // that would poison every later comparison.
        let distance = max(Self.cameraDistance - rotated.z, 0.25)
        let scale = Self.cameraDistance / distance

        return Projected(
            point: CGPoint(
                x: Double(size.width) / 2 + rotated.x * baseRadius * scale,
                y: Double(size.height) / 2 - rotated.y * baseRadius * scale
            ),
            depth: rotated.z,
            scale: scale
        )
    }

    /// Model-space radius to on-canvas radius at a given projected scale.
    func radius(_ modelRadius: Float, scale: Double) -> Double {
        Double(modelRadius) * baseRadius * scale
    }

    /// Rotation about Y then X. Returned as doubles because everything
    /// downstream is Core Graphics.
    static func rotate(_ position: SIMD3<Float>, yaw: Double, pitch: Double)
        -> (x: Double, y: Double, z: Double) {
        let x = Double(position.x)
        let y = Double(position.y)
        let z = Double(position.z)

        let cy = cos(yaw), sy = sin(yaw)
        let x1 = x * cy + z * sy
        let z1 = -x * sy + z * cy

        let cp = cos(pitch), sp = sin(pitch)
        let y2 = y * cp - z1 * sp
        let z2 = y * sp + z1 * cp

        return (x1, y2, z2)
    }

    /// Pitch is clamped so the model can never be rolled past vertical, which
    /// is disorienting and makes the drag gesture feel broken.
    static let pitchLimit: Double = 1.35

    static func clampPitch(_ value: Double) -> Double {
        min(max(value, -pitchLimit), pitchLimit)
    }

    /// Zoom bounds. The lower bound keeps the model from shrinking to a dot;
    /// the upper keeps it from filling the view so completely that nothing can
    /// be identified.
    static let zoomRange: ClosedRange<Double> = 0.6...2.6

    static func clampZoom(_ value: Double) -> Double {
        min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }
}
