import SwiftUI

/// Hosts a single study round and owns the transition into the summary.
struct StudySessionContainer: View {
    let plan: StudyRoundPlan
    let catalog: ElementCatalog
    /// Called when a round finishes and the learner has no free rounds left.
    /// The caller presents the paywall once this cover has gone — never over a
    /// round, which would discard the learner's position.
    var onAllowanceSpent: () -> Void = {}
    /// Called when a round is actually finished — the last card rated, the
    /// last question confirmed, the last pair matched. Never on dismissal.
    var onRoundFinished: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(SubscriptionManager.self) private var store: SubscriptionManager

    @State private var result: StudyResult?
    /// Bumped by "Study again" so a fresh round gets a fresh deck.
    @State private var round = 0
    /// The seed for the round in progress.
    ///
    /// Snapshotted once per round. Every session gets a fresh, UUID-derived
    /// seed, so two rounds never deal the same order — and a test can inject
    /// one, in which case the round is exactly reproducible.
    @State private var roundSeed: UInt64
    /// The deck, dealt once when the round starts and never reshuffled while
    /// it is on screen.
    @State private var questions: [QuizQuestion]
    @State private var matchRound: MatchRound?
    @State private var advancedQuestions: [AdvancedQuestion]

    private var mode: StudyMode { plan.mode }

    /// Practice draws from the least-familiar elements first, but keeps a wide
    /// enough pool that a round is never the same ten tiles twice over.
    ///
    /// Derived, not stored. It used to be `@State` seeded with
    /// `State(initialValue:)` from the queue, which takes effect only the first
    /// time this view's identity appears — so whichever value the very first
    /// construction happened to see was the deck for good. Deriving it is safe
    /// because the queue is captured once when the round starts and never
    /// written again while the round is on screen.
    private var pool: [ChemicalElement] {
        guard case .cards(_, let queue) = plan else { return [] }
        return Array(queue.prefix(StudyDeckBuilder.defaultPoolSize))
    }

    private var isEmpty: Bool {
        switch plan {
        case .cards: return pool.isEmpty
        case .quiz: return questions.isEmpty
        case .match: return matchRound?.pairs.isEmpty ?? true
        case .advanced: return advancedQuestions.isEmpty
        }
    }

    init(
        plan: StudyRoundPlan,
        catalog: ElementCatalog,
        seed: UInt64? = nil,
        onAllowanceSpent: @escaping () -> Void = {},
        onRoundFinished: @escaping () -> Void = {}
    ) {
        self.plan = plan
        self.catalog = catalog
        self.onAllowanceSpent = onAllowanceSpent
        self.onRoundFinished = onRoundFinished
        let initialSeed = seed ?? QuizSeed.fresh()
        _roundSeed = State(initialValue: initialSeed)
        switch plan {
        case .quiz(let dealer):
            _questions = State(initialValue: dealer.questions(seed: initialSeed))
            _matchRound = State(initialValue: nil)
            _advancedQuestions = State(initialValue: [])
        case .match(let dealer):
            _questions = State(initialValue: [])
            _matchRound = State(initialValue: dealer.matchRound(seed: initialSeed))
            _advancedQuestions = State(initialValue: [])
        case .advanced(let dealer):
            _questions = State(initialValue: [])
            _matchRound = State(initialValue: nil)
            _advancedQuestions = State(initialValue: dealer.questions(seed: initialSeed))
        case .cards:
            _questions = State(initialValue: [])
            _matchRound = State(initialValue: nil)
            _advancedQuestions = State(initialValue: [])
        }
    }

    private var seed: UInt64 { roundSeed &+ mode.seedSalt }

