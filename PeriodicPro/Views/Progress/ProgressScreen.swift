import SwiftUI

/// Honest, restrained progress reporting: how many elements are mastered,
/// how consistent the learner has been, and where the gaps are by family.
struct ProgressScreen: View {
    @Environment(\.elementCatalog) private var catalog
    @Environment(ProgressStore.self) private var progress: ProgressStore

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showsResetConfirmation = false
    @State private var showsAbout = false

    private var total: Int { max(catalog.count, 1) }
    private var mastered: Int { progress.masteredCount }
    private var fraction: Double { Double(mastered) / Double(total) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.section) {
                    overviewCard
                    statsRow
                    categoryBreakdown
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
                    Menu {
                        Button {
                            showsAbout = true
                        } label: {
                            Label("About this app", systemImage: "info.circle")
                        }
                        Button(role: .destructive) {
                            showsResetConfirmation = true
                        } label: {
                            Label("Reset progress", systemImage: "arrow.counterclockwise")
                        }
                        // resetAllProgress() deliberately keeps favorites, so
                        // having favorites is never a reason for this command to
                        // have work to do — it would only ever raise a
                        // destructive confirmation that then changed nothing.
                        .disabled(progress.totalAnswered == 0)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More options")
                    .accessibilityIdentifier("progress.menu")
                }
            }
            .confirmationDialog(
                "Reset all progress?",
                isPresented: $showsResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset progress", role: .destructive) {
                    progress.resetAllProgress()
                    Haptics.tap()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Familiarity scores and your streak will be cleared. Favorites are kept.")
            }
            .sheet(isPresented: $showsAbout) {
                AboutSheet()
            }
        }
        .tint(AppColor.accent)
    }

    private var overviewCard: some View {
        CardContainer(padding: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.l) {
                ProgressRing(
                    progress: fraction,
                    lineWidth: 12,
                    diameter: 158,
                    tint: AppColor.positive,
                    centerTitle: "\(mastered)",
                    centerCaption: "of \(total) mastered"
                )
                .accessibilityIdentifier("progress.ring")

                VStack(spacing: 4) {
                    Text(headline)
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .multilineTextAlignment(.center)
                    Text("""
                        An element becomes mastered after three correct answers, and slips \
                        back a step whenever you miss one.
                        """)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var headline: String {
        switch mastered {
        case 0: return "Your first mastered element is a round away"
        case 1..<12: return "\(Int((fraction * 100).rounded()))% of the table mastered"
        case 12..<80: return "Steady progress across the table"
        default: return "Most of the table is yours"
        }
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

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "By family", subtitle: "Mastered elements in each family")
            CardContainer {
                VStack(spacing: Theme.Spacing.l) {
                    ForEach(ElementCategory.displayOrder) { category in
                        CategoryProgressBar(
                            category: category,
                            mastered: progress.masteredCount(in: category, catalog: catalog),
                            total: catalog.count(of: category)
                        )
                    }
                }
            }
            .accessibilityIdentifier("progress.byFamily")
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

/// Short, factual credits and data provenance. Deliberately not a settings
/// screen — there is nothing here to configure.
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
