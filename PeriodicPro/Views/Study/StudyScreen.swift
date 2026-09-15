import SwiftUI

/// The learning hub: pick up where you left off, jump to a favorite, or start
/// one of the three practice modes.
struct StudyScreen: View {
    @Environment(\.elementCatalog) private var catalog
    @Environment(ProgressStore.self) private var progress: ProgressStore

    @State private var path: [ChemicalElement] = []
    @State private var activeMode: StudyMode?
    /// Captured when a round starts. `studyQueue` is ordered by mastery, which
    /// changes on every answer, and `StudyScreen.body` observes that — so
    /// passing it live handed the running session a freshly shuffled pool after
    /// each card and the deck changed under the learner mid-round.
    @State private var sessionQueue: [ChemicalElement] = []
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

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    Text("Explore. Practice. Remember.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.horizontal, Theme.Spacing.screenMargin)

                    continueCard
                        .padding(.horizontal, Theme.Spacing.screenMargin)

                    modesSection
                        .padding(.horizontal, Theme.Spacing.screenMargin)

                    favoritesSection

                    if !recentlyStudied.isEmpty {
                        recentSection
                    }
                }
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .background(AppColor.canvas)
            .navigationTitle("Study")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: ChemicalElement.self) { element in
                ElementDetailScreen(element: element)
                    .zoomTransition(id: element.atomicNumber, namespace: studyNamespace)
            }
            .fullScreenCover(item: $activeMode) { mode in
                StudySessionContainer(mode: mode, queue: sessionQueue, catalog: catalog)
            }
        }
        .tint(AppColor.accent)
    }

    // MARK: - Continue

    private var continueCard: some View {
        Button {
            Haptics.tap()
            start(.flashcards)
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(progress.totalAnswered == 0 ? "Start studying" : "Continue studying")
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)
                    Text(continueSubtitle)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background { Circle().fill(AppColor.accent) }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColor.accent.opacity(0.14),
                                ElementCategory.nobleGas.tileFill.opacity(0.9),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(AppColor.accent.opacity(0.16), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("study.continueCard")
        .accessibilityHint("Starts a flashcard round")
    }

    private var continueSubtitle: String {
        let streak = progress.currentStreak
        if progress.totalAnswered == 0 {
            return "Ten quick flashcards, starting with the elements you have not seen yet."
        }
        if streak > 1 {
            return "\(streak)-day streak \u{00B7} \(progress.masteredCount) of \(catalog.count) mastered"
        }
        return "\(progress.masteredCount) of \(catalog.count) mastered \u{00B7} pick up where you left off"
    }

    /// Snapshots the queue, then presents the round. Both happen in one pass so
    /// the session never sees a queue that changes beneath it.
    private func start(_ mode: StudyMode) {
        sessionQueue = studyQueue
        activeMode = mode
    }

    // MARK: - Modes

    private var modesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Practice", subtitle: "Short rounds of ten")
            VStack(spacing: Theme.Spacing.s) {
                ForEach(StudyMode.allCases) { mode in
                    Button {
                        Haptics.tap()
                        start(mode)
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(AppColor.accent)
                                .frame(width: 40, height: 40)
                                .background {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(AppColor.accent.opacity(0.10))
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .font(.system(.body, weight: .semibold))
                                    .foregroundStyle(AppColor.primaryText)
                                Text(mode.subtitle)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.secondaryText)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColor.tertiaryText)
                        }
                        .padding(Theme.Spacing.m)
                        .frame(minHeight: 64)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(AppColor.surface)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .strokeBorder(AppColor.hairline, lineWidth: 0.7)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("study.mode.\(mode.rawValue)")
                }
            }
        }
    }

    // MARK: - Favorites

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
                        message: "Tap the heart on any element to keep it here for quick review."
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

    private func elementCarousel(_ elements: [ChemicalElement], identifierPrefix: String) -> some View {
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
}
