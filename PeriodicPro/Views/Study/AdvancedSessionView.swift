import SwiftUI

/// A round of advanced chemistry.
///
/// Some of these are picked and some are typed. A molar mass has no plausible
/// four-option form — the options would either give the answer away or be
/// arbitrary — so the learner works it out and enters it, on a number pad,
/// graded within a tolerance that follows the precision of the value rather
/// than a fixed number of decimal places.
///
/// And every question shows its working afterwards, right or wrong. Being
/// told only that 98.08 was wrong teaches nothing; being shown
/// 2(1.008) + 32.06 + 4(15.999) teaches the method.
struct AdvancedSessionView: View {
    let questions: [AdvancedQuestion]
    let onAnswer: (QuizSubject, Bool) -> Void
    let onFinish: (StudyResult) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTyping: Bool

    @State private var index = 0
    @State private var typed = ""
    @State private var selection: Int?
    @State private var outcome: Bool?
    @State private var correctCount = 0

    private var question: AdvancedQuestion? {
        index < questions.count ? questions[index] : nil
    }

    private var isResolved: Bool { outcome != nil }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            SessionProgressHeader(current: index, total: questions.count)

            if let question {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        Text(question.kind.title)
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColor.secondaryText)
                            .textCase(.uppercase)
                            .kerning(0.5)
                            .accessibilityIdentifier("advanced.kind")

                        Text(question.prompt)
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("advanced.prompt")

                        switch question.answer {
                        case .numeric(_, let unit, _):
                            numericEntry(unit: unit)
                        case .choice(let options, _):
                            choiceButtons(question: question, options: options)
                        }

                        if isResolved {
                            solutionCard(question)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.bottom, Theme.Spacing.xxxl)
                    .frame(maxWidth: Theme.readableWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)

                footer(question)
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.bottom, Theme.Spacing.m)
            }
        }
        .background(AppColor.canvas)
        .animation(reduceMotion ? nil : Theme.Motion.soft, value: index)
        .animation(reduceMotion ? nil : Theme.Motion.soft, value: outcome)
        .accessibilityIdentifier("advanced.session")
    }

    // MARK: - Answering

    private func numericEntry(unit: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                TextField("Your answer", text: $typed)
                    .keyboardType(.decimalPad)
                    .font(.system(.title3, weight: .semibold).monospacedDigit())
                    .focused($isTyping)
                    .disabled(isResolved)
                    .accessibilityIdentifier("advanced.answerField")
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(AppColor.secondaryText)
                        .accessibilityLabel("Units: \(unit)")
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(AppColor.surfaceMuted)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isResolved ? 1.4 : 0.7)
            }

            Text("Rounding the atomic weights is fine — answers within one percent are accepted.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isTyping = false }
                    .accessibilityIdentifier("advanced.keyboardDone")
            }
        }
    }

    private var borderColor: Color {
        guard let outcome else { return AppColor.hairline }
        return outcome ? AppColor.positive : AppColor.warning
    }

    private func choiceButtons(question: AdvancedQuestion, options: [String]) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(Array(options.indices), id: \.self) { offset in
                Button {
                    guard !isResolved else { return }
                    selection = offset
                    resolve(question, correct: question.answer.accepts(index: offset))
                } label: {
                    HStack {
                        Text(options[offset])
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(AppColor.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Theme.Spacing.s)
                        if isResolved, question.answer.accepts(index: offset) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppColor.positive)
                        } else if isResolved, selection == offset {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppColor.warning)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(minHeight: 52)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(AppColor.surface)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(optionBorder(question, offset: offset), lineWidth: 0.9)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isResolved)
                .accessibilityIdentifier("advanced.option.\(offset)")
            }
        }
    }

    private func optionBorder(_ question: AdvancedQuestion, offset: Int) -> Color {
        guard isResolved else { return AppColor.hairline }
        if question.answer.accepts(index: offset) { return AppColor.positive }
        if selection == offset { return AppColor.warning }
        return AppColor.hairline
    }

    // MARK: - The working

    private func solutionCard(_ question: AdvancedQuestion) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: (outcome ?? false) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle((outcome ?? false) ? AppColor.positive : AppColor.warning)
                    Text((outcome ?? false) ? "Correct" : "The answer is \(question.answer.correctText)")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("advanced.verdict")

                ForEach(Array(question.solution.enumerated()), id: \.offset) { _, step in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.label)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                        Text(step.expression)
                            .font(.system(.subheadline, weight: .medium).monospacedDigit())
                            .foregroundStyle(AppColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(question.sourceNote)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .accessibilityIdentifier("advanced.solution")
    }

    private func footer(_ question: AdvancedQuestion) -> some View {
        Button {
            if isResolved {
                advance()
            } else if question.isCalculation {
                isTyping = false
                resolve(question, correct: question.answer.accepts(typed))
            }
        } label: {
            Text(isResolved
                 ? (index + 1 < questions.count ? "Next" : "Finish")
                 : "Check answer")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(isEnabled(question) ? AppColor.accent : AppColor.accent.opacity(0.35))
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled(question))
        .accessibilityIdentifier("advanced.primaryButton")
    }

    private func isEnabled(_ question: AdvancedQuestion) -> Bool {
        if isResolved { return true }
        // A multiple-choice question is answered by tapping an option, so its
        // button does nothing until then.
        guard question.isCalculation else { return false }
        return AdvancedAnswer.parse(typed) != nil
    }

    private func resolve(_ question: AdvancedQuestion, correct: Bool) {
        outcome = correct
        if correct { correctCount += 1 }
        if correct { Haptics.correct() } else { Haptics.incorrect() }
        onAnswer(question.subject, correct)
    }

    private func advance() {
        guard index + 1 < questions.count else {
            onFinish(StudyResult(mode: .advanced, correct: correctCount, total: questions.count))
            return
        }
        index += 1
        typed = ""
        selection = nil
        outcome = nil
    }
}
