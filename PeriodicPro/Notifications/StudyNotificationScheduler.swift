import Foundation
import Observation
import OSLog
import UserNotifications

/// The system's notification center, behind a protocol so the scheduler can be
/// tested without one.
protocol NotificationScheduling: Sendable {
    func authorization() async -> NotificationAuthorization
    /// Presents the system prompt. Only ever called because the learner asked
    /// for a notification category.
    func requestAuthorization() async -> NotificationAuthorization
    func pendingIdentifiers() async -> [String]
    func removePending(identifiers: [String]) async
    func add(_ notification: PlannedNotification, calendar: Calendar) async
}

/// The real one.
struct SystemNotificationScheduler: NotificationScheduling {
    private static let logger = Logger(subsystem: "com.periodicpro.app", category: "notifications")

    func authorization() async -> NotificationAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral: return .authorized
        case .provisional: return .provisional
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async -> NotificationAuthorization {
        do {
            // Alert, sound and badge. Deliberately not `.criticalAlert` and
            // deliberately never `.timeSensitive` on a request: chemistry
            // study is not an interruption worth overriding a Focus for.
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted ? .authorized : .denied
        } catch {
            Self.logger.error("Notification authorization failed: \(String(describing: error), privacy: .public)")
            return .denied
        }
    }

    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func removePending(identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ notification: PlannedNotification, calendar: Calendar) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.userInfo = notification.destination.userInfo
        // `.active` rather than `.timeSensitive` or `.critical`: it is
        // delivered the ordinary way and a Focus silences it, which is
        // correct for a study reminder.
        content.interruptionLevel = .active
        content.relevanceScore = 0.5

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: notification.date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notification.id, content: content, trigger: trigger
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // One interpolation, not two joined with +: an os_log message is
            // a compile-time literal, and two of them cannot be added.
            let reason = String(describing: error)
            Self.logger.error(
                "Could not schedule \(notification.id, privacy: .public): \(reason, privacy: .public)"
            )
        }
    }
}

/// Keeps what the system has pending in step with what the learner asked for.
///
/// Every reconcile replaces the whole plan: whatever Elemora had scheduled is
/// removed and the current plan is added. That is what keeps fifty stale
/// reminders from accumulating — the identifiers are stable and derived from
/// the category and the day, so nothing is ever scheduled twice, and anything
/// no longer wanted is removed rather than left to fire.
@MainActor
@Observable
final class StudyNotificationScheduler {
    /// Everything Elemora schedules starts with this, so reconciling can
    /// remove its own requests and nothing else's.
    static let identifierPrefix = "elemora.study."
    /// When an inactivity reminder was last scheduled, so the week's silence
    /// after one survives the app being closed.
    static let lastInactivityKey = "notifications.lastInactivity"

    private(set) var preferences: NotificationPreferences
    private(set) var authorization: NotificationAuthorization = .notDetermined
    /// What is scheduled right now, for Settings to show.
    private(set) var scheduled: [PlannedNotification] = []

