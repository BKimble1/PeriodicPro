import SwiftUI

/// The learning hub.
///
/// Laid out to the reference concept: a greeting, two compact status cards, one
/// strong card into a round, four pastel practice tiles, then recent searches
/// and the element shelves. Every number on it is read from `ProgressStore` —
/// a new learner sees a 0-day streak and 0% mastered, not a demo value.
struct StudyScreen: View {
    @Environment(\.elementCatalog) private var catalog
    @Environment(\.selectTab) private var selectTab
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(SubscriptionManager.self) private var store: SubscriptionManager

    @State private var path: [ChemicalElement] = []
    @State private var activeMode: StudyMode?
    /// Captured when a round starts. `studyQueue` is ordered by mastery, which
    /// changes on every answer, and `StudyScreen.body` observes that — so
    /// passing it live handed the running session a freshly shuffled pool after
    /// each card and the deck changed under the learner mid-round.
    @State private var sessionQueue: [ChemicalElement] = []
    @State private var paywall: PaywallContext?
    /// Shown when Smart Review is unlocked but has nothing to review yet.
    @State private var smartReviewNotice: String?
    /// Set when a round ends with the allowance spent. The paywall is only
    /// presented once the session cover has actually gone, never over a round.
    @State private var paywallAfterSession: PaywallContext?
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
        progress.recentlyStudied()
            .filter { !progress.isFavorite($0) }
            .compactMap { catalog.element(atomicNumber: $0) }
    }

    /// The elements the learner knows least well come first.
    private var studyQueue: [ChemicalElement] {
        MasteryEngine.studyPriority(catalog.elements) { progress.mastery(for: $0) }
    }

    private var masteryFraction: Double {
        catalog.count == 0 ? 0 : Double(progress.masteredCount) / Double(catalog.count)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    greeting
                    statusCards
                    heroCard
                    practiceSection
                    recentSearchesSection
                    favoritesSection
                    if !recentlyStudied.isEmpty { recentSection }
                }
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .background(AppColor.canvas)
            .navigationTitle("Study")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ChemicalElement.self) { element in
                ElementDetailScreen(element: element)
                    .zoomTransition(id: element.atomicNumber, namespace: studyNamespace)
            }
            .fullScreenCover(item: $activeMode) { mode in
                StudySessionContainer(
                    mode: mode,
                    queue: sessionQueue,
                    catalog: catalog,
                    onAllowanceSpent: { paywallAfterSession = .dailyLimit }
                )
            }
            .sheet(item: $paywall) { context in
                PaywallView(context: context)
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
            // Presenting the paywall only after the cover has gone avoids the
            // two presentations racing, and means the paywall never appears
            // over a round in progress.
            .onChange(of: activeMode) { _, newValue in
                guard newValue == nil, let pending = paywallAfterSession else { return }
                paywallAfterSession = nil
                paywall = pending
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
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
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

    // MARK: - Hero

    private var heroCard: some View {
        StudyHeroCard(
            title: StudyMode.flashcards.title,
            message: "Memorize, quiz and reinforce your knowledge.",
            symbolName: StudyMode.flashcards.symbolName,
            action: { start(.flashcards) }
        )
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .accessibilityIdentifier("study.heroCard")
    }

    // MARK: - Practice

    private static let modeTints: [StudyMode: ElementCategory] = [
        .flashcards: .metalloid,
        .quiz: .lanthanide,
        .identify: .alkalineEarthMetal,
        .smartReview: .alkaliMetal,
    ]

    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            StudySectionHeader(title: "Practice modes") {
                // Where the reference concept has a "See All" link. All four
                // modes are already on screen, so a link would go nowhere;
                // what belongs in that slot is how much free study is left.
                if let allowance = DailyStudyLimiter.allowanceDescription(
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

            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                ForEach(StudyMode.allCases) { mode in
                    PracticeModeTile(
                        mode: mode,
                        tint: Self.modeTints[mode] ?? .metalloid,
                        showsProBadge: mode.requiresPro && !store.isPro,
                        action: { start(mode) }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
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
            .accessibilityIdentifier("study.recentSearches")
        }
    }

    // MARK: - Favorites and recents

    @ViewBuilder
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(
                title: "Favorites",
                subtitle: favorites.isEmpty ? nil : "\(favorites.count) saved"
            )
            .padding(.horizontal, Theme.Spacing.screenMargin)

            if favorites.isEmpty {
                CardContainer {
                    EmptyStateView(
                        symbolName: "heart",
                        title: "No favorites yet",
                        message: "Tap the heart on any element to keep it here."
                    )
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .accessibilityIdentifier("study.favoritesEmpty")
            } else {
                elementCarousel(favorites, identifierPrefix: "study.favorite")
            }
        }
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

    // MARK: - Starting a round

    /// The single gate for beginning a round from this screen.
    ///
    /// Snapshots the queue and presents in one pass, so the session never sees
    /// a queue that changes beneath it. Everything that could stop a round —
    /// the Pro-only mode, the free daily allowance, and Smart Review not having
    /// enough history yet — is decided here, before anything is presented, and
    /// never once a round is running.
    private func start(_ mode: StudyMode) {
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

        sessionQueue = mode == .smartReview
            ? SmartReviewBuilder.queue(elements: catalog.elements, snapshots: progress.snapshots)
            : studyQueue
        activeMode = mode
    }
}
