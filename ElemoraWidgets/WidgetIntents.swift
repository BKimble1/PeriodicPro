import AppIntents
import Foundation
import WidgetKit

/// Answering a question without leaving the Home Screen.
///
/// The intent does three things and nothing else: it decides whether the tap
/// was right, it records that in the widget's own state so the next redraw
/// shows the result, and it appends an event for the app to merge. It never
/// writes the learner's progress directly — the app owns that store, and two
/// processes writing it is how progress gets corrupted.
///
/// The event's identifier is generated here, at the tap. If iOS runs this
/// intent twice for one tap, both events carry the same question and the app's
/// ledger counts the second as already merged.
struct AnswerWidgetQuestionIntent: AppIntent {
    static var title: LocalizedStringResource = "Answer a question"
    static var description = IntentDescription(
        "Answers the question shown in the Elemora widget."
    )
    /// The Home Screen is the whole point; opening the app would defeat it.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Question")
    var questionID: String

    @Parameter(title: "Choice")
    var choice: Int

    init() {}

    init(questionID: String, choice: Int) {
        self.questionID = questionID
        self.choice = choice
    }

    func perform() async throws -> some IntentResult {
        let snapshot = WidgetSnapshotStore().read() ?? WidgetProgressSnapshot()
        guard let question = snapshot.questions.first(where: { $0.id == questionID }) else {
            return .result()
        }

        let stateStore = WidgetStateStore()
        var state = stateStore.read()
        // A question already answered is not answered again. Without this, a
        // stale widget snapshot still on screen in another slot could record a
        // second answer for the same question.
        guard !state.hasAnswered(question.id) else { return .result() }

        let isCorrect = question.isCorrect(choice)
        let now = Date()
        state.record(questionID: question.id, choice: choice, isCorrect: isCorrect, at: now)
        stateStore.write(state)

        WidgetEventLog().append(
            WidgetAnswerEvent(
                questionID: question.id,
                subjectKey: question.subjectKey,
                isCorrect: isCorrect,
                answeredAt: now
            )
        )

        WidgetCenter.shared.reloadTimelines(ofKind: ElemoraWidgetKind.quickQuestion)
        return .result()
    }
}

/// Moving on from the answer that is on screen.
///
/// A deliberate tap rather than a timer. A widget timeline cannot reliably
/// schedule an entry a few seconds out, and a result that vanished before it
/// was read would be worse than one that waits.
struct NextWidgetQuestionIntent: AppIntent {
    static var title: LocalizedStringResource = "Next question"
    static var description = IntentDescription("Shows the next Elemora question.")
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        let stateStore = WidgetStateStore()
        var state = stateStore.read()
        state.dismissReveal()
        stateStore.write(state)
        WidgetCenter.shared.reloadTimelines(ofKind: ElemoraWidgetKind.quickQuestion)
        return .result()
    }
}

/// The widget kinds, in one place so the intents and the widgets agree.
enum ElemoraWidgetKind {
    static let quickQuestion = "ElemoraQuickQuestion"
    static let progress = "ElemoraProgress"
}
