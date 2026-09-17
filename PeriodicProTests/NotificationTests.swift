import Foundation
import Testing
@testable import PeriodicPro

/// Every scheduling rule, asserted without a device, a clock or a
/// notification center — which is the whole reason the planner is a pure
/// function of three values.
@Suite("Study notifications")
struct StudyNotificationPlannerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// Nine in the morning, so the six-thirty default is still ahead.
    private var morning: Date {
        calendar.date(from: DateComponents(year: 2_026, month: 5, day: 12, hour: 9))!
    }

    private func preferences(
        enabled: Bool = true,
        categories: Set<StudyNotificationCategory> = Set(StudyNotificationCategory.allCases)
    ) -> NotificationPreferences {
        NotificationPreferences(
            isEnabled: enabled, enabledCategories: categories, preferredHour: 18, preferredMinute: 30
        )
    }

    private func plan(
        _ preferences: NotificationPreferences,
        _ state: StudyNotificationState,
        authorization: NotificationAuthorization = .authorized,
        now: Date? = nil
    ) -> [PlannedNotification] {
        StudyNotificationPlanner.plan(
            preferences: preferences, authorization: authorization,
            state: state, now: now ?? morning, calendar: calendar
        )
    }

    // MARK: - Permission and the master switch

    @Test("Without permission, nothing is ever scheduled")
    func noPermissionMeansNothing() {
        let state = StudyNotificationState(currentStreak: 9, dueReviewCount: 20)
        #expect(plan(preferences(), state, authorization: .notDetermined).isEmpty)
        #expect(plan(preferences(), state, authorization: .denied).isEmpty)
        // And with it, something is.
        #expect(!plan(preferences(), state, authorization: .authorized).isEmpty)
        #expect(!plan(preferences(), state, authorization: .provisional).isEmpty)
    }

    @Test("The master switch is the master switch")
    func masterSwitch() {
        let state = StudyNotificationState(currentStreak: 9, dueReviewCount: 20)
        #expect(plan(preferences(enabled: false), state).isEmpty)
        #expect(plan(preferences(categories: []), state).isEmpty)
    }

    @Test("Nothing is on until the learner turns it on")
    func defaultsAreOff() {
        let fresh = NotificationPreferences()
        #expect(!fresh.isEnabled)
        #expect(fresh.enabledCategories.isEmpty)
        #expect(plan(fresh, StudyNotificationState(dueReviewCount: 40)).isEmpty)
        // And turning the master switch on does not turn all five on.
        #expect(NotificationPreferences.defaultCategories.count < StudyNotificationCategory.allCases.count)
        #expect(!NotificationPreferences.defaultCategories.contains(.inactivity))
    }

    // MARK: - The rules

    @Test("Having studied today means nothing is waiting, so nothing is sent")
    func studiedTodaySilencesToday() {
        let state = StudyNotificationState(
            hasStudiedToday: true, currentStreak: 9, dueReviewCount: 30, daysSinceLastStudy: 0
        )
        let planned = plan(preferences(), state)
        let today = calendar.startOfDay(for: morning)
        #expect(!planned.contains { calendar.isDate($0.date, inSameDayAs: today) },
                "a learner who already studied is not reminded to")
        // Tomorrow, when they have not, is a different question.
        #expect(!planned.isEmpty)
    }

    @Test("A streak reminder needs a streak")
    func streakNeedsAStreak() {
        let withStreak = StudyNotificationState(currentStreak: 12)
        let without = StudyNotificationState(currentStreak: 0)
        #expect(StudyNotificationPlanner.applies(.streak, state: withStreak, now: morning, calendar: calendar))
        #expect(!StudyNotificationPlanner.applies(.streak, state: without, now: morning, calendar: calendar),
                "a learner with no streak is not told they are about to lose one")
        // And it says the streak is open rather than threatening them.
        let text = StudyNotificationPlanner.title(for: .streak, state: withStreak)
            + " " + StudyNotificationPlanner.body(for: .streak, state: withStreak)
        #expect(text.contains("12-day streak is still open"))
        for word in ["lose", "lost", "don't", "about to end", "breaking", "fail"] {
            #expect(!text.lowercased().contains(word), "the wording should not use guilt: \(text)")
        }
    }

    @Test("Inactivity waits three days, then a week")
    func inactivityRateLimit() {
        var state = StudyNotificationState(daysSinceLastStudy: 2)
        #expect(!StudyNotificationPlanner.applies(.inactivity, state: state, now: morning, calendar: calendar))
        state.daysSinceLastStudy = 3
        #expect(StudyNotificationPlanner.applies(.inactivity, state: state, now: morning, calendar: calendar))

        // Sent one yesterday: not another today.
        state.lastInactivityNotification = calendar.date(byAdding: .day, value: -1, to: morning)
        #expect(!StudyNotificationPlanner.applies(.inactivity, state: state, now: morning, calendar: calendar),
                "one inactivity reminder, then silence — not one a day forever")
        // A week later, one more.
        state.lastInactivityNotification = calendar.date(byAdding: .day, value: -8, to: morning)
        #expect(StudyNotificationPlanner.applies(.inactivity, state: state, now: morning, calendar: calendar))
        #expect(StudyNotificationPlanner.inactivityCooldownInDays >= 7)
    }

    @Test("A daily challenge already done is not announced")
    func challengeDone() {
        let done = StudyNotificationState(hasCompletedDailyChallengeToday: true)
        #expect(!StudyNotificationPlanner.applies(.dailyChallenge, state: done,
                                                  now: morning, calendar: calendar))
        let notDone = StudyNotificationState()
        #expect(StudyNotificationPlanner.applies(.dailyChallenge, state: notDone,
                                                 now: morning, calendar: calendar))
    }

    @Test("Review due needs something due")
    func reviewNeedsReview() {
        #expect(!StudyNotificationPlanner.applies(
            .reviewDue, state: StudyNotificationState(dueReviewCount: 0),
            now: morning, calendar: calendar
        ))
        #expect(StudyNotificationPlanner.applies(
            .reviewDue, state: StudyNotificationState(dueReviewCount: 1),
            now: morning, calendar: calendar
        ))
    }

    // MARK: - One a day, and which one

    @Test("At most one a day, whatever else applies")
    func oneADay() {
        // Everything at once: a streak, a pile of review, an unfinished
        // challenge, and eight quiet days.
        let state = StudyNotificationState(
            hasStudiedToday: false, currentStreak: 9, dueReviewCount: 40,
            daysSinceLastStudy: 8, hasCompletedDailyChallengeToday: false
        )
        let planned = plan(preferences(), state)
        let byDay = Dictionary(grouping: planned) {
            StreakCalculator.dayKey(for: $0.date, calendar: calendar)
        }
        for (day, sent) in byDay {
            #expect(sent.count <= StudyNotificationPlanner.maximumPerDay,
                    "\(sent.count) notifications planned for \(day)")
        }
        #expect(StudyNotificationPlanner.maximumPerDay == 1)
    }

    @Test("When several apply, the most useful one is the one that goes")
    func priorityOrder() {
        let everything = StudyNotificationState(
            currentStreak: 9, dueReviewCount: 40, daysSinceLastStudy: 8
        )
        let chosen = StudyNotificationPlanner.chosenCategory(
            preferences: preferences(), state: everything, now: morning, calendar: calendar
        )
        #expect(chosen == .streak, "a streak about to lapse outranks everything else")

        // Without a streak, the overdue review is next.
        var noStreak = everything
        noStreak.currentStreak = 0
        #expect(StudyNotificationPlanner.chosenCategory(
            preferences: preferences(), state: noStreak, now: morning, calendar: calendar
        ) == .reviewDue)

        // Then the challenge, then the plain reminder, then inactivity last.
        var quiet = noStreak
        quiet.dueReviewCount = 0
        #expect(StudyNotificationPlanner.chosenCategory(
            preferences: preferences(), state: quiet, now: morning, calendar: calendar
        ) == .dailyChallenge)

        var onlyInactivity = quiet
        onlyInactivity.hasCompletedDailyChallengeToday = true
        #expect(StudyNotificationPlanner.chosenCategory(
            preferences: preferences(categories: [.inactivity, .studyReminder]),
            state: onlyInactivity, now: morning, calendar: calendar
        ) == .studyReminder)
        #expect(StudyNotificationPlanner.chosenCategory(
            preferences: preferences(categories: [.inactivity]),
            state: onlyInactivity, now: morning, calendar: calendar
        ) == .inactivity)
    }

    @Test("A category that is off is never chosen, however much it applies")
    func disabledCategoriesAreNeverChosen() {
        let state = StudyNotificationState(currentStreak: 9, dueReviewCount: 40, daysSinceLastStudy: 8)
        let onlyChallenge = preferences(categories: [.dailyChallenge])
        #expect(StudyNotificationPlanner.chosenCategory(
            preferences: onlyChallenge, state: state, now: morning, calendar: calendar
        ) == .dailyChallenge)
        #expect(plan(onlyChallenge, state).allSatisfy { $0.category == .dailyChallenge })
    }

    // MARK: - Times and identifiers

    @Test("Notifications land at the chosen time, and never in the past")
    func timing() {
        let planned = plan(preferences(), StudyNotificationState(dueReviewCount: 5))
        #expect(!planned.isEmpty)
        for notification in planned {
            #expect(notification.date > morning, "nothing may be scheduled in the past")
            let parts = calendar.dateComponents([.hour, .minute], from: notification.date)
            #expect(parts.hour == 18)
            #expect(parts.minute == 30)
        }
        // A preferred time already past today starts tomorrow instead.
        let evening = calendar.date(
            from: DateComponents(year: 2_026, month: 5, day: 12, hour: 22)
        )!
        let later = plan(preferences(), StudyNotificationState(dueReviewCount: 5), now: evening)
        #expect(later.allSatisfy { $0.date > evening })
        #expect(!later.contains { calendar.isDate($0.date, inSameDayAs: evening) })
    }

    @Test("Identifiers are stable, so replanning replaces rather than piles up")
    func identifiersAreStable() {
        let state = StudyNotificationState(dueReviewCount: 5)
        let first = plan(preferences(), state)
        let again = plan(preferences(), state)
        #expect(first.map(\.id) == again.map(\.id))
        #expect(Set(first.map(\.id)).count == first.count, "two requests must never share an identifier")
        for notification in first {
            #expect(notification.id.hasPrefix(StudyNotificationScheduler.identifierPrefix),
                    "every request must be recognizable as Elemora's own, to be removable")
        }
    }

    @Test("The horizon is short, because a plan is made from today's state")
    func horizonIsShort() {
        let planned = plan(preferences(), StudyNotificationState(dueReviewCount: 5))
        #expect(planned.count <= StudyNotificationPlanner.horizonInDays + 1)
        #expect(StudyNotificationPlanner.horizonInDays <= 7)
        for notification in planned {
            let days = calendar.dateComponents([.day], from: morning, to: notification.date).day ?? 0
            #expect(days <= StudyNotificationPlanner.horizonInDays)
        }
    }

    @Test("Every notification says where it goes, and every destination is a tab")
    func destinations() {
        #expect(StudyNotificationCategory.reviewDue.destination == .smartReview)
        #expect(StudyNotificationCategory.dailyChallenge.destination == .dailyChallenge)
        #expect(StudyNotificationCategory.streak.destination == .study)
        #expect(NotificationDestination.smartReview.tab == .study)
        #expect(NotificationDestination.progress.tab == .progress)
        // And it round-trips through the userInfo the system carries.
        for destination in [NotificationDestination.study, .smartReview, .dailyChallenge, .progress] {
            #expect(NotificationDestination(userInfo: destination.userInfo) == destination)
        }
        #expect(NotificationDestination(userInfo: ["something": "else"]) == nil)
    }

    @Test("The review estimate is a plain number of minutes")
    func minuteEstimates() {
        #expect(StudyNotificationPlanner.estimatedMinutes(0) == 1)
        #expect(StudyNotificationPlanner.estimatedMinutes(8) == 1)
        #expect(StudyNotificationPlanner.estimatedMinutes(30) == 3)
        #expect(StudyNotificationPlanner.estimatedMinutes(100) == 10)
    }
}