    /// Whether another round may start straight away from the summary.
    private var canStudyAgain: Bool {
        DailyStudyLimiter.canStartRound(
            completedToday: progress.completedRoundsToday,
            isPro: store.isPro
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    SessionSummaryView(
                        result: result,
                        canStudyAgain: canStudyAgain,
                        onRepeat: dealAgain,
                        onUnlock: {
                            onAllowanceSpent()
                            dismiss()
                        },
                        onDone: { dismiss() }
                    )
                } else if isEmpty {
                    ScrollView {
                        EmptyStateView(
                            symbolName: "tray",
                            title: "Nothing to study yet",
                            message: "There is not enough material for this round right now.",
                            actionTitle: "Close",
                            action: { dismiss() }
                        )
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
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
        switch plan {
        // Smart Review is the flashcard format over a pool of the elements the
        // learner keeps missing — the pool is what makes it different, and it
        // was already chosen before this view was presented.
        case .cards(let mode, _) where mode == .identify:
            CardSessionView(
                mode: mode,
                cards: StudyDeckBuilder.identifyCards(pool: pool, seed: seed),
                onAnswer: recordElement,
                onFinish: finish
            )
            .id(round)
        case .cards(let mode, _):
            CardSessionView(
                mode: mode,
                cards: StudyDeckBuilder.flashcards(pool: pool, seed: seed),
                onAnswer: recordElement,
                onFinish: finish
            )
            .id(round)
        case .quiz(let dealer):
            QuizSessionView(
                mode: .quiz,
                questions: questions,
                timerSeconds: dealer.configuration.timerSeconds,
                onAnswer: record,
                onFinish: finish
            )
            .id(round)
        case .match:
            if let matchRound {
                MatchSessionView(round: matchRound, onAnswer: record, onFinish: finish)
                    .id(round)
            }
        case .advanced:
            AdvancedSessionView(
                questions: advancedQuestions,
                onAnswer: recordAdvanced,
                onFinish: finish
            )
            .id(round)
        }
    }

    /// "Study again": a fresh seed and a fresh deck.
    private func dealAgain() {
        round += 1
        roundSeed = QuizSeed.fresh()
        switch plan {
        case .quiz(let dealer): questions = dealer.questions(seed: roundSeed)
        case .match(let dealer): matchRound = dealer.matchRound(seed: roundSeed)
        case .advanced(let dealer): advancedQuestions = dealer.questions(seed: roundSeed)
        case .cards: break
        }
        result = nil
    }

    private func recordElement(atomicNumber: Int, correct: Bool) {
        progress.recordAnswer(atomicNumber: atomicNumber, correct: correct)
    }

    private func record(subject: QuizSubject, correct: Bool) {
        switch subject {
        case .element(let element):
            progress.recordAnswer(atomicNumber: element.atomicNumber, correct: correct)
        case .compound(let compound):
            progress.recordCompoundAnswer(id: compound.id, correct: correct)
        }
    }

    /// An advanced answer counts twice: once against whatever element or
    /// compound it was about, and once against the harder material as a
    /// whole, which is what the learning rank's depth term reads.
    private func recordAdvanced(subject: QuizSubject, correct: Bool) {
        record(subject: subject, correct: correct)
        progress.recordAdvancedAnswer(correct: correct)
    }

    /// The one place a round is counted as complete, for every mode.
    ///
    /// `onFinish` fires exactly once per round, and only when the last card is
    /// rated, the last question is confirmed or the last pair is matched.
    /// Exiting part way through never reaches here, so an interrupted round
    /// never costs the learner part of the free daily allowance.
    private func finish(_ result: StudyResult) {
        self.result = result
        progress.recordCompletedRound()
        onRoundFinished()
    }
}

// MARK: - Session chrome

/// Thin progress header shared by every mode.
struct SessionProgressHeader: View {
    let current: Int
    let total: Int
    /// What one of these is called, for VoiceOver. A deck has cards and a
    /// round has questions, and "Question 3 of 12" is wrong about a flashcard.
    var noun: String = "Question"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .animation(reduceMotion ? nil : Theme.Motion.reveal, value: fraction)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, Theme.Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(noun) \(min(current + 1, total)) of \(total)")
    }
}

// MARK: - Flashcards & Identify

/// Flashcards and Identify share one screen: a card that flips, a deck you can
/// move back and forth through, and an honest two-way self-rating.
///
/// The card turns over when it is tapped, the way a flashcard does everywhere
/// else, and a swipe left or right moves through the deck. Browsing is free:
/// you can go back to a card you have already seen, and forward past one you
/// have not rated yet, without either costing anything.
///
/// Rating is what the study engine records, and it happens once per card.
/// `ratings` is the deck's memory of that — first rating wins, so swiping back
/// to a card you have already judged cannot report it a second time and move
/// mastery twice for one recollection. The round is over when every card in
/// the deck has been rated, not when the last index is reached, because with
/// free movement those are no longer the same thing.
struct CardSessionView: View {
    let mode: StudyMode
    let cards: [StudyCard]
    let onAnswer: (Int, Bool) -> Void
    let onFinish: (StudyResult) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    @State private var isRevealed = false
    /// What the learner said about each card, keyed by its position in the
    /// deck. The count is how far through the round they are; the values are
    /// the score.
    @State private var ratings: [Int: Bool] = [:]
    /// How far the current swipe has traveled, for the card to follow the
    /// finger before it settles.
    @State private var dragOffset: CGFloat = 0

