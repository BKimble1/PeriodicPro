import SwiftUI

/// Where a quiz or a Match round is shaped before it starts, and where a
/// saved quiz is edited.
///
/// Four questions, in the order somebody actually asks them: what to study,
/// how hard, how many, and where from. Everything else is behind Customize,
/// which is closed until it is wanted. A beginner reaches Start in about three
/// taps; nothing an advanced learner had before has been taken away.
///
/// The engine underneath is untouched. Every control still writes one
/// `QuizConfiguration`, the pool is recomputed as it changes, and the footer
/// says how many items the selection holds and why a round cannot start when
/// it cannot.
struct QuizSetupView: View {
    let mode: StudyMode
    /// The saved quiz being edited, if any.
    var existing: SavedQuiz?
    /// Starts a round with the dealer built here. `nil` hides Start.
    var onStart: ((QuizRoundDealer) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.elementCatalog) private var catalog
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(CompoundStore.self) private var compounds: CompoundStore
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(SavedQuizStore.self) private var savedQuizzes: SavedQuizStore

    @State private var configuration: QuizConfiguration
    @State private var name: String
    @State private var isNamingQuiz = false
    @State private var customCount: Int
    @State private var showsCustomize = false
    @State private var path = NavigationPath()

    init(mode: StudyMode, existing: SavedQuiz? = nil, onStart: ((QuizRoundDealer) -> Void)? = nil) {
        self.mode = mode
        self.existing = existing
        self.onStart = onStart
        var initial = existing?.configuration ?? QuizConfiguration.standard
        if mode == .match, existing == nil {
            initial.questionCount = MatchRoundBuilder.defaultPairCount
        }
        _configuration = State(initialValue: initial)
        _name = State(initialValue: existing?.name ?? "")
        // The count "Custom" switches to must not be one of the presets, or
        // the picker would snap straight back to that preset.
        let presets = mode == .match ? QuizConfiguration.matchPairPresets : QuizConfiguration.lengthPresets
        _customCount = State(initialValue: presets.contains(initial.questionCount)
                             ? (mode == .match ? 7 : 15) : initial.questionCount)
    }

    private var pool: [QuizSubject] {
        QuizPoolBuilder.subjects(
            for: configuration,
            catalog: catalog,
            compounds: compounds.allKnownCompounds,
            elementSnapshots: progress.snapshots,
            compoundSnapshots: progress.compoundSnapshots
        )
    }

    private var unavailableReason: String? {
        QuizPoolBuilder.unavailableReason(for: configuration, poolCount: pool.count)
    }

    private var dealer: QuizRoundDealer {
        QuizRoundDealer(
            configuration: configuration.sanitized(),
            subjects: pool,
            elementDistractors: catalog.elements,
            compoundDistractors: compounds.allKnownCompounds.filter { !$0.isHypothetical }
        )
    }

    private var lengthPresets: [Int] {
        mode == .match ? QuizConfiguration.matchPairPresets : QuizConfiguration.lengthPresets
    }

    /// Four across normally, two once a quarter of the width can no longer
    /// hold a word.
    private var choiceColumns: [GridItem] {
        let item = GridItem(.flexible(), spacing: Theme.Spacing.s)
        return dynamicTypeSize.isAccessibilitySize ? [item, item] : [item, item, item, item]
    }

