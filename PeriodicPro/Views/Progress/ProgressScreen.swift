import SwiftUI

/// Honest, restrained progress reporting: how many elements are mastered,
/// how consistent the learner has been, and where the gaps are by family.
struct ProgressScreen: View {
    @Environment(\.elementCatalog) private var catalog
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(CompoundStore.self) private var compounds: CompoundStore
    @Environment(\.selectTab) private var selectTab

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var total: Int { max(catalog.count, 1) }
    private var mastered: Int { progress.masteredCount }
    private var fraction: Double { Double(mastered) / Double(total) }

    /// The path, measured from progress the app already keeps.
    private var pathSteps: [LearningPathStep] {
        LearningPathBuilder.steps(
            catalog: catalog,
            elements: progress.snapshots,
            compounds: progress.compoundSnapshots,
            advancedAnswered: progress.advancedAnswered
        )
    }

    /// The rank the score adds up to, weighted for breadth.
    private var standing: RankStanding {
        LearningRankCalculator.standing(
            elements: progress.snapshots,
            elementCount: catalog.count,
            compounds: progress.compoundSnapshots,
            hardQuestionsCorrect: progress.advancedCorrect,
            hardQuestionsAnswered: progress.advancedAnswered,
            studyDaysInLastMonth: progress.studyDayCount(inLast: 30),
            pathCompletion: LearningPathBuilder.completion(pathSteps)
        )
    }

    /// Accuracy across everything answered. `nil` before anything has been.
    private var recentAccuracy: Double? {
        let correct = progress.snapshots.values.reduce(0) { $0 + $1.correctCount }
        let attempts = progress.totalAnswered
        guard attempts > 0 else { return nil }
        return Double(correct) / Double(attempts)
    }

    private var familyRows: [FamilyMasteryCard.Row] {
        ElementCategory.displayOrder.map { category in
            let members = catalog.elements(in: category)
            let snapshots = members.compactMap { progress.snapshots[$0.atomicNumber] }
            let correct = snapshots.reduce(0) { $0 + $1.correctCount }
            let attempts = snapshots.reduce(0) { $0 + $1.attempts }
            let due = snapshots.filter {
                ReviewSchedule.isDue(lastReviewed: $0.lastReviewed, mastery: $0.mastery,
                                     correct: $0.correctCount, incorrect: $0.incorrectCount)
            }.count
            return FamilyMasteryCard.Row(
                category: category,
                mastered: progress.masteredCount(in: category, catalog: catalog),
                total: catalog.count(of: category),
                accuracy: attempts > 0 ? Double(correct) / Double(attempts) : nil,
                due: due
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.section) {
                    PeriodicMasteryHero(
                        mastered: mastered,
                        total: total,
                        compoundsStudied: progress.studyCompoundIDs.count,
                        recentAccuracy: recentAccuracy,
                        standing: standing
                    )
                    statsRow
                    LearningPathCard(steps: pathSteps) { _ in
                        // The path recommends; Study is where a round starts,
                        // and nothing here is a gate on going anywhere else.
                        selectTab(.study)
                    }
                    FamilyMasteryCard(rows: familyRows) { _ in
                        selectTab(.study)
                    }
                    storageNotices
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.canvas)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // A gear, not an ellipsis. About and Reset moved into
                    // Settings, where somebody looking for them would look.
                    NavigationLink(value: ProgressRoute.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("progress.settings")
                }
            }
            .navigationDestination(for: ProgressRoute.self) { route in
                switch route {
                case .settings: SettingsScreen()
                }
            }
        }
        .tint(AppColor.accent)
    }

    /// Two across normally, one across once the caption no longer fits a
    /// ~160pt column. Hard-coded rows of two truncated "cards answered" to
    /// "cards / answe…" at accessibility sizes and wrapped the number itself.
    private var statColumns: [GridItem] {
        [GridItem(
            .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 300 : 150),
            spacing: Theme.Spacing.m
        )]
    }

    private var statsRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Activity")
            LazyVGrid(columns: statColumns, spacing: Theme.Spacing.m) {
                StatTile(
                    value: "\(progress.currentStreak)",
                    caption: "day streak",
                    symbolName: "flame.fill",
                    tint: AppColor.warning
                )
                .accessibilityIdentifier("progress.streak")
                StatTile(
                    value: "\(progress.totalAnswered)",
                    caption: "cards answered",
                    symbolName: "checkmark.circle.fill",
                    tint: AppColor.accent
                )
                .accessibilityIdentifier("progress.answered")
                StatTile(
                    value: "\(progress.startedCount)",
                    caption: "elements started",
                    symbolName: "book.fill",
                    tint: AppColor.positive
                )
                StatTile(
                    value: "\(progress.favoriteAtomicNumbers.count)",
                    caption: "favorites saved",
                    symbolName: "heart.fill",
                    tint: ElementCategory.alkaliMetal.accentColor
                )
                StatTile(
                    value: "\(progress.studyCompoundIDs.count)",
                    caption: "compounds in study",
                    symbolName: "circle.hexagongrid.fill",
                    tint: ElementCategory.transitionMetal.accentColor
                )
                .accessibilityIdentifier("progress.compounds")
                StatTile(
                    value: "\(progress.masteredCompoundCount)",
                    caption: "compounds mastered",
                    symbolName: "checkmark.circle.fill",
                    tint: AppColor.positive
                )
            }
        }
    }

    /// The app is honest about storage problems rather than quietly losing
    /// progress. Nothing renders when everything is working, which is the
    /// normal case.
    @ViewBuilder
    private var storageNotices: some View {
        if progress.storage.losesProgressOnQuit {
            notice(
                title: "Progress is not being saved",
                message: """
                    The on-device store could not be opened, so this session's progress \
                    will be lost when the app closes. Restarting the app usually fixes it.
                    """
            )
        }
        if progress.storage.discardedPreviousProgress {
            notice(
                title: "Earlier progress could not be recovered",
                message: """
                    Saved progress was unreadable and had to be rebuilt, so familiarity \
                    scores and your streak have started again. New progress is being saved \
                    normally.
                    """
            )
        }
        if let failure = progress.readFailureMessage {
            notice(title: "Some saved data could not be read", message: failure)
        }
        if let failure = progress.writeFailureMessage {
            notice(title: "Something could not be saved", message: failure)
        }
    }

    private func notice(title: String, message: String) -> some View {
        CardContainer {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColor.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppColor.primaryText)
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress.storageNotice")
    }
}

