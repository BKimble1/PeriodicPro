import SwiftUI

/// The learning hub.
///
/// Laid out to the reference concept: a greeting, two compact status cards, one
/// strong card into a round, five pastel practice tiles, then recent searches
/// and the element shelves. Every number on it is read from `ProgressStore` —
/// a new learner sees a 0-day streak and 0% mastered, not a demo value.
struct StudyScreen: View {
    @Environment(\.elementCatalog) private var catalog
    @Environment(\.selectTab) private var selectTab
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(SubscriptionManager.self) private var store: SubscriptionManager
    @Environment(CompoundStore.self) private var compounds: CompoundStore
    @Environment(SavedQuizStore.self) private var savedQuizzes: SavedQuizStore

    @State private var path = NavigationPath()
    /// The round on screen: mode and deck together.
    ///
    /// The deck travels *inside* the item rather than beside it in its own
    /// `@State`. Two state writes driving one presentation is how
    /// `fullScreenCover(item:)` ends up building its content from a stale
    /// item, and every round used to open on "Nothing to study yet". One
    /// value, one write, no window in which they disagree. The deck is still
    /// captured once when the round starts — the study queue is ordered by
    /// mastery, which changes on every answer, and handing the session a live
    /// view of it reshuffled the learner's remaining cards after each one.
    @State private var activeRound: StudyRoundPlan?
    /// The mode whose setup sheet is open: Quiz or Match.
    @State private var setup: StudyMode?
    @State private var paywall: PaywallContext?
    /// Shown when Smart Review is unlocked but has nothing to review yet.
    @State private var smartReviewNotice: String?
    /// Set when a round ends with the allowance spent. The paywall is only
    /// presented once the session cover has actually gone, never over a round.
    @State private var paywallAfterSession: PaywallContext?
    /// What to do once the shared-quiz sheet has finished dismissing. The same
    /// lesson as `paywallAfterSession`: asking to present a round, or to push
    /// a page, from a host that is still presenting does nothing at all.
    @State private var sharedQuizAction: SharedQuizAction?
    /// Whether the round on screen is today's Daily Challenge. The challenge
    /// is only spent when it is finished, so this is what the round's finish
    /// callback consults — opening the challenge and backing out of it leaves
    /// today's still to do.
    @State private var activeRoundIsDailyChallenge = false
    @Namespace private var studyNamespace

    private var favorites: [ChemicalElement] {
        progress.favoriteAtomicNumbers.compactMap { catalog.element(atomicNumber: $0) }
    }

    /// Favorites are excluded on purpose. Both carousels register a
    /// `matchedTransitionSource` under the same id in `studyNamespace`, and a
    /// duplicated (id, namespace) pair makes the zoom resolve ambiguously — the
    /// detail page can grow out of whichever tile happens to be scrolled
    /// off-screen. Showing the same tile twice was a wart in its own right.
    private var recentlyStudied: [ChemicalElement] {
        // A wider window than the shelf shows, filtered and then capped by
        // `StudyShelf`, which is where that rule is tested.
        StudyShelf.recent(
            from: progress.recentlyStudied(limit: 32),
            isFavorite: { progress.isFavorite($0) }
        )
        .compactMap { catalog.element(atomicNumber: $0) }
    }

    /// The elements the learner knows least well come first.
    private var studyQueue: [ChemicalElement] {
        MasteryEngine.studyPriority(catalog.elements) { progress.mastery(for: $0) }
    }

    private var masteryFraction: Double {
        catalog.count == 0 ? 0 : Double(progress.masteredCount) / Double(catalog.count)
    }

    /// Compounds the learner favorited, for the Favorites shelf.
    ///
    /// Favorites means favorites: a favorited compound belongs beside the
    /// favorited elements, not buried in a separate study-material section
    /// where nobody looks for it.
    private var favoriteCompounds: [ChemicalCompound] {
        progress.favoriteCompoundIDs
            .compactMap { compounds.compound(id: $0) }
            .sorted { $0.preferredName < $1.preferredName }
    }

