import Foundation
import WidgetKit

/// Everything both widgets need to draw one moment.
struct ElemoraEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetProgressSnapshot
    let state: WidgetInteractionState
    /// True when the App Group is unavailable, which is the one case the
    /// widget explains rather than silently showing zeros.
    let isSharedStorageAvailable: Bool

    /// The question to ask, or nil when every question in the snapshot has
    /// been answered.
    var question: WidgetQuestion? { state.nextQuestion(in: snapshot) }

    /// The result being shown, if the learner has just answered.
    var revealed: WidgetQuestion? { state.revealedQuestion(in: snapshot) }

    var hasContent: Bool { !snapshot.questions.isEmpty }

    /// A widget shown before the app has ever run, or in the gallery.
    static func placeholder(date: Date = Date()) -> ElemoraEntry {
        ElemoraEntry(
            date: date,
            snapshot: WidgetProgressSnapshot(
                masteredElements: 24,
                totalElements: 118,
                currentStreak: 5,
                dueReviewCount: 7,
                rankTitle: "Pattern Reader",
                questions: [
                    WidgetQuestion(
                        id: "placeholder",
                        prompt: "Which element has the symbol Fe?",
                        options: ["Iron", "Fluorine", "Francium", "Fermium"],
                        correctIndex: 0,
                        subjectKey: "element-26",
                        detail: "Fe is from ferrum, the Latin for iron."
                    )
                ],
                updatedAt: date
            ),
            state: WidgetInteractionState(),
            isSharedStorageAvailable: true
        )
    }
}

/// Reads the shared container and hands the widget one entry.
///
/// There is no timeline in the usual sense. The content changes when the
/// learner taps something — which reloads the timeline from the intent — or
/// when the app republishes the snapshot, which reloads it from the app. A
/// refresh an hour out exists only so a widget on a device whose owner has not
/// opened the app in days still redraws its date-sensitive parts.
struct ElemoraTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ElemoraEntry {
        ElemoraEntry.placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (ElemoraEntry) -> Void) {
        // The gallery preview gets the sample rather than a learner's real
        // progress: an empty widget is a bad advertisement for the feature,
        // and a stranger looking at someone's phone is not owed their streak.
        completion(context.isPreview ? ElemoraEntry.placeholder() : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ElemoraEntry>) -> Void) {
        let entry = current()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func current(date: Date = Date()) -> ElemoraEntry {
        guard ElemoraAppGroup.isAvailable else {
            return ElemoraEntry(
                date: date,
                snapshot: WidgetProgressSnapshot(),
                state: WidgetInteractionState(),
                isSharedStorageAvailable: false
            )
        }
        return ElemoraEntry(
            date: date,
            snapshot: WidgetSnapshotStore().read() ?? WidgetProgressSnapshot(),
            state: WidgetStateStore().read(),
            isSharedStorageAvailable: true
        )
    }
}