/// Where the Progress tab's stack can go.
enum ProgressRoute: Hashable {
    case settings
}

/// Short, factual credits and data provenance. The things that *are*
/// configurable live in `SettingsScreen`; this is the provenance it links to.
struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.elementCatalog) private var catalog
    @Environment(CompoundStore.self) private var compounds: CompoundStore

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("The data") {
                    LabeledContent("Elements", value: "\(catalog.count)")
                    LabeledContent("Atomic weights", value: "IUPAC 2021")
                    Text("""
                        Standard atomic weights follow the IUPAC 2021 table. Elements with no \
                        stable isotope show the mass number of their most stable known isotope \
                        instead. Properties for elements 104 and above are largely predicted \
                        rather than measured.
                        """)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                }

                Section("Privacy") {
                    Text("""
                        Everything you do stays on this device. There is no account and no \
                        analytics \u{2014} favorites, familiarity scores, saved quizzes and \
                        recent searches are stored locally, and are removed when you delete \
                        the app.
                        """)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                    Text("""
                        Online compound searches are sent to PubChem to retrieve requested \
                        chemical information. Only the name or formula you look up is sent, \
                        only when you search for a compound or look one up in the builder, \
                        and nothing about you travels with it.
                        """)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .accessibilityIdentifier("about.pubchem")
                }

                Section("Compounds") {
                    LabeledContent("Bundled compounds", value: "\(compounds.catalog.count)")
                    Text("""
                        Bundled compound records are verified against PubChem and carry its \
                        compound identifier. Molecular pictures are computed conformers or \
                        representative unit cells, and every picture says which. A composition \
                        the builder cannot match is saved only as a hypothetical composition: \
                        a database miss is never treated as a discovery.
                        """)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                }

                Section("Diagrams") {
                    Text("""
                        Shell diagrams are educational simplifications. They show how many \
                        electrons occupy each energy level; electrons do not travel around \
                        the nucleus on fixed circular paths.
                        """)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                }

                Section {
                    LabeledContent("Version", value: version)
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }
}