    private var contentColumns: [GridItem] {
        let item = GridItem(.flexible(), spacing: Theme.Spacing.s)
        return dynamicTypeSize.isAccessibilitySize ? [item] : [item, item, item]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    contentSection
                    difficultySection
                    lengthSection
                    scopeSection
                    customizeSection
                    footerSection
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .background(AppColor.canvas)
            .navigationTitle(existing == nil ? (mode == .match ? "Create a Match" : "Create a Quiz")
                             : "Edit quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("quizSetup.cancel")
                }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .navigationDestination(for: String.self) { route in
                if route == "elements" {
                    ElementMultiPicker(catalog: catalog, selection: $configuration.customElementIDs)
                } else {
                    CompoundMultiPicker(compounds: compounds.allKnownCompounds,
                                        selection: $configuration.customCompoundIDs)
                }
            }
            .alert("Name this quiz", isPresented: $isNamingQuiz) {
                TextField("Quiz name", text: $name)
                    .accessibilityIdentifier("quizSetup.name")
                Button("Save") { save() }
                    .accessibilityIdentifier("quizSetup.confirmSave")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saved quizzes live under My Quizzes on the Study tab.")
            }
        }
        .tint(AppColor.accent)
        .presentationDetents([.large])
        .accessibilityIdentifier("quizSetup.sheet")
    }

    // MARK: - What to study

    private var contentSection: some View {
        QuizSetupSection(title: "What do you want to study?") {
            LazyVGrid(columns: contentColumns, spacing: Theme.Spacing.s) {
                ForEach(QuizContent.allCases) { content in
                    QuizOptionCard(
                        title: content.title,
                        symbolName: symbol(for: content),
                        isSelected: configuration.content == content,
                        identifier: "quizSetup.content.\(content.rawValue)"
                    ) {
                        configuration.content = content
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quizSetup.content")
        }
    }

    private func symbol(for content: QuizContent) -> String {
        switch content {
        case .elements: return "atom"
        case .compounds: return "circle.hexagongrid.fill"
        case .both: return "square.grid.2x2"
        }
    }

    // MARK: - Difficulty

    private var difficultySection: some View {
        QuizSetupSection(title: "Choose difficulty", detail: difficultyNote) {
            LazyVGrid(columns: choiceColumns, spacing: Theme.Spacing.s) {
                ForEach(QuizDifficulty.allCases) { difficulty in
                    QuizOptionCard(
                        title: difficulty.title,
                        isSelected: configuration.difficulty == difficulty,
                        identifier: "quizSetup.difficulty.\(difficulty.rawValue)"
                    ) {
                        configuration.difficulty = difficulty
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quizSetup.difficulty")
        }
    }

    // MARK: - How many

    private var lengthSection: some View {
        QuizSetupSection(title: mode == .match ? "Number of pairs" : "Number of questions") {
            VStack(spacing: Theme.Spacing.s) {
                LazyVGrid(columns: choiceColumns, spacing: Theme.Spacing.s) {
                    ForEach(lengthPresets, id: \.self) { count in
                        QuizOptionCard(
                            title: "\(count)",
                            isSelected: configuration.questionCount == count,
                            identifier: "quizSetup.length.\(count)"
                        ) {
                            configuration.questionCount = count
                        }
                    }
                    QuizOptionCard(
                        title: "Custom",
                        isSelected: !lengthPresets.contains(configuration.questionCount),
                        identifier: "quizSetup.length.custom"
                    ) {
                        configuration.questionCount = customCount
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("quizSetup.length")

                if !lengthPresets.contains(configuration.questionCount) {
                    Stepper(value: Binding(
                        get: { configuration.questionCount },
                        set: { configuration.questionCount = $0; customCount = $0 }
                    ), in: QuizConfiguration.minimumQuestions...QuizConfiguration.maximumQuestions) {
                        Text(mode == .match ? "\(configuration.questionCount) pairs"
                                            : "\(configuration.questionCount) questions")
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.primaryText)
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(minHeight: Theme.minimumTouchTarget)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(AppColor.surface)
                    }
                    .accessibilityIdentifier("quizSetup.customLength")
                }
            }
        }
    }

    // MARK: - Where from

    private var scopeSection: some View {
        QuizSetupSection(title: "Study from") {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(QuizScope.allCases) { scope in
                    QuizOptionRow(
                        title: scope == .custom ? "Choose items" : scope.title,
                        detail: scope.detail,
                        symbolName: symbol(for: scope),
                        isSelected: configuration.scope == scope,
                        identifier: "quizSetup.scope.\(scope.rawValue)"
                    ) {
                        configuration.scope = scope
                    }
                }
                if configuration.scope == .custom {
                    customPickers
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quizSetup.scope")
        }
    }

    private func symbol(for scope: QuizScope) -> String {
        switch scope {
        case .all: return "square.grid.2x2"
        case .favorites: return "heart.fill"
        case .recentlyMissed: return "arrow.counterclockwise"
        case .notMastered: return "circle.lefthalf.filled"
        case .custom: return "list.bullet.rectangle"
        }
    }

    @ViewBuilder
    private var customPickers: some View {
        if configuration.content.includesElements {
            NavigationLink(value: "elements") {
                pickerRow("Elements", value: "\(configuration.customElementIDs.count) chosen")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quizSetup.chooseElements")
        }
        if configuration.content.includesCompounds {
            NavigationLink(value: "compounds") {
                pickerRow("Compounds", value: "\(configuration.customCompoundIDs.count) chosen")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quizSetup.chooseCompounds")
        }
    }

    private func pickerRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.primaryText)
            Spacer(minLength: Theme.Spacing.s)
            Text(value)
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.secondaryText)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.tertiaryText)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(minHeight: Theme.minimumTouchTarget)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(AppColor.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(AppColor.hairline, lineWidth: 0.8)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Customize

    /// Everything the old screen showed at once. Closed by default, and it
    /// says what is set inside it without being opened.
    private var customizeSection: some View {
        CardContainer(padding: Theme.Spacing.m) {
            DisclosureGroup(isExpanded: $showsCustomize) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if configuration.content.includesElements { elementFilters }
                    if configuration.content.includesCompounds { compoundFilters }
                    if mode != .match { roundOptions }
                }
                .padding(.top, Theme.Spacing.m)
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColor.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Customize")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        Text(customizeSummary)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: Theme.minimumTouchTarget)
            }
            .tint(AppColor.accent)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quizSetup.customize")
    }

    private var customizeSummary: String {
        var parts: [String] = []
        if let elements = configuration.elementFilters.summary { parts.append(elements) }
        if let compoundSummary = configuration.compoundFilters.summary { parts.append(compoundSummary) }
        if configuration.isTimed, let seconds = configuration.timerSeconds {
            parts.append("\(seconds)s timer")
        }
        if !configuration.shuffles { parts.append("in order") }
        return parts.isEmpty ? "Optional" : parts.joined(separator: " · ")
    }

    private var elementFilters: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            filterLabel("Element families")
            ChipGrid(items: ElementCategory.displayOrder,
                     selection: $configuration.elementFilters.categories,
                     title: \.shortName, identifierPrefix: "quizSetup.family")
            filterLabel("State at room temperature")
            ChipGrid(items: [MatterPhase.solid, .liquid, .gas],
                     selection: $configuration.elementFilters.phases,
                     title: \.displayName, identifierPrefix: "quizSetup.phase")
            filterLabel("Periods")
            ChipGrid(items: Array(1...7), selection: $configuration.elementFilters.periods,
                     title: { "\($0)" }, identifierPrefix: "quizSetup.period")
            filterLabel("Groups")
            ChipGrid(items: Array(1...18), selection: $configuration.elementFilters.groups,
                     title: { "\($0)" }, identifierPrefix: "quizSetup.group")
            filterLabel("Atomic number range")
            Stepper(value: Binding(
                get: { configuration.elementFilters.minimumAtomicNumber ?? 1 },
                set: { configuration.elementFilters.minimumAtomicNumber = $0 == 1 ? nil : $0 }
            ), in: 1...118) {
                Text("From \(configuration.elementFilters.minimumAtomicNumber ?? 1)")
                    .font(AppFont.footnote)
            }
            .accessibilityIdentifier("quizSetup.minimumZ")
            Stepper(value: Binding(
                get: { configuration.elementFilters.maximumAtomicNumber ?? 118 },
                set: { configuration.elementFilters.maximumAtomicNumber = $0 == 118 ? nil : $0 }
            ), in: 1...118) {
                Text("To \(configuration.elementFilters.maximumAtomicNumber ?? 118)")
                    .font(AppFont.footnote)
            }
            .accessibilityIdentifier("quizSetup.maximumZ")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quizSetup.elementFilters")
    }

    private var compoundFilters: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            filterLabel("Compound bonding")
            ChipGrid(items: CompoundBondingClass.allCases.filter { $0 != .unknown },
                     selection: $configuration.compoundFilters.bondingClasses,
                     title: \.displayName, identifierPrefix: "quizSetup.bonding")
            filterLabel("Compound type")
            ChipGrid(items: CompoundTag.allCases, selection: $configuration.compoundFilters.tags,
                     title: \.displayName, identifierPrefix: "quizSetup.tag")
            Toggle("Only compounds I saved or favorited", isOn: $configuration.compoundFilters.onlySaved)
                .font(AppFont.footnote)
                .accessibilityIdentifier("quizSetup.onlySaved")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quizSetup.compoundFilters")
    }

    private var roundOptions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            filterLabel("Timer")
            Picker("Timer", selection: Binding(
                get: { configuration.timerSeconds ?? 0 },
                set: { configuration.timerSeconds = $0 == 0 ? nil : $0 }
            )) {
                Text("Off").tag(0)
                ForEach(QuizConfiguration.timerPresets, id: \.self) { seconds in
                    Text("\(seconds) s").tag(seconds)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("quizSetup.timer")
            Toggle("Shuffle questions", isOn: $configuration.shuffles)
                .font(AppFont.footnote)
                .accessibilityIdentifier("quizSetup.shuffle")
        }
    }

    // MARK: - Footer and actions

    private var footerSection: some View {
        Group {
            if let unavailableReason {
                Label(unavailableReason, systemImage: "exclamationmark.triangle")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.warning)
                    .accessibilityIdentifier("quizSetup.unavailable")
            } else {
                Text(poolDescription)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
                    .accessibilityIdentifier("quizSetup.poolCount")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let onStart {
                primaryButton(mode == .match ? "Start Match" : "Start Quiz", identifier: "quizSetup.start") {
                    onStart(dealer)
                    dismiss()
                }
                .disabled(unavailableReason != nil)
                .opacity(unavailableReason == nil ? 1 : 0.5)
            }
            Button {
                Haptics.tap()
                if existing == nil { isNamingQuiz = true } else { save() }
            } label: {
                Text(existing == nil ? "Save Quiz" : "Save Changes")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(AppColor.accent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quizSetup.save")
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
    }

    // MARK: - Helpers

    private func filterLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption.weight(.semibold))
            .foregroundStyle(AppColor.secondaryText)
            .textCase(.uppercase)
            .kerning(0.5)
    }

    private var difficultyNote: String {
        switch configuration.difficulty {
        case .easy: return "Names, symbols and formulas."
        case .medium: return "Atomic numbers, families, states, periods, molar masses and bonding."
        case .hard: return "Electron configurations, groups, atomic masses, written clues and atom counts."
        case .mixed: return "A blend of every question type."
        }
    }

    private var poolDescription: String {
        let count = pool.count
        let elements = pool.filter { $0.element != nil }.count
        let compoundCount = count - elements
        var parts: [String] = []
        if elements > 0 { parts.append(elements == 1 ? "1 element" : "\(elements) elements") }
        if compoundCount > 0 { parts.append(compoundCount == 1 ? "1 compound" : "\(compoundCount) compounds") }
        return "This selection holds " + parts.joined(separator: " and ") + "."
    }

    private func primaryButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.vertical, Theme.Spacing.s)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(AppColor.accent)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func save() {
        if var quiz = existing {
            quiz.name = name
            quiz.configuration = configuration
            savedQuizzes.update(quiz)
        } else {
            savedQuizzes.create(name: name, configuration: configuration)
        }
        dismiss()
    }
}