    private var correctCount: Int { ratings.values.filter { $0 }.count }

    private var card: StudyCard? {
        index < cards.count ? cards[index] : nil
    }

    /// A horizontal drag only. The card sits in a vertical `ScrollView` — a
    /// long element name at an accessibility text size makes it taller than a
    /// small phone — so a drag that is mostly vertical has to stay with the
    /// scroll view rather than turning the page.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                defer { withAnimation(reduceMotion ? nil : Theme.Motion.reveal) { dragOffset = 0 } }
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 60 else { return }
                move(by: value.translation.width < 0 ? 1 : -1)
            }
    }

    /// Moves through the deck without judging anything.
    private func move(by step: Int) {
        let target = index + step
        guard cards.indices.contains(target) else { return }
        Haptics.tap()
        withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
            index = target
            // Each card is turned over on its own. Carrying the flip across
            // would give away the next answer before it had been asked.
            isRevealed = false
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            SessionProgressHeader(current: index, total: cards.count, noun: "Card")

            if let card {
                deck(card)
                footer(card)
            }
        }
        // A swipe is a gesture VoiceOver cannot pass through, so the two moves
        // it stands for are offered by name instead. The flip is already a
        // button, so it needs nothing here.
        .accessibilityAction(named: Text("Next card")) { move(by: 1) }
        .accessibilityAction(named: Text("Previous card")) { move(by: -1) }
        .animation(reduceMotion ? nil : Theme.Motion.reveal, value: index)
        .animation(reduceMotion ? nil : Theme.Motion.reveal, value: isRevealed)
        // A container, like the paywall and the summary. This view holds the
        // card face *and* the controls under it, so naming it without
        // `children: .contain` renamed Reveal Answer, the answer, I knew this
        // and Review again to "session.card" — every control a round is
        // played with.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.card")
    }

    /// The card itself: scrollable, because a long element name at an
    /// accessibility text size makes it taller than a small phone and clipped
    /// copy is never acceptable.
    ///
    /// Broken out of `body` rather than written inline. Two of these went into
    /// `StudyScreen.body` in this build and took the type-checker past its
    /// budget; this one is kept small for the same reason.
    private func deck(_ card: StudyCard) -> some View {
        ScrollView {
            cardFace(card)
                .id(card.id)
                .rotation3DEffect(
                    .degrees(reduceMotion ? 0 : (isRevealed ? 180 : 0)),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.35
                )
                .offset(x: dragOffset)
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .offset(x: 40)),
                                removal: .opacity.combined(with: .offset(x: -40))
                              ))
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.vertical, 2)
                // The whole card turns it over, which is what a flashcard
                // does. The button underneath stays: it is what VoiceOver and
                // the UI tests reach for, and a learner who has not guessed
                // that the card is tappable still has something that says so.
                .contentShape(Rectangle())
                .onTapGesture { flip() }
                .gesture(swipe)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// What the gestures are, and the rating. Both gestures are invisible
    /// until somebody tries them, so the line says them once.
    private func footer(_ card: StudyCard) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(gestureHint)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            controls(for: card)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.bottom, Theme.Spacing.l)
    }

    private var gestureHint: String {
        cards.count > 1
            ? "Tap the card to flip it. Swipe to move through the \(cards.count)."
            : "Tap the card to flip it."
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
                        .fill(concealsFamily(card)
                              ? AnyShapeStyle(AppColor.surfaceMuted)
                              : AnyShapeStyle(card.element.category.tileFill
                                              .opacity(isRevealed ? 0.9 : 0.55)))
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
        // The card is turned over by rotating it half a turn; this turns its
        // contents back, so the answer reads the right way round instead of
        // mirrored. Two rotations of 180°, not one of 360°: the outer one is
        // what animates, and this one only has to cancel it.
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : (isRevealed ? 180 : 0)),
            axis: (x: 0, y: 1, z: 0)
        )
    }

    /// A shell diagram in Identify is the whole question, so it may not be drawn
    /// in the answer's family color: the app teaches that palette on onboarding
    /// page one, and lavender alone narrows 118 candidates to seven. Text and
    /// description clues are unaffected — the former *is* the question, and the
    /// latter already names the family in words.
    private func concealsFamily(_ card: StudyCard) -> Bool {
        mode == .identify && !isRevealed && card.clue == .structure
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
            // A glossy model of the atom itself: the shell counts are what
            // make it a fair clue, since they identify the element uniquely.
            //
            // Drawn in neutral gray until the learner commits. The family
            // palette is taught on onboarding page one, so a lavender model
            // would narrow 118 candidates to seven before a single shell had
            // been counted.
            StructurePreview(
                scene: StructureSceneBuilder.scene(for: card.element, representation: .atom),
                accent: card.element.category.accentColor,
                usesElementColor: !concealsFamily(card),
                animates: false
            )
            .frame(height: 168)
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
                flip()
            } label: {
                Text("Flip Card")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    // A floor, not a fixed height — `.body` scales, and past
                    // the larger accessibility sizes a single line of it no
                    // longer fits in 52 points.
                    .padding(.vertical, Theme.Spacing.s)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
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

    /// Turns the card over. Flipping back is allowed — a learner who reveals
    /// too early should be able to hide it again and think.
    private func flip() {
        Haptics.reveal()
        withAnimation(reduceMotion ? nil : Theme.Motion.reveal) { isRevealed.toggle() }
    }

    /// Records what the learner said about this card, then moves on.
    ///
    /// Recorded once. Swiping back to a card already rated and rating it again
    /// changes nothing: the first answer is the one the engine heard, and
    /// counting a second would move mastery twice for one recollection.
    private func advance(card: StudyCard, correct: Bool) {
        if ratings[index] == nil {
            ratings[index] = correct
            onAnswer(card.element.atomicNumber, correct)
        }
        if correct { Haptics.correct() } else { Haptics.incorrect() }

        guard ratings.count < cards.count else {
            Haptics.sessionComplete()
            onFinish(StudyResult(mode: mode, correct: correctCount, total: cards.count))
            return
        }
        // On to the next card still waiting for an answer, wrapping past the
        // end so a card skipped earlier is come back to rather than stranded.
        let order = (1...cards.count).map { (index + $0) % cards.count }
        guard let next = order.first(where: { ratings[$0] == nil }) else { return }
        withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
            isRevealed = false
            index = next
        }
    }
}

