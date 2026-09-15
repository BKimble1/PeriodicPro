import UIKit

/// Thin wrapper over UIKit feedback generators.
///
/// Deliberately sparse: a tap on an element, a favorite toggle, and the
/// outcome of an answer. Nothing fires on scroll, appearance or navigation.
@MainActor
enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()

    /// Disabled during UI tests so recorded runs stay deterministic.
    static var isEnabled = !RuntimeFlags.isUITesting

    /// Prepares the generators just before a burst of feedback.
    static func warmUp() {
        guard isEnabled else { return }
        selection.prepare()
        soft.prepare()
        rigid.prepare()
        notification.prepare()
    }

    /// Tapping an element tile, a chip, or a card.
    static func tap() {
        guard isEnabled else { return }
        selection.selectionChanged()
    }

    /// Favouriting: a slightly weightier confirmation.
    static func favorited(_ on: Bool) {
        guard isEnabled else { return }
        if on { rigid.impactOccurred(intensity: 0.7) } else { soft.impactOccurred(intensity: 0.5) }
    }

    /// Revealing a flashcard answer.
    static func reveal() {
        guard isEnabled else { return }
        soft.impactOccurred(intensity: 0.6)
    }

    static func correct() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }

    static func incorrect() {
        guard isEnabled else { return }
        notification.notificationOccurred(.warning)
    }

    static func sessionComplete() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }
}
