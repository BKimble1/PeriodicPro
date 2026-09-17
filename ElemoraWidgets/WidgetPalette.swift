import SwiftUI
import UIKit

/// The widget's colors, written out rather than read from an asset catalog.
///
/// The asset catalog belongs to the app target. A widget extension is its own
/// bundle and would need its own copy of it, which is a second place for the
/// palette to drift. These are the same sRGB values the app's catalog and icon
/// use, in one small file that `Tools/check_widget_shared.py` compares
/// against the icon's palette so the two cannot diverge unnoticed.
enum WidgetPalette {
    /// The teal the icon and the app's accent are built on.
    static let accent = Color(
        light: Color(red: 27 / 255, green: 128 / 255, blue: 141 / 255),
        dark: Color(red: 52 / 255, green: 166 / 255, blue: 180 / 255)
    )
    static let gold = Color(
        light: Color(red: 213 / 255, green: 168 / 255, blue: 84 / 255),
        dark: Color(red: 226 / 255, green: 181 / 255, blue: 96 / 255)
    )
    static let canvas = Color(
        light: Color(red: 247 / 255, green: 245 / 255, blue: 240 / 255),
        dark: Color(red: 18 / 255, green: 20 / 255, blue: 21 / 255)
    )
    /// Right and wrong. Never carried by color alone — every use is paired
    /// with a symbol and with words, because a learner who cannot distinguish
    /// these two hues still has to be told which it was.
    static let correct = Color(
        light: Color(red: 22 / 255, green: 120 / 255, blue: 74 / 255),
        dark: Color(red: 60 / 255, green: 178 / 255, blue: 122 / 255)
    )
    static let incorrect = Color(
        light: Color(red: 168 / 255, green: 58 / 255, blue: 48 / 255),
        dark: Color(red: 224 / 255, green: 108 / 255, blue: 96 / 255)
    )
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
}

extension Color {
    /// A color that resolves differently in light and dark.
    ///
    /// The app has the same initializer against `UIColor`; this is the
    /// extension's own copy, because the app's is in the app target.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