/// The scheduler keeps the system in step with the plan and never leaves
/// stale requests behind.
@MainActor
@Suite("Reconciling what is scheduled")
struct StudyNotificationSchedulerTests {
    /// A notification center that records what it was asked to do.
    final class RecordingCenter: NotificationScheduling, @unchecked Sendable {
        var authorized: NotificationAuthorization
        var pending: [String] = []
        var added: [PlannedNotification] = []
        var removed: [String] = []
        var requestCount = 0

        init(authorized: NotificationAuthorization = .authorized) {
            self.authorized = authorized
        }

        func authorization() async -> NotificationAuthorization { authorized }

        func requestAuthorization() async -> NotificationAuthorization {
            requestCount += 1
            if authorized == .notDetermined { authorized = .authorized }
            return authorized
        }

        func pendingIdentifiers() async -> [String] { pending }

        func removePending(identifiers: [String]) async {
            removed.append(contentsOf: identifiers)
            pending.removeAll { identifiers.contains($0) }
        }

        func add(_ notification: PlannedNotification, calendar: Calendar) async {
            added.append(notification)
            pending.append(notification.id)
        }
    }

    private func makeScheduler(_ center: RecordingCenter) -> StudyNotificationScheduler {
        let defaults = UserDefaults(suiteName: "NotificationTests-\(UUID().uuidString)") ?? .standard
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return StudyNotificationScheduler(center: center, defaults: defaults, calendar: calendar)
    }

