import SwiftUI

/// Hosts a single study round and owns the transition into the summary.
struct StudySessionContainer: View {
    let mode: StudyMode
    let queue: [ChemicalElement]
    let catalog: ElementCatalog

    @Environment(\.dismiss) private var dismiss
    @Environment(ProgressStore.self) private var progress: ProgressStore

    @State private var result: StudyResult?
    /// Bumped by "Study again" so a fresh round gets a fresh deck.
    @State private var round = 0

    private var seed: UInt64 {
        SeededGenerator.dailySeed() &+ UInt64(round) &* 7_919
    }

    /// Practice draws from the least-familiar elements first, but keeps a wide
    /// enough pool that a round is never the same ten tiles twice over.
    private var pool: [ChemicalElement] {
        Array(queue.prefix(40))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    SessionSummaryView(
                        result: result,
                        onRepeat: {
                            round += 1
                            self.result = nil
                        },
                        onDone: { dismiss() }
                    )
                } else if pool.isEmpty {
                    EmptyStateView(
                        symbolName: "tray",
                        title: "Nothing to study yet",
                        message: "Element data could not be loaded, so there is nothing to practice right now.",
                        actionTitle: "Close",
                        action: { dismiss() }
                    )
                } else {
                    session
                }
            }
            .background(AppColor.canvas)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Exit") { dismiss() }
                        .accessibilityIdentifier("session.exit")
                }
            }
        }
        .tint(AppColor.accent)
        .onAppear { Haptics.warmUp() }
    }

    @ViewBuilder
    private var session: some View {
        switch mode {
        case .flashcards:
            CardSessionView(
                mode: mode,
                cards: StudyDeckBuilder.flashcards(pool: pool, seed: seed),
                onAnswer: record,
                onFinish: { result = $0 }
            )
            .id(round)
        case .identify:
            CardSessionView(
                mode: mode,
                cards: StudyDeckBuilder.identifyCards(pool: pool, seed: seed),
                onAnswer: record,
                onFinish: { result = $0 }
            )
            .id(round)
        case .quiz:
            QuizSessionView(
                questions: QuizGenerator.makeQuiz(
                    pool: pool,
                    distractors: catalog.elements,
                    seed: seed
                ),
                onAnswer: record,
                onFinish: { result = $0 }
            )
            .id(round)
        }
    }

    private func record(atomicNumber: Int, correct: Bool) {
        progress.recordAnswer(atomicNumber: atomicNumber, correct: correct)
    }
}

// MARK: - Session chrome

/// Thin progress header shared by every mode.
struct SessionProgressHeader: View {
    let current: Int
    let total: Int

    private var fraction: Double {
        total == 0 ? 0 : Double(current) / Double(total)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack {
                Text("\(min(current + 1, total)) of \(total)")
                    .font(.system(.footnote, weight: .medium).monospacedDigit())
                    .foregroundStyle(AppColor.secondaryText)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(.footnote, weight: .medium).monospacedDigit())
                    .foregroundStyle(AppColor.secondaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.surfaceMuted)
                    Capsule()
                        .fill(AppColor.accent)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 8 : 0))
                }
            }
            .frame(height: 6)
            .animation(Theme.Motion.reveal, value: fraction)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, Theme.Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Question \(min(current + 1, total)) of \(total)")
    }
}

// MARK: - Flashcards & Identify

/// Flashcards and Identify share one screen: a clue, a reveal, and an honest
/// two-way self-rating.
struct CardSessionView: View {
    let mode: StudyMode
    let cards: [StudyCard]
    let onAnswer: (Int, Bool) -> Void
    let onFinish: (StudyResult) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    @State private var isRevealed = false
    @State private var correctCount = 0