// MARK: - Quiz

/// Ten multiple-choice questions. Options lock once answered so the learner
/// sees which one was right before moving on.
struct QuizSessionView: View {
    /// Passed in rather than assumed: reporting `.quiz` for whatever mode
    /// presented this view would mislabel the result the moment another mode
    /// reuses the multiple-choice format.
    let mode: StudyMode
    let questions: [QuizQuestion]
    /// Seconds allowed per question. `nil`, the default, means no clock.
    var timerSeconds: Int?
    let onAnswer: (QuizSubject, Bool) -> Void
    let onFinish: (StudyResult) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    @State private var selection: Int?
    @State private var correctCount = 0
    /// Set when the clock ran out before an answer: the options lock, the
    /// right one is shown, and the question counts as missed.
    @State private var timedOut = false
    @State private var remainingSeconds = 0

    private var question: QuizQuestion? {
        index < questions.count ? questions[index] : nil
    }

    /// Answered, or out of time: either way the options are locked.
    private var isResolved: Bool { selection != nil || timedOut }

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

                        if let timerSeconds, !isResolved {
                            timerLine(total: timerSeconds)
                        }

                        VStack(spacing: Theme.Spacing.s) {
                            ForEach(Array(question.options.indices), id: \.self) { offset in
                                optionButton(
                                    question: question,
                                    offset: offset,
                                    option: question.options[offset]
                                )
                            }
                        }

