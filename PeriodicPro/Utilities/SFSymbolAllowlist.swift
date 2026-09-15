import SwiftUI
import UIKit

/// Every SF Symbol name the bundled dataset is allowed to reference.
///
/// Keeping the list here rather than trusting the JSON means a typo shows up as
/// a failing unit test instead of an invisible gap in the "Common Uses" grid,
/// and `resolved(_:)` guarantees the UI always has something to draw.
enum SFSymbolAllowlist {
    static let names: Set<String> = [
        "atom", "flame.fill", "drop.fill", "leaf.fill", "bolt.fill", "bolt.horizontal.fill",
        "sun.max.fill", "lightbulb.fill", "sparkles", "sparkle", "star.fill", "heart.fill",
        "cross.case.fill", "pills.fill", "stethoscope", "bandage.fill", "syringe.fill",
        "lungs.fill", "brain.head.profile", "eye.fill", "figure.walk", "figure.stand",
        "cpu", "memorychip", "display", "iphone", "laptopcomputer", "tv.fill",
        "antenna.radiowaves.left.and.right", "wifi", "battery.100", "powerplug.fill",
        "car.fill", "airplane", "fuelpump.fill", "gearshape.fill", "wrench.and.screwdriver.fill",
        "hammer.fill", "building.2.fill", "house.fill", "shippingbox.fill", "cube.fill",
        "cylinder.fill", "testtube.2", "thermometer", "camera.fill", "photo.fill",
        "paintpalette.fill", "paintbrush.fill", "scissors", "fork.knife", "cup.and.saucer.fill",
        "carrot.fill", "clock.fill", "speaker.wave.3.fill", "radio.fill",
        "shield.fill", "lock.fill", "key.fill", "scalemass.fill", "chart.bar.fill", "globe",
        "moon.stars.fill", "wind", "snowflake", "cloud.fill", "water.waves", "tree.fill",
        "mountain.2.fill", "pawprint.fill", "book.fill", "gift.fill", "arrow.3.trianglepath",
        "circle.hexagongrid.fill", "hexagon.fill", "diamond.fill", "crown.fill",
        "bed.double.fill", "facemask.fill", "trash.fill", "rays", "waveform.path",
        "microphone.fill", "headphones", "gamecontroller.fill", "bicycle",
        "flashlight.on.fill", "ruler.fill", "binoculars.fill", "scope",
        "circle.grid.cross.fill", "wrench.adjustable.fill",
    ]

    /// Guaranteed to exist on every supported OS version.
    static let fallback = "atom"

    static func contains(_ name: String) -> Bool { names.contains(name) }

    /// Never returns a name that would render as a blank space.
    ///
    /// The allowlist is the first gate and `PeriodicProTests` proves every entry
    /// in it resolves; this second check means even a symbol withdrawn by a
    /// future OS release degrades to the fallback rather than to nothing.
    @MainActor
    static func resolved(_ name: String) -> String {
        guard names.contains(name), UIImage(systemName: name) != nil else { return fallback }
        return name
    }
}
