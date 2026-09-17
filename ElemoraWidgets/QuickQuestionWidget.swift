import AppIntents
import SwiftUI
import WidgetKit

/// One question, four answers, answered on the Home Screen.
///
/// Medium and large only. A small widget has room for a prompt or for four
/// options, not both, and four-point touch targets crammed into a 155pt square
/// would be a quiz that is hard to answer for reasons that have nothing to do
/// with chemistry.
struct QuickQuestionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: ElemoraWidgetKind.quickQuestion,
            provider: ElemoraTimelineProvider()
        ) { entry in
            QuickQuestionView(entry: entry)
                .containerBackground(WidgetPalette.canvas, for: .widget)
        }
        .configurationDisplayName("Quick Question")
        .description("One chemistry question you can answer without opening Elemora.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct QuickQuestionView: View {
    let entry: ElemoraEntry

    var body: some View {
        if !entry.isSharedStorageAvailable {
            WidgetMessage(
                symbolName: "exclamationmark.triangle",
                title: "Widget storage unavailable",
                message: "Open Elemora once to set the widget up."
            )
        } else if let question = entry.revealed,
                  let choice = entry.state.revealedChoice,
                  let wasCorrect = entry.state.revealedWasCorrect {
            RevealView(question: question, choice: choice, wasCorrect: wasCorrect)
        } else if let question = entry.question {
            QuestionView(question: question)
        } else if entry.hasContent {
            WidgetMessage(
                symbolName: "checkmark.seal",
                title: "All caught up",
                message: "You have answered today's widget questions. More tomorrow."
            )
        } else {
            WidgetMessage(
                symbolName: "atom",
                title: "Nothing to ask yet",
                message: "Open Elemora once and the widget fills itself in."
            )
        }
    }
}

/// The question, with its four options as buttons.
private struct QuestionView: View {
    let question: WidgetQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.prompt)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(WidgetPalette.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            // Two by two. Four rows would give each option a 20pt strip on a
            // medium widget; two columns keeps every target tappable.
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(row, id: \.self) { index in
                            OptionButton(question: question, index: index)
                        }
                    }
                }
            }
        }
        .padding(2)
    }

    /// Indices in pairs, so a question with three options still lays out.
    private var rows: [[Int]] {
        stride(from: 0, to: question.options.count, by: 2).map { start in
            Array(start..<min(start + 2, question.options.count))
        }
    }
}

private struct OptionButton: View {
    let question: WidgetQuestion
    let index: Int

    var body: some View {
        Button(intent: AnswerWidgetQuestionIntent(questionID: question.id, choice: index)) {
            Text(question.options[index])
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(WidgetPalette.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(WidgetPalette.accent.opacity(0.12))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(question.options[index])
    }
}

/// Right or wrong, why, and a way on.
private struct RevealView: View {
    let question: WidgetQuestion
    let choice: Int
    let wasCorrect: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Symbol, color and the word, so none of the three is doing the
            // work alone.
            Label(
                wasCorrect ? "Correct" : "Not this time",
                systemImage: wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(wasCorrect ? WidgetPalette.correct : WidgetPalette.incorrect)

            if !wasCorrect {
                Text("The answer is \(question.correctAnswer).")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(WidgetPalette.primaryText)
                    .lineLimit(2)
            }

            if !question.detail.isEmpty {
                Text(question.detail)
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(intent: NextWidgetQuestionIntent()) {
                Text("Next question")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(WidgetPalette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(WidgetPalette.accent.opacity(0.12))
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(2)
        .accessibilityElement(children: .contain)
    }
}

/// The states that are a sentence rather than a question.
struct WidgetMessage: View {
    let symbolName: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(WidgetPalette.accent)
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(WidgetPalette.primaryText)
            Text(message)
                .font(.caption)
                .foregroundStyle(WidgetPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