    /// Compounds the learner added to their study material, minus the ones
    /// already shown under Favorites.
    private var studyCompounds: [ChemicalCompound] {
        let favorites = Set(progress.favoriteCompoundIDs)
        return progress.savedCompoundIDs
            .filter { !favorites.contains($0) }
            .compactMap { compounds.compound(id: $0) }
            .filter { !$0.isHypothetical }
            .sorted { $0.preferredName < $1.preferredName }
    }

    private var hasFavorites: Bool { !favorites.isEmpty || !favoriteCompounds.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    greeting
                    statusCards
                    dailyChallengeCard
                    heroCard
                    practiceSection
                    myQuizzesSection
                    recentSearchesSection
                    favoritesSection
                    if !studyCompounds.isEmpty { compoundsSection }
                    if !recentlyStudied.isEmpty { recentSection }
                }
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.canvas)
            .navigationTitle("Study")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ChemicalElement.self) { element in
                ElementDetailScreen(element: element)
                    .zoomTransition(id: element.atomicNumber, namespace: studyNamespace)
            }
            .navigationDestination(for: CompoundMatchCandidate.self) { candidate in
                CompoundDetailScreen(candidate: candidate)
            }
            .navigationDestination(for: StudyRoute.self) { route in
                switch route {
                case .myQuizzes:
                    MyQuizzesScreen { dealer in start(.quiz(dealer)) }
                }
            }
            .sheet(item: $setup) { mode in
                QuizSetupView(mode: mode) { dealer in
                    start(mode == .match ? .match(dealer) : .quiz(dealer))
                }
            }
            .fullScreenCover(item: $activeRound, onDismiss: roundDismissed) { plan in
                StudySessionContainer(
                    plan: plan,
                    catalog: catalog,
                    onAllowanceSpent: { paywallAfterSession = .dailyLimit },
                    onRoundFinished: roundFinished
                )
            }
            .sheet(item: $paywall) { context in
                PaywallView(context: context)
            }
            // A quiz that arrived through a shared link. It is already saved
            // by the time this appears; this says so and offers to play it.
            .sheet(
                isPresented: Binding(
                    get: { savedQuizzes.lastImportOutcome != nil },
                    set: { if !$0 { savedQuizzes.lastImportOutcome = nil } }
                ),
                onDismiss: performSharedQuizAction
            ) {
                if let outcome = savedQuizzes.lastImportOutcome {
                    SharedQuizResultView(
                        outcome: outcome,
                        onStart: { sharedQuizAction = .start($0) },
                        onViewAll: { sharedQuizAction = .viewAll }
                    )
                }
            }
            .alert(
                "Not enough history yet",
                isPresented: Binding(
                    get: { smartReviewNotice != nil },
                    set: { if !$0 { smartReviewNotice = nil } }
                )
            ) {
                Button("OK", role: .cancel) { smartReviewNotice = nil }
            } message: {
                Text(smartReviewNotice ?? "")
            }
        }
        .tint(AppColor.accent)
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(StudyGreeting.salutation())!")
                .font(.system(.largeTitle, weight: .bold))
                .foregroundStyle(AppColor.primaryText)
            Text(StudyGreeting.encouragement(
                masteredCount: progress.masteredCount,
                streak: progress.currentStreak,
                hasStudied: progress.totalAnswered > 0
            ))
            .font(.system(.largeTitle, weight: .bold))
            .foregroundStyle(AppColor.primaryText)
            Text(StudyGreeting.supportingLine)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .padding(.top, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("study.greeting")
    }

    // MARK: - Status

    private var statusCards: some View {
        // Side by side normally; stacked once each card would be a 160-point
        // column trying to hold "Elements mastered" at forty points.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.m))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.m))

        return layout {
            StudyStatusCard(
                title: "\(progress.currentStreak)",
                caption: "Day streak",
                action: { selectTab(.progress) }
            ) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.warning)
            }
            .accessibilityIdentifier("study.streakCard")

            StudyStatusCard(
                title: "\(Int((masteryFraction * 100).rounded()))%",
                caption: "Elements mastered",
                action: { selectTab(.progress) }
            ) {
                MiniProgressRing(progress: masteryFraction)
            }
            .accessibilityIdentifier("study.masteryCard")
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
    }

    // MARK: - Daily Challenge

    /// Five questions, the same five all day.
    ///
    /// Counts for the streak like any other round, and is deterministic per
    /// calendar day — backing out and coming back does not reshuffle it.
    @ViewBuilder
    private var dailyChallengeCard: some View {
        let done = DailyChallengeRecord.isComplete()
        Button {
            guard !done else { return }
            Haptics.tap()
            startDailyChallenge()
        } label: {
            CardContainer {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: done ? "checkmark.seal.fill" : "flag.checkered")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(done ? AppColor.positive : AppColor.accent)
                        .frame(width: 34)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Challenge")
                            .font(.system(.headline, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        Text(done
                             ? "Done for today. A new set tomorrow."
                             : "\(DailyChallenge.questionCount) questions, chosen for where you are.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if !done {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColor.tertiaryText)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .disabled(done)
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("study.dailyChallenge")
    }

    /// A round is over, however it ended.
    ///
    /// `onDismiss` runs after the cover has finished dismissing. Reacting to
    /// the binding going nil instead would fire at the *start* of the
    /// transition, and asking to present a sheet from a host that is still
    /// presenting is how "Get Elemora Pro" ends up doing nothing at all.
    ///
    /// Written as a method rather than a closure inside `body`. Two
    /// multi-statement closures in there took the type-checker past its budget
    /// — "unable to type-check this expression in reasonable time", on a
    /// `body` that was already long.
    private func roundDismissed() {
        // Whatever the round was, it is over. Without this a challenge that was
        // opened and abandoned would still be armed when some later round
        // finished, and that round would spend the day's challenge instead.
        activeRoundIsDailyChallenge = false
        guard let pending = paywallAfterSession else { return }
        paywallAfterSession = nil
        paywall = pending
    }

    /// A round was actually finished — the last question confirmed, not the
    /// cover dismissed.
    private func roundFinished() {
        guard activeRoundIsDailyChallenge else { return }
        activeRoundIsDailyChallenge = false
        DailyChallengeRecord.markComplete()
    }

    private func startDailyChallenge() {
        let questions = DailyChallenge.questions(
            catalog: catalog,
            snapshots: progress.snapshots,
            compounds: compounds.allKnownCompounds
        )
        guard !questions.isEmpty else { return }
        // Marked complete when the round finishes, not here: opening the
        // challenge and closing it again used to spend the day.
        activeRoundIsDailyChallenge = true
        start(.quiz(QuizRoundDealer(
            configuration: QuizConfiguration(
                difficulty: .mixed,
                questionCount: DailyChallenge.questionCount
            ),
            subjects: DailyChallenge.subjects(
                catalog: catalog,
                snapshots: progress.snapshots,
                seed: DailyChallenge.seed()
            ).map(QuizSubject.element),
            elementDistractors: catalog.elements,
            compoundDistractors: compounds.allKnownCompounds.filter { !$0.isHypothetical }
        )))
    }

    // MARK: - Hero

    private var heroCard: some View {
        StudyHeroCard(
            title: StudyMode.flashcards.title,
            message: "Memorize, quiz and reinforce your knowledge.",
            symbolName: StudyMode.flashcards.symbolName,
            action: { open(.flashcards) }
        )
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .accessibilityIdentifier("study.heroCard")
    }

    // MARK: - Practice

    private static let modeTints: [StudyMode: ElementCategory] = [
        .flashcards: .metalloid,
        .quiz: .lanthanide,
        .match: .transitionMetal,
        .identify: .alkalineEarthMetal,
        .advanced: .halogen,
        .smartReview: .alkaliMetal,
    ]

    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            StudySectionHeader(title: "Practice modes") {
                // Where the reference concept has a "See All" link. All four
                // modes are already on screen, so a link would go nowhere;
                // what belongs in that slot is how much free study is left.
                if !store.entitlement.isResolving,
                   let allowance = DailyStudyLimiter.allowanceDescription(
                       completedToday: progress.completedRoundsToday,
                       isPro: store.isPro
                   ) {
                    Text(allowance)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .accessibilityIdentifier("study.allowance")
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)

            // Three across normally, two at accessibility sizes. Five fitted
            // when there were five modes; a sixth would make each tile a
            // sixth of a 375-point screen, which is 47 points, and no mode
            // name goes in that.
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Theme.Spacing.s),
                    count: dynamicTypeSize.isAccessibilitySize ? 2 : 3
                ),
                alignment: .leading,
                spacing: Theme.Spacing.m
            ) {
                ForEach(StudyMode.allCases) { mode in
                    PracticeModeTile(
                        mode: mode,
                        tint: Self.modeTints[mode] ?? .metalloid,
                        // Nothing is said about Pro state until it is known, so
                        // a subscriber never sees a badge appear and vanish.
                        showsProBadge: mode.requiresPro
                            && !store.isPro
                            && !store.entitlement.isResolving,
                        action: { open(mode) }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
    }

    // MARK: - My Quizzes

    private var myQuizzesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            StudySectionHeader(title: "My Quizzes") {
                NavigationLink(value: StudyRoute.myQuizzes) {
                    Text(savedQuizzes.quizzes.isEmpty ? "Create" : "See all")
                        .font(.system(.footnote, weight: .medium))
                        .frame(minHeight: Theme.minimumTouchTarget)
                }
                .accessibilityIdentifier("study.myQuizzes.seeAll")
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)

            if savedQuizzes.quizzes.isEmpty {
                CardContainer {
                    Text("Shape a quiz from the Quiz tile — elements, compounds or both, any difficulty — "
                         + "and save it here to play again or share as a file.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .accessibilityIdentifier("study.myQuizzes.empty")
            } else {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(savedQuizzes.quizzes.prefix(3)) { quiz in
                        SavedQuizRow(quiz: quiz) { startSaved(quiz) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("study.myQuizzes")
    }

    // MARK: - Compounds

    private var compoundsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Compounds", subtitle: "\(studyCompounds.count) in your study material")
                .padding(.horizontal, Theme.Spacing.screenMargin)
            compoundCarousel(studyCompounds, identifierPrefix: "study.compound")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("study.compounds")
    }

    /// One horizontal shelf of compounds. Used by Favorites and by the study
    /// material section, so the two can never drift apart visually.
    private func compoundCarousel(
        _ items: [ChemicalCompound],
        identifierPrefix: String
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.m) {
                ForEach(items) { compound in
                    Button {
                        Haptics.tap()
                        path.append(CompoundMatchCandidate(local: compound))
                    } label: {
                        VStack(spacing: 6) {
                            CompoundTile(formula: compound.formula, size: 68)
                            Text(compound.preferredName)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: 74)
                        }
                    }
                    .buttonStyle(ElementTileButtonStyle())
                    .accessibilityLabel(compound.accessibilityDescription)
                    .accessibilityIdentifier("\(identifierPrefix).\(compound.pubChemCID ?? 0)")
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Recent searches

    @ViewBuilder
    private var recentSearchesSection: some View {
        if !progress.recentSearches.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StudySectionHeader(title: "Recent searches") {
                    Button("Clear") {
                        Haptics.tap()
                        progress.clearRecentSearches()
                    }
                    .font(.system(.footnote, weight: .medium))
                    .frame(minHeight: Theme.minimumTouchTarget)
                    .accessibilityIdentifier("study.clearSearches")
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)

                VStack(spacing: 0) {
                    ForEach(Array(progress.recentSearches.enumerated()), id: \.offset) { index, term in
                        if index > 0 {
                            Divider()
                                .overlay(AppColor.hairline)
                                .padding(.leading, Theme.Spacing.xxl)
                        }
                        RecentSearchRow(term: term)
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(AppColor.surface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(AppColor.hairline, lineWidth: 0.7)
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
            }
            // A container element, not a relabelling of everything inside it.
            // SwiftUI applies an accessibility identifier to every descendant
            // element when the view it is attached to is not an element itself,
            // so this alone renamed every control below to the container's name.
            // `children: .contain` makes this an accessibility container that
            // holds its children rather than replacing them.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("study.recentSearches")
        }
    }

    // MARK: - Favorites and recents

    @ViewBuilder
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(
                title: "Favorites",
                subtitle: hasFavorites ? favoritesSubtitle : nil
            )
            .padding(.horizontal, Theme.Spacing.screenMargin)

            if !hasFavorites {
                CardContainer {
                    EmptyStateView(
                        symbolName: "heart",
                        title: "No favorites yet",
                        message: "Tap the heart on any element or compound to keep it here."
                    )
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .accessibilityIdentifier("study.favoritesEmpty")
            } else {
                // Two shelves under one heading rather than one mixed row:
                // an element tile and a compound tile are different things and
                // a learner scanning for water should not have to read past
                // eleven elements to find it.
                if !favorites.isEmpty {
                    shelfLabel("Elements")
                    elementCarousel(favorites, identifierPrefix: "study.favorite")
                }
                if !favoriteCompounds.isEmpty {
                    shelfLabel("Compounds")
                    compoundCarousel(favoriteCompounds, identifierPrefix: "study.favoriteCompound")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("study.favorites")
    }

    private var favoritesSubtitle: String {
        var parts: [String] = []
        if !favorites.isEmpty {
            parts.append(favorites.count == 1 ? "1 element" : "\(favorites.count) elements")
        }
        if !favoriteCompounds.isEmpty {
            parts.append(favoriteCompounds.count == 1 ? "1 compound" : "\(favoriteCompounds.count) compounds")
        }
        return parts.joined(separator: " · ")
    }

    private func shelfLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption.weight(.semibold))
            .foregroundStyle(AppColor.secondaryText)
            .textCase(.uppercase)
            .kerning(0.5)
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .accessibilityAddTraits(.isHeader)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Recently studied")
                .padding(.horizontal, Theme.Spacing.screenMargin)
            elementCarousel(recentlyStudied, identifierPrefix: "study.recent")
        }
    }

    private func elementCarousel(
        _ elements: [ChemicalElement],
        identifierPrefix: String
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.m) {
                ForEach(elements) { element in
                    Button {
                        Haptics.tap()
                        path.append(element)
                    } label: {
                        VStack(spacing: 6) {
                            ElementTile(
                                element: element,
                                size: 68,
                                density: .standard,
                                isFavorite: progress.isFavorite(element.atomicNumber),
                                mastery: progress.mastery(for: element.atomicNumber),
                                showsMastery: true
                            )
                            // Two lines: every element name fits on one at
                            // default sizes, but at accessibility type a single
                            // capped line renders "Magne…" for a reader who is
                            // running large type precisely because they need it.
                            Text(element.name)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: 74)
                        }
                    }
                    .buttonStyle(ElementTileButtonStyle())
                    .zoomTransitionSource(id: element.atomicNumber, namespace: studyNamespace)
                    .accessibilityIdentifier("\(identifierPrefix).\(element.symbol)")
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    /// Runs once the shared-quiz sheet has actually gone.
    private func performSharedQuizAction() {
        savedQuizzes.lastImportOutcome = nil
        guard let action = sharedQuizAction else { return }
        sharedQuizAction = nil
        switch action {
        case .start(let quiz): startSaved(quiz)
        case .viewAll: path.append(StudyRoute.myQuizzes)
        }
    }

    // MARK: - Starting a round

    /// A tap on a practice tile. Quiz and Match open their setup sheet; the
    /// card modes start straight away.
    private func open(_ mode: StudyMode) {
        if mode.opensSetup {
            guard activeRound == nil, paywall == nil else { return }
            setup = mode
            return
        }
        if mode == .advanced {
            start(.advanced(AdvancedRoundDealer(
                catalog: catalog,
                compounds: compounds.allKnownCompounds.filter { !$0.isHypothetical }
            )))
            return
        }
        let queue = mode == .smartReview
            ? SmartReviewBuilder.queue(elements: catalog.elements, snapshots: progress.snapshots)
            : studyQueue
        start(.cards(mode, queue))
    }

    /// Starts one of the learner's saved quizzes from the shelf.
    private func startSaved(_ quiz: SavedQuiz) {
        let pool = QuizPoolBuilder.subjects(
            for: quiz.configuration,
            catalog: catalog,
            compounds: compounds.allKnownCompounds,
            elementSnapshots: progress.snapshots,
            compoundSnapshots: progress.compoundSnapshots
        )
        guard QuizPoolBuilder.unavailableReason(for: quiz.configuration, poolCount: pool.count) == nil else {
            path.append(StudyRoute.myQuizzes)
            return
        }
        start(.quiz(QuizRoundDealer(
            configuration: quiz.configuration,
            subjects: pool,
            elementDistractors: catalog.elements,
            compoundDistractors: compounds.allKnownCompounds.filter { !$0.isHypothetical }
        )))
    }

    /// The single gate for beginning a round from this screen.
    ///
    /// The plan is captured before anything is presented, so the session
    /// never sees a queue that changes beneath it. Everything that could stop
    /// a round — the Pro-only mode, the free daily allowance, and Smart Review
    /// not having enough history yet — is decided here, before anything is
    /// presented, and never once a round is running.
    private func start(_ plan: StudyRoundPlan) {
        Task { @MainActor in await beginRound(plan) }
    }

    /// Main-actor isolated because it assigns view state.
    @MainActor
    private func beginRound(_ plan: StudyRoundPlan) async {
        // Nothing may start, and no paywall may appear, while a round is on
        // screen. Two taps during the suspension below would otherwise resume
        // in arbitrary order and put a paywall over a running session.
        guard activeRound == nil, paywall == nil else { return }

        // StoreKit may not have answered yet on a very fast first tap. Asking
        // again is the difference between a subscriber starting their round and
        // a subscriber being shown a paywall — but it is bounded, because
        // StoreKit does not promise to answer and an unbounded await here means
        // the tile does nothing at all.
        await store.resolveEntitlement()

        // Re-checked after the suspension: the state may have moved while this
        // task was waiting.
        guard activeRound == nil, paywall == nil else { return }

        let mode = plan.mode
        if mode.requiresPro, !store.isPro {
            paywall = .smartReview
            return
        }
        if !DailyStudyLimiter.canStartRound(
            completedToday: progress.completedRoundsToday,
            isPro: store.isPro
        ) {
            paywall = .dailyLimit
            return
        }
        // Smart Review with no history would just be Flashcards under another
        // name, which is not what the learner paid for. Say so instead.
        if mode == .smartReview,
           let reason = SmartReviewBuilder.unavailableReason(snapshots: progress.snapshots) {
            smartReviewNotice = reason
            return
        }

        activeRound = plan
    }
}

/// Where the Study tab's stack can go besides an element or a compound.
enum StudyRoute: Hashable {
    case myQuizzes
}

/// What the shared-quiz sheet asked for, held until it has finished dismissing.
enum SharedQuizAction: Hashable {
    case start(SavedQuiz)
    case viewAll
}

/// One saved quiz on the Study tab's shelf, with its Start button.
struct SavedQuizRow: View {
    let quiz: SavedQuiz
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColor.accent)
                .frame(width: 34, height: 34)
                .background { Circle().fill(AppColor.accent.opacity(0.10)) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(quiz.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                Text(quiz.configuration.summary)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.s)
            Button {
                Haptics.tap()
                onStart()
            } label: {
                Text("Start")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.l)
                    .frame(minHeight: Theme.minimumTouchTarget)
                    .background { Capsule().fill(AppColor.accent) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start \(quiz.name)")
            .accessibilityIdentifier("study.savedQuiz.start.\(quiz.id.uuidString)")
        }
        .padding(Theme.Spacing.m)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(AppColor.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(AppColor.hairline, lineWidth: 0.7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("study.savedQuiz.\(quiz.id.uuidString)")
    }
}
