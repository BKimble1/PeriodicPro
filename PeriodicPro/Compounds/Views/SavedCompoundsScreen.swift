import SwiftUI

/// Everything the learner has kept, and the one place to tidy it up.
///
/// Saved compounds, favorites and every composition they built, in one list.
/// What removal means differs by where the record came from, and the screen
/// says which before it does anything:
///
/// * a bundled compound is removed from the learner's list, never from the
///   catalog — the app's own data is not the learner's to delete, and
///   "remove from saved" was never a claim about whether water exists;
/// * a compound fetched from PubChem is removed from the list and, if nothing
///   else points at it, dropped from the cache too, so it is fetched again
///   the next time it is wanted;
/// * a composition the learner built is deleted outright, because there is
///   nowhere else it exists.
struct SavedCompoundsScreen: View {
    @Environment(CompoundStore.self) private var store: CompoundStore
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(\.dismiss) private var dismiss

    @State private var pendingDeletion: ChemicalCompound?
    @State private var lastRemoved: String?

    private var kept: [ChemicalCompound] { store.keptCompounds(progress: progress) }

    var body: some View {
        NavigationStack {
            Group {
                if kept.isEmpty {
                    EmptyStateView(
                        symbolName: "bookmark",
                        title: "Nothing saved yet",
                        message: "Compounds you save, favorite or build appear here."
                    )
                    .accessibilityIdentifier("saved.empty")
                } else {
                    list
                }
            }
            .background(AppColor.canvas)
            .navigationTitle("Saved Compounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("saved.done")
                }
            }
            .navigationDestination(for: CompoundMatchCandidate.self) { candidate in
                CompoundDetailScreen(candidate: candidate)
            }
            .alert(
                "Delete this composition?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { compound in
                Button("Delete", role: .destructive) { remove(compound) }
                    .accessibilityIdentifier("saved.confirmDelete")
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: { compound in
                Text("\(CompoundFormula.subscripted(compound.formula)) was built here and is not a "
                     + "record from anywhere else, so deleting it removes it for good.")
            }
        }
        .tint(AppColor.accent)
        .accessibilityIdentifier("saved.screen")
    }

    private var list: some View {
        List {
            Section {
                ForEach(kept) { compound in
                    NavigationLink(value: CompoundMatchCandidate(local: compound)) {
                        row(compound)
                    }
                    .accessibilityIdentifier("saved.row.\(compound.id)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            confirm(compound)
                        } label: {
                            Label(compound.isHypothetical ? "Delete" : "Remove", systemImage: "trash")
                        }
                        .accessibilityIdentifier("saved.remove.\(compound.id)")
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            confirm(compound)
                        } label: {
                            Label(compound.isHypothetical ? "Delete composition" : "Remove from saved",
                                  systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text("Removing a bundled compound takes it off this list only. A compound from "
                     + "PubChem is fetched again if you look it up later. A composition you built "
                     + "is deleted for good.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColor.canvas)
        .accessibilityIdentifier("saved.list")
    }

    private func row(_ compound: ChemicalCompound) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(compound.preferredName)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(CompoundFormula.subscripted(compound.formula))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    Text("·")
                        .foregroundStyle(AppColor.tertiaryText)
                    Text(compound.dataSource.displayName)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            if compound.isHypothetical {
                UnverifiedBadge()
            }
            if progress.isCompoundFavorite(compound.id) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.accent)
                    .accessibilityLabel("Favorite")
            }
        }
        .padding(.vertical, 2)
    }

    private func confirm(_ compound: ChemicalCompound) {
        // Only an outright deletion needs confirming. Taking something off a
        // list is undone by putting it back, and asking about it every time
        // would teach the learner to tap through the one question that counts.
        if compound.isHypothetical {
            pendingDeletion = compound
        } else {
            remove(compound)
        }
    }

    private func remove(_ compound: ChemicalCompound) {
        Haptics.tap()
        _ = store.remove(compound, progress: progress)
        lastRemoved = compound.id
        pendingDeletion = nil
    }
}
