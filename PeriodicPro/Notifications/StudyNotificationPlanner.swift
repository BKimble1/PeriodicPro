import Foundation

/// Decides what, if anything, to send — and mostly decides to send nothing.
///
/// The whole rule set is a pure function of preferences, state and a clock, so
/// every claim about it is a test rather than something to be discovered by a
/// learner three weeks after release.
///
/// The rules, in order:
///
/// * Nothing is scheduled without permission, and nothing is scheduled with
///   the master switch off.
/// * **At most one** proactive notification a day. When several categories
///   apply, the most useful one is sent and the rest are not — a streak about
///   to lapse and a pile of overdue review are worth knowing about, a generic
///   reminder is what gets dropped.
/// * A streak reminder only while a streak is actually running and the learner
///   has not studied today. It says the streak is open; it does not threaten
///   them with losing it.
/// * An inactivity reminder only after three quiet days, and then at most
///   once a week — not once a day forever.
/// * Nothing is ever sent at a critical or time-sensitive interruption level.
///   This is a chemistry app; there is no emergency here, and the system's
///   ordinary delivery respects the learner's Focus.
enum StudyNotificationPlanner {
    /// How many days ahead to schedule.
    ///
    /// Three. Far enough that closing the app on Friday still produces a
    /// reminder on Saturday, near enough that a plan made from today's state
    /// is not still being acted on next week. Every foreground reconciles it.
    static let horizonInDays = 3

    /// Quiet days before an inactivity reminder.
    static let inactivityThresholdInDays = 3
    /// And how long before another one.
    static let inactivityCooldownInDays = 7

    /// At most one proactive learning notification a day.
    static let maximumPerDay = 1

    static func plan(
        preferences: NotificationPreferences,
        authorization: NotificationAuthorization,
        state: StudyNotificationState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        guard authorization == .authorized || authorization == .provisional else { return [] }
        guard preferences.isEnabled, !preferences.enabledCategories.isEmpty else { return [] }

        var planned: [PlannedNotification] = []
        for offset in 0...horizonInDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fireDate = preferences.time(on: day, calendar: calendar),
                  fireDate > now else { continue }

            // Today's state is known; a future day's is projected from it —
            // which is why the horizon is short and every foreground replans.
            let projected = project(state, daysAhead: offset)
            guard let category = chosenCategory(
                preferences: preferences, state: projected, now: fireDate, calendar: calendar
            ) else { continue }

            let dayKey = StreakCalculator.dayKey(for: day, calendar: calendar)
            planned.append(PlannedNotification(
                id: PlannedNotification.identifier(category, dayKey: dayKey),
                category: category,
                title: title(for: category, state: projected),
                body: body(for: category, state: projected),
                date: fireDate
            ))
            if planned.count >= horizonInDays + 1 { break }
        }
        return planned
    }

    /// What the learner's state will look like in `daysAhead` days if they do
    /// nothing in between.
    ///
    /// Deliberately pessimistic about them and optimistic about nothing: a day
    /// that has not happened has not been studied, and review only piles up.
    static func project(_ state: StudyNotificationState, daysAhead: Int) -> StudyNotificationState {
        guard daysAhead > 0 else { return state }
        var projected = state
        projected.hasStudiedToday = false
        projected.hasCompletedDailyChallengeToday = false
        if let since = state.daysSinceLastStudy {
            projected.daysSinceLastStudy = since + daysAhead
        } else if state.hasStudiedToday {
            projected.daysSinceLastStudy = daysAhead
        }
        return projected
    }

    /// The one category worth sending on a day, or none.
    static func chosenCategory(
        preferences: NotificationPreferences,
        state: StudyNotificationState,
        now: Date,
        calendar: Calendar = .current
    ) -> StudyNotificationCategory? {
        // Already studied today: nothing is waiting, so nothing is sent.
        guard !state.hasStudiedToday else { return nil }

        var eligible: [StudyNotificationCategory] = []
        for category in StudyNotificationCategory.allCases
        where preferences.enabledCategories.contains(category) {
            if applies(category, state: state, now: now, calendar: calendar) {
                eligible.append(category)
            }
        }
        // One a day. When several apply, the most useful one goes.
        return eligible.min { $0.priority < $1.priority }
    }

    static func applies(
        _ category: StudyNotificationCategory,
        state: StudyNotificationState,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        switch category {
        case .reviewDue:
            return state.dueReviewCount > 0
        case .dailyChallenge:
            return !state.hasCompletedDailyChallengeToday
        case .streak:
            // Only while there is a streak to keep. A learner with no streak
            // is not told they are about to lose one.
            return state.currentStreak > 0 && !state.hasStudiedToday
        case .inactivity:
            guard let days = state.daysSinceLastStudy, days >= inactivityThresholdInDays else {
                return false
            }
            guard let last = state.lastInactivityNotification else { return true }
            // One, then a week's silence. Not one a day forever.
            let elapsed = calendar.dateComponents([.day], from: last, to: now).day ?? 0
            return elapsed >= inactivityCooldownInDays
        case .studyReminder:
            return true
        }
    }

    // MARK: - Wording

    /// Plain, factual, and never guilt.
    static func title(for category: StudyNotificationCategory, state: StudyNotificationState) -> String {
        switch category {
        case .reviewDue:
            return state.dueReviewCount == 1
                ? "1 item is ready for review"
                : "\(state.dueReviewCount) items are ready for review"
        case .dailyChallenge:
            return "Today's Daily Challenge is ready"
        case .streak:
            return "Your \(state.currentStreak)-day streak is still open"
        case .inactivity:
            return "Ready for a quick review?"
        case .studyReminder:
            return "Time to study"
        }
    }

    static func body(for category: StudyNotificationCategory, state: StudyNotificationState) -> String {
        switch category {
        case .reviewDue:
            return "About \(estimatedMinutes(state.dueReviewCount)) minutes."
        case .dailyChallenge:
            return "\(DailyChallenge.questionCount) questions, chosen for where you are."
        case .streak:
            // States the fact. Does not threaten, does not count down, and
            // does not say what happens if they do not.
            return "A short round keeps it going."
        case .inactivity:
            return state.dueReviewCount > 0
                ? "\(state.dueReviewCount) items are waiting whenever you have a moment."
                : "A few minutes is enough to pick up where you left off."
        case .studyReminder:
            return "A short round is enough."
        }
    }

    /// Roughly six seconds an item, rounded up, floored at one.
    static func estimatedMinutes(_ items: Int) -> Int {
        max(1, Int((Double(items) * 6 / 60).rounded(.up)))
    }
}
