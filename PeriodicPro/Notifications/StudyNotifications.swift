import Foundation
import UserNotifications

/// What a notification is for.
///
/// Five kinds, all of them about studying. There is no marketing category and
/// there is no room for one: everything here either tells the learner that
/// something is waiting for them or that a thing they were doing is still
/// open.
enum StudyNotificationCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Items the spaced-review schedule says are due.
    case reviewDue
    /// Today's five questions.
    case dailyChallenge
    /// A streak that is still alive and has not been used today.
    case streak
    /// Nothing for several days.
    case inactivity
    /// A plain reminder at the chosen time.
    case studyReminder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reviewDue: return "Review Due"
        case .dailyChallenge: return "Daily Challenge"
        case .streak: return "Streak Reminder"
        case .inactivity: return "Inactivity Reminder"
        case .studyReminder: return "Study Reminder"
        }
    }

    var explanation: String {
        switch self {
        case .reviewDue: return "When elements or compounds are ready to review again."
        case .dailyChallenge: return "When today's five-question challenge is ready."
        case .streak: return "Only while a streak is running and you have not studied yet."
        case .inactivity: return "After a few quiet days. At most once a week."
        case .studyReminder: return "A plain reminder at the time you choose."
        }
    }

    /// Which one wins when several apply on the same day.
    ///
    /// Lower is more useful. A streak about to lapse and a pile of overdue
    /// review are things the learner would want to know; a generic reminder is
    /// the one to drop.
    var priority: Int {
        switch self {
        case .streak: return 0
        case .reviewDue: return 1
        case .dailyChallenge: return 2
        case .studyReminder: return 3
        case .inactivity: return 4
        }
    }

    /// Where tapping it should land.
    var destination: NotificationDestination {
        switch self {
        case .reviewDue: return .smartReview
        case .dailyChallenge: return .dailyChallenge
        case .streak, .studyReminder: return .study
        case .inactivity: return .study
        }
    }
}

/// Where a notification takes the learner.
enum NotificationDestination: String, Codable, Sendable {
    case study
    case smartReview
    case dailyChallenge
    case progress

    static let userInfoKey = "elemora.destination"

    init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo[Self.userInfoKey] as? String,
              let value = NotificationDestination(rawValue: raw) else { return nil }
        self = value
    }

    var userInfo: [String: String] { [Self.userInfoKey: rawValue] }

    /// Which tab this lands on.
    var tab: AppTab {
        switch self {
        case .study, .smartReview, .dailyChallenge: return .study
        case .progress: return .progress
        }
    }
}

extension Notification.Name {
    /// Posted when the learner taps one of Elemora's own notifications.
    static let elemoraNotificationTapped = Notification.Name("elemora.notificationTapped")
}

/// Receives taps from the system and turns them into a destination.
///
/// The only reason this class exists: `UNUserNotificationCenter` needs a
/// delegate object, and SwiftUI has nowhere to put one. It does no work
/// beyond reading the destination back out of the notification it created.
final class StudyNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let destination = NotificationDestination(userInfo: userInfo) else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .elemoraNotificationTapped, object: destination)
        }
    }

    /// Shown while the app is open, too — a reminder that arrives while the
    /// learner is already studying is silently dropped by the system
    /// otherwise, which reads as a bug.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

/// Whether Elemora may post notifications at all.
enum NotificationAuthorization: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    /// Allowed, but only quietly — no banner, no sound.
    case provisional
}

/// One notification, planned but not yet handed to the system.
struct PlannedNotification: Equatable, Identifiable, Sendable {
    /// Stable, and derived from the category and the day, so re-planning
    /// replaces a request rather than adding a second one.
    let id: String
    let category: StudyNotificationCategory
    let title: String
    let body: String
    /// When it should fire.
    let date: Date
    var destination: NotificationDestination { category.destination }

    static func identifier(_ category: StudyNotificationCategory, dayKey: String) -> String {
        "elemora.study.\(category.rawValue).\(dayKey)"
    }
}

/// What the learner has turned on.
///
/// Everything is off by default. Notification permission is never requested at
/// launch and never requested as a side effect of anything else — the learner
/// turns a category on in Settings, is told what it does, and only then is the
/// system asked.
struct NotificationPreferences: Codable, Equatable, Sendable {
    /// The master switch. Off means nothing is ever scheduled, whatever else
    /// is set.
    var isEnabled: Bool = false
    var enabledCategories: Set<StudyNotificationCategory> = []
    /// When a reminder should arrive, in the learner's own calendar.
    var preferredHour: Int = 18
    var preferredMinute: Int = 30

    static let storageKey = "notifications.preferences"

    /// The categories a learner gets when they first turn notifications on.
    ///
    /// Two, both of which only fire when there is genuinely something waiting.
    /// Not all five — turning on a switch is not consent to everything behind
    /// it.
    static let defaultCategories: Set<StudyNotificationCategory> = [.reviewDue, .streak]

    var isCategoryEnabled: (StudyNotificationCategory) -> Bool {
        { [enabledCategories, isEnabled] category in
            isEnabled && enabledCategories.contains(category)
        }
    }

    func enabling(_ category: StudyNotificationCategory, _ on: Bool) -> NotificationPreferences {
        var copy = self
        if on { copy.enabledCategories.insert(category) } else { copy.enabledCategories.remove(category) }
        return copy
    }

    /// The time of day a notification should arrive on a given date.
    func time(on date: Date, calendar: Calendar) -> Date? {
        calendar.date(
            bySettingHour: min(max(preferredHour, 0), 23),
            minute: min(max(preferredMinute, 0), 59),
            second: 0,
            of: date
        )
    }
}

/// Everything the planner needs to know about the learner, as a value.
///
/// Passed in rather than read, so every rule below is a pure function of a
/// struct and can be asserted without a device, a clock or a notification
/// center.
struct StudyNotificationState: Equatable, Sendable {
    var hasStudiedToday: Bool = false
    var currentStreak: Int = 0
    /// Elements and compounds the review schedule says are due.
    var dueReviewCount: Int = 0
    /// Whole days since anything was answered. `nil` when nothing ever was.
    var daysSinceLastStudy: Int?
    var hasCompletedDailyChallengeToday: Bool = false
    /// When an inactivity reminder was last sent, so a second one waits.
    var lastInactivityNotification: Date?
}