    private var card: StudyCard? {
        index < cards.count ? cards[index] : nil
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            SessionProgressHeader(current: index, total: cards.count)

            if let card {
                // Scrollable rather than a fixed VStack: a long element name at
                // an accessibility text size makes the card taller than a small
                // phone, and clipped copy is never acceptable.
                ScrollView {
                    cardFace(card)
                        .id(card.id)
                        .transition(reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .opacity.combined(with: .offset(x: 40)),
                                        removal: .opacity.combined(with: .offset(x: -40))
                                      ))
                        .padding(.horizontal, Theme.Spacing.screenMargin)
                        .padding(.vertical, 2)
                }
                .scrollBounceBehavior(.basedOnSize)

                controls(for: card)
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.bottom, Theme.Spacing.l)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.reveal, value: index)
        .animation(reduceMotion ? nil : Theme.Motion.reveal, value: isRevealed)
        .accessibilityIdentifier("session.card")
    }

    private func cardFace(_ card: StudyCard) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            Text(mode == .identify ? "IDENTIFY ELEMENT" : "FLASHCARD")
                .font(.system(.caption2, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(AppColor.tertiaryText)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, 5)
                .background { Capsule().fill(AppColor.surfaceMuted) }

            Text(card.question)
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(AppColor.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            clueView(card)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 176)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(card.element.category.tileFill.opacity(isRevealed ? 0.9 : 0.55))
                }

            if isRevealed {
                VStack(spacing: 4) {
                    Text(card.answerTitle)
                        .font(.system(.largeTitle, weight: .bold))
                        .foregroundStyle(AppColor.primaryText)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(card.answerDetail)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .accessibilityIdentifier("session.answer")
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .fill(AppColor.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .strokeBorder(AppColor.hairline, lineWidth: 0.8)
        }
        .themeShadow(Theme.Shadow.card)
    }

    @ViewBuilder
    private func clueView(_ card: StudyCard) -> some View {
        switch card.clue {
        case .text(let text):
            Text(text)
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(card.element.category.onTileColor)
                .minimumScaleFactor(0.35)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(Theme.Spacing.l)
        case .structure:
            AtomicStructureView(element: card.element, diameter: 150)
                .padding(Theme.Spacing.m)
        case .description(let text):
            Text(text)
                .font(.system(.title3, weight: .medium))
                .foregroundStyle(AppColor.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Theme.Spacing.l)
        }
    }

    @ViewBuilder
    private func controls(for card: StudyCard) -> some View {
        if isRevealed {
            HStack(spacing: Theme.Spacing.m) {
                selfRatingButton(
                    title: "Review again",
                    symbol: "arrow.counterclockwise",
                    tint: AppColor.warning,
                    identifier: "session.reviewAgain"
                ) {
                    advance(card: card, correct: false)
                }
                selfRatingButton(
                    title: "I knew this",
                    symbol: "checkmark",
                    tint: AppColor.positive,
                    identifier: "session.knewThis"
                ) {
                    advance(card: card, correct: true)
                }
            }
        } else {
            Button {
                Haptics.reveal()
                isRevealed = true
            } label: {
                Text("Reveal Answer")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(AppColor.accent)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("session.reveal")
        }
    }

    private func selfRatingButton(
        title: String,
        symbol: String,
        tint: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(.footnote, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(tint.opacity(0.10))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func advance(card: StudyCard, correct: Bool) {
        if correct {
            correctCount += 1
            Haptics.correct()
        } else {
            Haptics.incorrect()
        }
        onAnswer(card.element.atomicNumber, correct)

        if index + 1 >= cards.count {
            Haptics.sessionComplete()
            onFinish(StudyResult(mode: mode, correct: correctCount, total: cards.count))
        } else {
            isRevealed = false
            index += 1
        }
    }
}

// MARK: - Quiz

/// Ten multiple-choice questions. Options lock once answered so the learner
/// sees which one was right before moving on.
struct QuizSessionView: View {
    let questions: [QuizQuestion]
    let onAnswer: (Int, Bool) -> Void
    let onFinish: (StudyResult) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    @State private var selection: Int?
    @State private var correctCount = 0

    private var question: QuizQuestion? {
        index < questions.count ? questions[index] : nil
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            SessionProgressHeader(current: index, total: questions.count)

            if let question {
                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        Text(question.prompt)
                            .font(.system(.title2, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Theme.Spacing.l)
                            .accessibilityIdentifier("quiz.prompt")

                        VStack(spacing: Theme.Spacing.s) {
                            ForEach(Array(question.options.indices), id: \.self) { offset in
                                optionButton(
                                    question: question,
                                    offset: offset,
                                    option: question.options[offset]
                                )
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.bottom, Theme.Spacing.l)
                    .id(question.id)
                }

                Button {
                    advanceToNextQuestion()
                } label: {
                    Text(index + 1 >= questions.count ? "See results" : "Next question")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(selection == nil ? AppColor.tertiaryText : AppColor.accent)
                        }
                }
                .buttonStyle(.plain)
                .disabled(selection == nil)
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.bottom, Theme.Spacing.l)
                .accessibilityIdentifier("quiz.next")
            } else {
                EmptyStateView(
                    symbolName: "questionmark.circle",
                    title: "No questions available",
                    message: "There are not enough elements loaded to build a quiz."
                )
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.soft, value: selection)
        .animation(reduceMotion ? nil : Theme.Motion.reveal, value: index)
    }

    private func optionButton(question: QuizQuestion, offset: Int, option: String) -> some View {
        let isChosen = selection == offset
        let isAnswer = question.isCorrect(offset)
        let resolved = selection != nil

        let tint: Color = {
            guard resolved else { return AppColor.hairline }
            if isAnswer { return AppColor.positive }
            return isChosen ? AppColor.warning : AppColor.hairline
        }()

        let fill: Color = {
            guard resolved else { return AppColor.surface }
            if isAnswer { return AppColor.positive.opacity(0.10) }
            return isChosen ? AppColor.warning.opacity(0.10) : AppColor.surface
        }()

        return Button {
            guard selection == nil else { return }
            selection = offset
            let correct = question.isCorrect(offset)
            if correct {
                correctCount += 1
                Haptics.correct()
            } else {
                Haptics.incorrect()
            }
            onAnswer(question.element.atomicNumber, correct)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Text(option)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if resolved, isAnswer {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.positive)
                } else if resolved, isChosen {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColor.warning)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 56)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(tint, lineWidth: resolved && (isAnswer || isChosen) ? 1.4 : 0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(resolved)
        .accessibilityIdentifier("quiz.option.\(offset)")
        .accessibilityAddTraits(resolved && isChosen ? [.isButton, .isSelected] : .isButton)
    }

    private func advanceToNextQuestion() {
        guard selection != nil else { return }
        if index + 1 >= questions.count {
            Haptics.sessionComplete()
            onFinish(StudyResult(mode: .quiz, correct: correctCount, total: questions.count))
        } else {
            selection = nil
            index += 1
        }
    }
}

// MARK: - Summary

/// End of a round: the score, and a calm, factual line about it.
struct SessionSummaryView: View {
    let result: StudyResult
    let onRepeat: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.xl)

            ProgressRing(
                progress: result.accuracy,
                lineWidth: 12,
                diameter: 156,
                tint: result.accuracy >= 0.8 ? AppColor.positive : AppColor.accent,
                centerTitle: "\(result.correct) / \(result.total)",
                centerCaption: "correct"
            )
            .accessibilityIdentifier("summary.ring")

            VStack(spacing: Theme.Spacing.s) {
                Text(result.headline)
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text(result.message)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.xl)

            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.s) {
                Button {
                    Haptics.tap()
                    onRepeat()
                } label: {
                    Text("Study again")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(AppColor.accent)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("summary.again")

                Button {
                    Haptics.tap()
                    onDone()
                } label: {
                    Text("Done")
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(AppColor.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("summary.done")
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, Theme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("session.summary")
    }
}
