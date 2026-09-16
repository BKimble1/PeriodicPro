import SwiftUI

/// Match: prompts on the left, answers on the right, pair them up.
///
/// A pair matched at the first attempt counts as known; a pair the learner
/// missed on the way counts as a miss for that element or compound. Every
/// card is a plain button with a spoken label, selection shows as a border
/// and a mark rather than color alone, and there is no timer to beat — the
/// round ends when every pair is matched.
struct MatchSessionView: View {
    let round: MatchRound
    let onAnswer: (QuizSubject, Bool) -> Void
    let onFinish: (StudyResult) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedPrompt: Int?
    @State private var selectedAnswer: Int?
    @State private var matched: Set<Int> = []
    /// Pairs that were mismatched at least once.
    @State private var missed: Set<Int> = []
    /// The pair id whose two cards are flashing as a wrong guess.
    @State private var wrongFlash: (prompt: Int, answer: Int)?
    @State private var hasFinished = false

    private var isComplete: Bool { matched.count == round.pairs.count && !round.pairs.isEmpty }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            SessionProgressHeader(current: matched.count, total: round.pairs.count)

            if round.pairs.isEmpty {
                ScrollView {
                    EmptyStateView(
                        symbolName: "tray",
                        title: "Nothing to match yet",
                        message: "This selection has fewer than two things to pair."
                    )
                }
                .scrollIndicators(.hidden)
            } else {
                Text(instruction)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .accessibilityIdentifier("match.instruction")

                ScrollView {
                    columns
                        .padding(.horizontal, Theme.Spacing.screenMargin)
                        .padding(.bottom, Theme.Spacing.l)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.soft, value: matched)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("match.board")
    }

    private var instruction: String {
        if selectedPrompt != nil { return "Now tap its match on the right." }
        if selectedAnswer != nil { return "Now tap what it belongs to on the left." }
        return "Tap a name, then the symbol or formula that goes with it."
    }

    /// Two columns normally; at accessibility sizes the answers follow the
    /// prompts in one column so nothing is squeezed to a sliver.
    @ViewBuilder
    private var columns: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(round.promptOrder, id: \.self) { id in promptCard(id) }
                Divider().overlay(AppColor.hairline).padding(.vertical, Theme.Spacing.s)
                ForEach(round.answerOrder, id: \.self) { id in answerCard(id) }
            }
        } else {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(round.promptOrder, id: \.self) { id in promptCard(id) }
                }
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(round.answerOrder, id: \.self) { id in answerCard(id) }
                }
            }
        }
    }

    private func promptCard(_ id: Int) -> some View {
        card(
            text: round.pair(id: id)?.prompt ?? "",
            spokenRole: "name",
            isSelected: selectedPrompt == id,
            isMatched: matched.contains(id),
            isWrong: wrongFlash?.prompt == id,
            identifier: "match.prompt.\(id)"
        ) {
            choosePrompt(id)
        }
    }

    private func answerCard(_ id: Int) -> some View {
        card(
            text: round.pair(id: id)?.answer ?? "",
            spokenRole: "answer",
            isSelected: selectedAnswer == id,
            isMatched: matched.contains(id),
            isWrong: wrongFlash?.answer == id,
            identifier: "match.answer.\(id)"
        ) {
            chooseAnswer(id)
        }
    }

    private func card(
        text: String,
        spokenRole: String,
        isSelected: Bool,
        isMatched: Bool,
        isWrong: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        let tint: Color = isMatched ? AppColor.positive : (isWrong ? AppColor.warning : AppColor.accent)
        return Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Text(text)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(isMatched ? AppColor.tertiaryText : AppColor.primaryText)
                    .strikethrough(isMatched, color: AppColor.tertiaryText)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isMatched {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColor.positive)
                } else if isWrong {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppColor.warning)
                } else if isSelected {
                    Image(systemName: "circle.fill").font(.system(size: 9)).foregroundStyle(AppColor.accent)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 56)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isSelected || isWrong ? tint.opacity(0.10) : AppColor.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(isSelected || isWrong || isMatched ? tint : AppColor.hairline,
                                  lineWidth: isSelected || isWrong ? 1.6 : 0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMatched)
        .accessibilityLabel(isMatched ? "\(text), matched" : "\(spokenRole) \(text)")
        .accessibilityHint(isMatched ? "" : "Double tap to select, then choose its match")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Selection

    private func choosePrompt(_ id: Int) {
        guard !matched.contains(id) else { return }
        Haptics.tap()
        selectedPrompt = selectedPrompt == id ? nil : id
        wrongFlash = nil
        resolveIfPaired()
    }

    private func chooseAnswer(_ id: Int) {
        guard !matched.contains(id) else { return }
        Haptics.tap()
        selectedAnswer = selectedAnswer == id ? nil : id
        wrongFlash = nil
        resolveIfPaired()
    }

    private func resolveIfPaired() {
        guard let prompt = selectedPrompt, let answer = selectedAnswer else { return }
        selectedPrompt = nil
        selectedAnswer = nil
        if prompt == answer {
            Haptics.correct()
            matched.insert(prompt)
            if let pair = round.pair(id: prompt) {
                onAnswer(pair.subject, !missed.contains(prompt))
            }
            if isComplete, !hasFinished {
                hasFinished = true
                Haptics.sessionComplete()
                let firstTry = round.pairs.count - missed.count
                onFinish(StudyResult(mode: .match, correct: max(0, firstTry), total: round.pairs.count))
            }
        } else {
            Haptics.incorrect()
            missed.insert(prompt)
            missed.insert(answer)
            wrongFlash = (prompt, answer)
        }
    }
}
