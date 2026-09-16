import SwiftUI

/// Where a quiz or a Match round is shaped before it starts, and where a
/// saved quiz is edited.
///
/// Everything here writes one `QuizConfiguration`. The pool is recomputed as
/// the learner changes it, so the footer always says how many items the
/// selection holds — and why a round cannot start, when it cannot.
struct QuizSetupView: View {
    let mode: StudyMode
    /// The saved quiz being edited, if any.
    var existing: SavedQuiz?
    /// Starts a round with the dealer built here. `nil` hides Start.
    var onStart: ((QuizRoundDealer) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.elementCatalog) private var catalog
    @Environment(CompoundStore.self) private var compounds: CompoundStore
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(SavedQuizStore.self) private var savedQuizzes: SavedQuizStore

    @State private var configuration: QuizConfiguration
    @State private var name: String
    @State private var isNamingQuiz = false
    @State private var customCount: Int

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

    var body: some View {
        NavigationStack {
            Form {
                contentSection
                scopeSection
                if configuration.content.includesElements { elementFilterSection }
                if configuration.content.includesCompounds { compoundFilterSection }
                if mode == .match { pairsSection } else { questionsSection }
                footerSection
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(existing == nil ? mode.fullTitle : "Edit quiz")
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

    // MARK: - Sections

    private var contentSection: some View {
        Section("Ask about") {
            Picker("Content", selection: $configuration.content) {
                ForEach(QuizContent.allCases) { content in
                    Text(content.title).tag(content)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("quizSetup.content")
        }
    }

    private var scopeSection: some View {
        Section("From") {
            Picker("Scope", selection: $configuration.scope) {
                ForEach(QuizScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("quizSetup.scope")
            Text(configuration.scope.detail)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            if configuration.scope == .custom {
                if configuration.content.includesElements {
                    NavigationLink(value: "elements") {
                        LabeledContent("Elements", value: "\(configuration.customElementIDs.count) chosen")
                    }
                    .accessibilityIdentifier("quizSetup.chooseElements")
                }
                if configuration.content.includesCompounds {
                    NavigationLink(value: "compounds") {
                        LabeledContent("Compounds", value: "\(configuration.customCompoundIDs.count) chosen")
                    }
                    .accessibilityIdentifier("quizSetup.chooseCompounds")
                }
            }
        }
    }

    private var elementFilterSection: some View {
        Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    filterLabel("Families")
                    ChipGrid(items: ElementCategory.displayOrder, selection: $configuration.elementFilters.categories,
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
                    HStack(spacing: Theme.Spacing.l) {
                        Stepper(value: Binding(
                            get: { configuration.elementFilters.minimumAtomicNumber ?? 1 },
                            set: { configuration.elementFilters.minimumAtomicNumber = $0 == 1 ? nil : $0 }
                        ), in: 1...118) {
                            Text("From \(configuration.elementFilters.minimumAtomicNumber ?? 1)")
                                .font(AppFont.footnote)
                        }
                        .accessibilityIdentifier("quizSetup.minimumZ")
                    }
                    Stepper(value: Binding(
                        get: { configuration.elementFilters.maximumAtomicNumber ?? 118 },
                        set: { configuration.elementFilters.maximumAtomicNumber = $0 == 118 ? nil : $0 }
                    ), in: 1...118) {
                        Text("To \(configuration.elementFilters.maximumAtomicNumber ?? 118)")
                            .font(AppFont.footnote)
                    }
                    .accessibilityIdentifier("quizSetup.maximumZ")
                }
                .padding(.vertical, Theme.Spacing.s)
            } label: {
                LabeledContent("Element filters", value: configuration.elementFilters.summary ?? "Any")
            }
            .accessibilityIdentifier("quizSetup.elementFilters")
        }
    }

    private var compoundFilterSection: some View {
        Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    filterLabel("Bonding")
                    ChipGrid(items: CompoundBondingClass.allCases.filter { $0 != .unknown },
                             selection: $configuration.compoundFilters.bondingClasses,
                             title: \.displayName, identifierPrefix: "quizSetup.bonding")
                    filterLabel("Type")
                    ChipGrid(items: CompoundTag.allCases, selection: $configuration.compoundFilters.tags,
                             title: \.displayName, identifierPrefix: "quizSetup.tag")
                    Toggle("Only compounds I saved or favorited", isOn: $configuration.compoundFilters.onlySaved)
                        .font(AppFont.footnote)
                        .accessibilityIdentifier("quizSetup.onlySaved")
                }
                .padding(.vertical, Theme.Spacing.s)
            } label: {
                LabeledContent("Compound filters", value: configuration.compoundFilters.summary ?? "Any")
            }
            .accessibilityIdentifier("quizSetup.compoundFilters")
        }
    }

    private var questionsSection: some View {
        Section("Questions") {
            Picker("Difficulty", selection: $configuration.difficulty) {
                ForEach(QuizDifficulty.allCases) { difficulty in
                    Text(difficulty.title).tag(difficulty)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("quizSetup.difficulty")
            Text(difficultyNote)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            lengthPicker
            Picker("Timer", selection: Binding(
                get: { configuration.timerSeconds ?? 0 },
                set: { configuration.timerSeconds = $0 == 0 ? nil : $0 }
            )) {
                Text("Off").tag(0)
                ForEach(QuizConfiguration.timerPresets, id: \.self) { seconds in
                    Text("\(seconds) s").tag(seconds)
                }
            }
            .accessibilityIdentifier("quizSetup.timer")
            Toggle("Shuffle questions", isOn: $configuration.shuffles)
                .accessibilityIdentifier("quizSetup.shuffle")
        }
    }

    private var pairsSection: some View {
        Section("Pairs") {
            lengthPicker
        }
    }

    private var lengthPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Picker(mode == .match ? "Pairs" : "Length", selection: Binding(
                get: { lengthPresets.contains(configuration.questionCount) ? configuration.questionCount : 0 },
                set: { newValue in
                    if newValue == 0 {
                        configuration.questionCount = customCount
                    } else {
                        configuration.questionCount = newValue
                    }
                }
            )) {
                ForEach(lengthPresets, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
                Text("Custom").tag(0)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("quizSetup.length")
            if !lengthPresets.contains(configuration.questionCount) {
                Stepper(value: Binding(
                    get: { configuration.questionCount },
                    set: { configuration.questionCount = $0; customCount = $0 }
                ), in: QuizConfiguration.minimumQuestions...QuizConfiguration.maximumQuestions) {
                    Text(mode == .match ? "\(configuration.questionCount) pairs"
                                        : "\(configuration.questionCount) questions")
                        .font(AppFont.footnote)
                }
                .accessibilityIdentifier("quizSetup.customLength")
            }
        }
    }

    private var footerSection: some View {
        Section {
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
                Text(existing == nil ? "Save as Quiz" : "Save Changes")
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(AppColor.accent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quizSetup.save")
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.vertical, Theme.Spacing.m)
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
