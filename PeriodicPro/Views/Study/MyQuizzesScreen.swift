import SwiftUI
import UniformTypeIdentifiers

/// The learner's saved quizzes: start, edit, duplicate, rename, share,
/// import and delete.
struct MyQuizzesScreen: View {
    let onStart: (QuizRoundDealer) -> Void

    @Environment(\.elementCatalog) private var catalog
    @Environment(CompoundStore.self) private var compounds: CompoundStore
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(SavedQuizStore.self) private var savedQuizzes: SavedQuizStore

    @State private var editing: SavedQuiz?
    @State private var isCreating = false
    @State private var renaming: SavedQuiz?
    @State private var renameText = ""
    @State private var isImporting = false
    @State private var pendingDelete: SavedQuiz?

    var body: some View {
        Group {
            if savedQuizzes.quizzes.isEmpty {
                ScrollView {
                    EmptyStateView(
                        symbolName: "list.bullet.rectangle",
                        title: "No saved quizzes yet",
                        message: "Build a quiz from the Quiz tile and tap Save as Quiz, or import one someone "
                            + "shared with you.",
                        actionTitle: "New quiz",
                        action: { isCreating = true }
                    )
                    .padding(.top, Theme.Spacing.xxl)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("myQuizzes.empty")
            } else {
                List {
                    ForEach(savedQuizzes.quizzes) { quiz in
                        row(quiz)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("myQuizzes.list")
            }
        }
        .background(AppColor.canvas)
        .navigationTitle("My Quizzes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isCreating = true
                    } label: {
                        Label("New quiz", systemImage: "plus")
                    }
                    .accessibilityIdentifier("myQuizzes.new")
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import a quiz file", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("myQuizzes.import")
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add a quiz")
                .accessibilityIdentifier("myQuizzes.menu")
            }
        }
        .sheet(isPresented: $isCreating) {
            QuizSetupView(mode: .quiz, onStart: onStart)
        }
        .sheet(item: $editing) { quiz in
            QuizSetupView(mode: .quiz, existing: quiz, onStart: onStart)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.elemoraQuiz, .json]) { result in
            if case .success(let url) = result {
                savedQuizzes.importFile(at: url, catalog: catalog)
            }
        }
        .alert("Rename quiz", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Quiz name", text: $renameText)
                .accessibilityIdentifier("myQuizzes.renameField")
            Button("Save") {
                if let renaming { savedQuizzes.rename(id: renaming.id, to: renameText) }
                renaming = nil
            }
            .accessibilityIdentifier("myQuizzes.renameSave")
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete this quiz?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { savedQuizzes.delete(id: pendingDelete.id) }
                pendingDelete = nil
            }
            .accessibilityIdentifier("myQuizzes.confirmDelete")
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete.map { "\u{201C}\($0.name)\u{201D} will be removed. Your progress is not affected." }
                 ?? "")
        }
    }

    private func row(_ quiz: SavedQuiz) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(quiz.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(2)
                Text(quiz.configuration.summary)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.s)
            Button {
                Haptics.tap()
                start(quiz)
            } label: {
                Text("Start")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.l)
                    .frame(minHeight: 36)
                    .background { Capsule().fill(AppColor.accent) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start \(quiz.name)")
            .accessibilityIdentifier("myQuizzes.start.\(quiz.id.uuidString)")
            Menu {
                Button {
                    editing = quiz
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button {
                    renameText = quiz.name
                    renaming = quiz
                } label: {
                    Label("Rename", systemImage: "textformat")
                }
                Button {
                    savedQuizzes.duplicate(id: quiz.id)
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                ShareLink(item: savedQuizzes.package(for: quiz),
                          preview: SharePreview(quiz.name, image: Image(systemName: "questionmark.circle.fill"))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    pendingDelete = quiz
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColor.secondaryText)
                    .frame(width: Theme.minimumTouchTarget, height: Theme.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More actions for \(quiz.name)")
            .accessibilityIdentifier("myQuizzes.more.\(quiz.id.uuidString)")
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("myQuizzes.row.\(quiz.id.uuidString)")
    }

    private func start(_ quiz: SavedQuiz) {
        let pool = QuizPoolBuilder.subjects(
            for: quiz.configuration,
            catalog: catalog,
            compounds: compounds.allKnownCompounds,
            elementSnapshots: progress.snapshots,
            compoundSnapshots: progress.compoundSnapshots
        )
        guard QuizPoolBuilder.unavailableReason(for: quiz.configuration, poolCount: pool.count) == nil else {
            // A quiz whose scope has run dry (no favorites, nothing missed)
            // opens in the editor, where the footer says exactly why.
            editing = quiz
            return
        }
        onStart(QuizRoundDealer(
            configuration: quiz.configuration,
            subjects: pool,
            elementDistractors: catalog.elements,
            compoundDistractors: compounds.allKnownCompounds.filter { !$0.isHypothetical }
        ))
    }
}