                        if isResolved {
                            VStack(spacing: 4) {
                                if timedOut {
                                    Text("Out of time. The answer is \(question.correctAnswer).")
                                        .font(.system(.footnote, weight: .semibold))
                                        .foregroundStyle(AppColor.warning)
                                        .accessibilityIdentifier("quiz.timedOut")
                                }
                                if let detail = question.detail {
                                    Text(detail)
                                        .font(AppFont.footnote)
                                        .foregroundStyle(AppColor.secondaryText)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("quiz.detail")
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.bottom, Theme.Spacing.l)
                    .id(question.id)
                }
                .scrollIndicators(.hidden)
                .task(id: index) { await runTimer(for: question) }

                Button {
                    advanceToNextQuestion()
                } label: {
                    Text(index + 1 >= questions.count ? "See results" : "Next question")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, Theme.Spacing.s)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(isResolved ? AppColor.accent : AppColor.tertiaryText)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!isResolved)
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.bottom, Theme.Spacing.l)
                .accessibilityIdentifier("quiz.next")
            } else {
                ScrollView {
                    EmptyStateView(
                        symbolName: "questionmark.circle",
                        title: "No questions available",
                        message: "There are not enough elements loaded to build a quiz."
                    )
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.soft, value: selection)
        .animation(reduceMotion ? nil : Theme.Motion.reveal, value: index)
    }

    /// A countdown in words and as a bar, so it reads without color.
    private func timerLine(total: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(remainingSeconds) s left")
                .font(.system(.footnote, weight: .medium).monospacedDigit())
                .foregroundStyle(remainingSeconds <= 5 ? AppColor.warning : AppColor.secondaryText)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.surfaceMuted)
                    Capsule()
                        .fill(remainingSeconds <= 5 ? AppColor.warning : AppColor.accent)
                        .frame(width: proxy.size.width * CGFloat(remainingSeconds) / CGFloat(max(total, 1)))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(remainingSeconds) seconds left")
        .accessibilityIdentifier("quiz.timer")
    }

    /// Counts the question's clock down, one second at a time. Canceled by
    /// SwiftUI when the question changes; stops on its own once answered.
    private func runTimer(for question: QuizQuestion) async {
        guard let timerSeconds else { return }
        remainingSeconds = timerSeconds
        while remainingSeconds > 0 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, !isResolved else { return }
            remainingSeconds -= 1
        }
        guard !isResolved else { return }
        timedOut = true
        Haptics.incorrect()
        onAnswer(question.subject, false)
    }

    private func optionButton(question: QuizQuestion, offset: Int, option: String) -> some View {
        let isChosen = selection == offset
        let isAnswer = question.isCorrect(offset)
        let resolved = isResolved

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
            guard !isResolved else { return }
            selection = offset
            let correct = question.isCorrect(offset)
            if correct {
                correctCount += 1
                Haptics.correct()
            } else {
                Haptics.incorrect()
            }
            onAnswer(question.subject, correct)
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
        guard isResolved else { return }
        if index + 1 >= questions.count {
            Haptics.sessionComplete()
            onFinish(StudyResult(mode: mode, correct: correctCount, total: questions.count))
        } else {
            selection = nil
            timedOut = false
            index += 1
        }
    }
}

// MARK: - Summary

/// End of a round: the score, and a calm, factual line about it.
struct SessionSummaryView: View {
    let result: StudyResult
    /// False once the free daily allowance is spent. The primary button then
    /// says what it will actually do rather than letting the learner tap
    /// "Study again" and be refused.
    var canStudyAgain: Bool = true
    let onRepeat: () -> Void
    var onUnlock: () -> Void = {}
    let onDone: () -> Void

    var body: some View {
        // Same shape as CardSessionView and QuizSessionView: the content
        // scrolls, the controls stay put. The ring has a hard frame that
        // Dynamic Type multiplies by up to 1.55, and a landscape phone leaves
        // barely 340pt of height — as one unscrollable stack the "Done" button
        // was pushed off the bottom edge with no way to reach it.
        VStack(spacing: Theme.Spacing.l) {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
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
                            .multilineTextAlignment(.center)
                        Text(result.message)
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: Theme.Spacing.s) {
                Button {
                    Haptics.tap()
                    if canStudyAgain { onRepeat() } else { onUnlock() }
                } label: {
                    Text(canStudyAgain ? "Study again" : "Get Elemora Pro")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, Theme.Spacing.s)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(AppColor.accent)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("summary.again")

                if !canStudyAgain {
                    Text("That was your last free round today.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Haptics.tap()
                    onDone()
                } label: {
                    Text("Done")
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(AppColor.accent)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, Theme.Spacing.s)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("summary.done")
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, Theme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A container element, not a relabelling of everything inside it.
        // SwiftUI applies an accessibility identifier to every descendant
        // element when the view it is attached to is not an element itself,
        // so this alone renamed every control below to the container's name.
        // `children: .contain` makes this an accessibility container that
        // holds its children rather than replacing them.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.summary")
    }
}
