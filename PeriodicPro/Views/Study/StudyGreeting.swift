import Foundation

/// The two-line greeting at the top of the Study tab.
///
/// Pure, so the wording and the hour boundaries are testable rather than
/// something that can only be checked by changing the device clock. No name is
/// used, because the app has no accounts and never asks for one.
enum StudyGreeting {
    /// "Good morning", "Good afternoon" or "Good evening".
    static func salutation(hour: Int) -> String {
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    static func salutation(at date: Date = Date(), calendar: Calendar = .current) -> String {
        salutation(hour: calendar.component(.hour, from: date))
    }

    /// The second line, which reflects what the learner has actually done
    /// rather than cheering unconditionally.
    static func encouragement(masteredCount: Int, streak: Int, hasStudied: Bool) -> String {
        if !hasStudied { return "Start exploring." }
        if streak >= 2 { return "Keep the streak going." }
        if masteredCount == 0 { return "Keep exploring." }
        return "Keep going."
    }

    static let supportingLine = "Small steps. Big knowledge."
}
