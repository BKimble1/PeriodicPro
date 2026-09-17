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

    /// Every SF Symbol the app's own interface draws, as opposed to the ones
    /// the dataset asks for. Kept here so a single test can prove that nothing
    /// anywhere in the app renders a blank icon, and so
    /// `Tools/lint_sources.py` can fail the build if a view introduces a symbol
    /// that was never checked.
    static let uiNames: Set<String> = [
        // Navigation and controls
        "chevron.right", "chevron.down", "arrow.right", "arrow.up.left", "checkmark",
        "checkmark.circle.fill", "xmark.circle.fill", "ellipsis.circle", "info.circle",
        "arrow.counterclockwise", "magnifyingglass", "clock", "gearshape",
        // States and empty states
        "heart", "heart.fill", "exclamationmark.triangle", "exclamationmark.triangle.fill",
        "tray", "questionmark.circle", "lightbulb.fill",
        // Onboarding
        "square.grid.3x3.fill", "hand.tap.fill", "graduationcap.fill",
        // Family glyphs, phase glyphs, mastery glyphs, study-mode glyphs, tabs
        "circle.fill", "square.fill", "diamond.fill", "triangle.fill", "hexagon.fill",
        "circle", "square", "diamond", "triangle", "hexagon",
        "cube.fill", "drop.fill", "wind",
        "circle.dotted", "circle.lefthalf.filled", "circle.righthalf.filled",
        "rectangle.on.rectangle.angled", "questionmark.circle.fill", "eye.fill",
        "chart.bar.fill", "flame.fill", "book.fill",
        // Pro, the paywall and the 3D structure explorer
        "xmark", "infinity", "scope", "cube.fill", "sparkles", "lock.fill",
        "arrow.up.right",
        // Compounds, the builder and the Build tab
        "circle.hexagongrid.fill", "plus.circle.fill", "plus", "minus",
        // Match, quiz setup and My Quizzes
        "arrow.left.arrow.right", "list.bullet.rectangle", "square.and.arrow.up",
        "doc.on.doc", "pencil", "textformat", "trash",
        "slider.horizontal.3", "square.grid.2x2", "atom",
        // Settings
        "creditcard", "envelope", "hand.raised", "doc.text", "globe",
        "sun.max.fill", "moon.stars.fill",
        // Saving and favoriting a compound
        "bookmark", "bookmark.fill",
    ]

    /// Everything the app can ask UIKit to draw.
    static var allNames: Set<String> { names.union(uiNames) }

    /// Guaranteed to exist on every supported OS version.
    static let fallback = "atom"

    static func contains(_ name: String) -> Bool { names.contains(name) }

    /// Never returns a name that would render as a blank space.
    ///
    /// Checked against `allNames`, not `names`. The two lists exist because the
    /// dataset and the interface are trusted differently — `contains(_:)` is
    /// what gates the dataset, and the unit tests enforce it — but both lists
    /// are equally "symbols this app draws on purpose". Gating this on the
    /// dataset list alone silently turned the paywall's `infinity` and
    /// `square.grid.3x3.fill` rows into atoms, because those are interface
    /// symbols and nothing in the dataset happens to use them.
    ///
    /// The allowlist is the first gate and `PeriodicProTests` proves every
    /// entry in it resolves; the `UIImage` check means even a symbol withdrawn
    /// by a future OS release degrades to the fallback rather than to nothing.
    @MainActor
    static func resolved(_ name: String) -> String {
        guard allNames.contains(name), UIImage(systemName: name) != nil else { return fallback }
        return name
    }
}