    @Test("Permission is asked for only when the learner turns it on")
    func permissionIsAskedInContext() async {
        let center = RecordingCenter(authorized: .notDetermined)
        let scheduler = makeScheduler(center)

        await scheduler.refreshAuthorization()
        #expect(center.requestCount == 0, "merely looking at Settings must not prompt")
        #expect(!scheduler.preferences.isEnabled)

        await scheduler.enable(state: StudyNotificationState(dueReviewCount: 4))
        #expect(center.requestCount == 1)
        #expect(scheduler.preferences.isEnabled)
        #expect(!scheduler.preferences.enabledCategories.isEmpty)
    }

    @Test("Refusing leaves the switch off rather than on and silent")
    func refusalIsHonest() async {
        let center = RecordingCenter(authorized: .denied)
        let scheduler = makeScheduler(center)
        await scheduler.enable(state: StudyNotificationState(dueReviewCount: 4))
        #expect(!scheduler.preferences.isEnabled)
        #expect(scheduler.isBlockedBySystem)
        #expect(center.added.isEmpty)
    }

    @Test("Reconciling twice does not schedule twice")
    func reconcilingIsIdempotent() async {
        let center = RecordingCenter()
        let scheduler = makeScheduler(center)
        let state = StudyNotificationState(currentStreak: 3, dueReviewCount: 6)

        await scheduler.enable(state: state)
        let first = center.pending
        #expect(!first.isEmpty)

        await scheduler.reconcile(state: state)
        #expect(Set(center.pending).count == center.pending.count,
                "the same plan must not leave two requests per day")
        #expect(!center.removed.isEmpty, "the previous plan should have been removed first")
    }

    @Test("Turning it off removes everything Elemora had pending")
    func disablingClears() async {
        let center = RecordingCenter()
        let scheduler = makeScheduler(center)
        await scheduler.enable(state: StudyNotificationState(dueReviewCount: 6))
        #expect(!center.pending.isEmpty)

        await scheduler.disable()
        #expect(center.pending.isEmpty)
        #expect(scheduler.scheduled.isEmpty)
        #expect(!scheduler.preferences.isEnabled)
    }

    @Test("Only Elemora's own requests are removed")
    func othersAreLeftAlone() async {
        let center = RecordingCenter()
        center.pending = ["someone.elses.request", "another.app.reminder"]
        let scheduler = makeScheduler(center)
        await scheduler.enable(state: StudyNotificationState(dueReviewCount: 6))
        await scheduler.disable()
        #expect(center.pending == ["someone.elses.request", "another.app.reminder"],
                "reconciling must only touch requests this app made")
    }

    @Test("Preferences survive being written and read back")
    func preferencesPersist() async {
        let center = RecordingCenter()
        let defaults = UserDefaults(suiteName: "NotificationTests-\(UUID().uuidString)") ?? .standard
        let scheduler = StudyNotificationScheduler(center: center, defaults: defaults)
        await scheduler.enable(state: StudyNotificationState(dueReviewCount: 3))
        await scheduler.setCategory(.dailyChallenge, enabled: true,
                                    state: StudyNotificationState(dueReviewCount: 3))
        await scheduler.setPreferredTime(hour: 7, minute: 15,
                                         state: StudyNotificationState(dueReviewCount: 3))

        let reloaded = StudyNotificationScheduler(center: center, defaults: defaults)
        #expect(reloaded.preferences.isEnabled)
        #expect(reloaded.preferences.enabledCategories.contains(.dailyChallenge))
        #expect(reloaded.preferences.preferredHour == 7)
        #expect(reloaded.preferences.preferredMinute == 15)
    }
}