    @ObservationIgnored private let center: NotificationScheduling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    init(
        center: NotificationScheduling = SystemNotificationScheduler(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
        self.preferences = Self.load(from: defaults)
    }

    /// Whether the learner has been asked yet.
    var needsPermission: Bool { authorization == .notDetermined }
    /// Whether iOS is refusing, which Settings has to say out loud.
    var isBlockedBySystem: Bool { authorization == .denied }

    func refreshAuthorization() async {
        authorization = await center.authorization()
    }

    /// Turns notifications on, asking the system only now.
    ///
    /// The learner has already been told what the categories do and has
    /// chosen one; this is the moment the system prompt is right to show.
    @discardableResult
    func enable(state: StudyNotificationState) async -> NotificationAuthorization {
        authorization = await center.authorization()
        if authorization == .notDetermined {
            authorization = await center.requestAuthorization()
        }
        guard authorization == .authorized || authorization == .provisional else {
            // Refused. The preference stays off so the interface never shows
            // a switch that is on and doing nothing.
            update { $0.isEnabled = false }
            return authorization
        }
        update {
            $0.isEnabled = true
            if $0.enabledCategories.isEmpty {
                $0.enabledCategories = NotificationPreferences.defaultCategories
            }
        }
        await reconcile(state: state)
        return authorization
    }

    func disable() async {
        update { $0.isEnabled = false }
        await clearScheduled()
    }

    func setCategory(_ category: StudyNotificationCategory, enabled: Bool,
                     state: StudyNotificationState) async {
        update { $0 = $0.enabling(category, enabled) }
        await reconcile(state: state)
    }

    func setPreferredTime(hour: Int, minute: Int, state: StudyNotificationState) async {
        update {
            $0.preferredHour = hour
            $0.preferredMinute = minute
        }
        await reconcile(state: state)
    }

    /// Replaces the schedule with what the current state calls for.
    ///
    /// Called on every foreground and whenever progress changes. Cheap, and
    /// idempotent: the same state produces the same plan, and the same plan
    /// produces the same requests.
    func reconcile(state: StudyNotificationState, now: Date = Date()) async {
        authorization = await center.authorization()
        let plan = StudyNotificationPlanner.plan(
            preferences: preferences, authorization: authorization,
            state: state, now: now, calendar: calendar
        )
        await removeOurs()
        for notification in plan {
            await center.add(notification, calendar: calendar)
        }
        if let inactivity = plan.first(where: { $0.category == .inactivity }) {
            defaults.set(inactivity.date, forKey: Self.lastInactivityKey)
        }
        scheduled = plan
    }

    func clearScheduled() async {
        await removeOurs()
        scheduled = []
    }

    private func removeOurs() async {
        let ours = await center.pendingIdentifiers()
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        guard !ours.isEmpty else { return }
        await center.removePending(identifiers: ours)
    }

    // MARK: - Storage

    private func update(_ change: (inout NotificationPreferences) -> Void) {
        var copy = preferences
        change(&copy)
        preferences = copy
        if let data = try? JSONEncoder().encode(copy) {
            defaults.set(data, forKey: NotificationPreferences.storageKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> NotificationPreferences {
        guard let data = defaults.data(forKey: NotificationPreferences.storageKey),
              let decoded = try? JSONDecoder().decode(NotificationPreferences.self, from: data)
        else { return NotificationPreferences() }
        return decoded
    }
}

extension StudyNotificationState {
    /// Reads the learner's current state out of the stores.
    @MainActor
    static func current(
        progress: ProgressStore,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> StudyNotificationState {
        let dueElements = ReviewSchedule.dueElements(progress.snapshots, now: now).count
        let dueCompounds = ReviewSchedule.dueCompounds(progress.compoundSnapshots, now: now).count
        var daysSince: Int?
        if let last = progress.lastStudyDay {
            daysSince = calendar.dateComponents([.day], from: last, to: now).day
        }
        return StudyNotificationState(
            hasStudiedToday: progress.hasStudied(on: now),
            currentStreak: progress.currentStreak,
            dueReviewCount: dueElements + dueCompounds,
            daysSinceLastStudy: daysSince,
            hasCompletedDailyChallengeToday: DailyChallengeRecord.isComplete(
                on: now, calendar: calendar
            ),
            lastInactivityNotification: UserDefaults.standard.object(
                forKey: StudyNotificationScheduler.lastInactivityKey
            ) as? Date
        )
    }
}

/// A scheduler that talks to nothing.
///
/// Used by the UI tests, so a run can drive every switch in Settings without
/// the simulator asking for notification permission or being left with
/// requests pending afterwards.
struct InertNotificationScheduler: NotificationScheduling {
    func authorization() async -> NotificationAuthorization { .authorized }
    func requestAuthorization() async -> NotificationAuthorization { .authorized }
    func pendingIdentifiers() async -> [String] { [] }
    func removePending(identifiers: [String]) async {}
    func add(_ notification: PlannedNotification, calendar: Calendar) async {}
}
