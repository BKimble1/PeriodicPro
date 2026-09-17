import SwiftUI

/// The compound half of the table's search results.
///
/// Local matches appear as the learner types. PubChem is asked after a pause,
/// and only for something that could be a name; what it adds is marked as
/// coming from PubChem. The section is honest about the network: searching,
/// failed with a retry, or nothing found.
struct CompoundSearchSection: View {
    let model: CompoundSearchModel
    let isFavorite: (String) -> Bool
    let mastery: (String) -> MasteryLevel
    let onSelect: (CompoundMatchCandidate) -> Void
    let onRetry: () -> Void
    /// Fetches the next page of a formula search. Absent on the Table screen,
    /// whose compound section is a short list beneath the elements.
    var onLoadMore: (() -> Void)?
    /// Runs the search again for a suggested name.
    var onPickSuggestion: ((String) -> Void)?
    /// The table lays this out inside a full-bleed scroll view and needs the
    /// page margin; the Build tab has already applied it.
    var horizontalPadding: CGFloat = Theme.Spacing.screenMargin

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Compounds")
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.secondaryText)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
                statusLine
            }
            .padding(.horizontal, Theme.Spacing.xs)

            if let kind = model.recognizedKind {
                // What the app made of what was typed, said out loud: a
                // formula search and a name search return different things,
                // and a learner who pasted a SMILES string should be able to
                // see that it was read as one.
                Label(kind, systemImage: "checkmark.seal")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .accessibilityIdentifier("search.compounds.kind")
            }

            if !model.suggestions.isEmpty, let onPickSuggestion {
                suggestionRow(onPickSuggestion)
            }

            if model.isEmpty {
                emptyLine
            } else {
                LazyVStack(spacing: Theme.Spacing.s) {
                    ForEach(model.allResults) { candidate in
                        Button {
                            Haptics.tap()
                            onSelect(candidate)
                        } label: {
                            CompoundRow(
                                candidate: candidate,
                                isFavorite: isFavorite(candidate.id),
                                mastery: mastery(candidate.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("compoundResult.\(candidate.cid)")
                    }
                }
            }

            if model.hasMore, let onLoadMore {
                Button {
                    Haptics.tap()
                    onLoadMore()
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        if model.isLoadingMore {
                            ProgressView().controlSize(.mini)
                        }
                        Text(model.isLoadingMore ? "Loading…" : "Load more matches")
                    }
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.minimumTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingMore)
                .accessibilityIdentifier("search.compounds.loadMore")
            }

            if model.askedRemote {
                Text("Online compound searches are sent to PubChem.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.compounds")
    }

    /// PubChem's own index terms, offered while the learner is still typing.
    ///
    /// Terms, not records — nothing here claims to be a compound the app has
    /// found. Tapping one runs the ordinary exact lookup for that name.
    private func suggestionRow(_ pick: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(model.suggestions.prefix(10), id: \.self) { term in
                    Button {
                        Haptics.tap()
                        pick(term)
                    } label: {
                        Text(term)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.primaryText)
                            .lineLimit(1)
                            .padding(.horizontal, Theme.Spacing.m)
                            .frame(height: 32)
                            .background { Capsule().fill(AppColor.surfaceMuted) }
                            .overlay { Capsule().strokeBorder(AppColor.hairline, lineWidth: 0.7) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.compounds.suggestion")
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions from PubChem")
        .accessibilityIdentifier("search.compounds.suggestions")
    }

    @ViewBuilder
    private var statusLine: some View {
        switch model.status {
        case .searching:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Searching PubChem…")
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.tertiaryText)
            .accessibilityIdentifier("search.compounds.searching")
        case .failed:
            Button("Retry", action: onRetry)
                .font(AppFont.caption.weight(.semibold))
                .accessibilityIdentifier("search.compounds.retry")
        case .idle, .done:
            EmptyView()
        }
    }

    @ViewBuilder
    private var emptyLine: some View {
        switch model.status {
        case .failed(let message):
            Text(message)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.xs)
                .accessibilityIdentifier("search.compounds.error")
        case .done where model.askedRemote:
            Text("No compounds found for \u{201C}\(model.query)\u{201D}.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
                .padding(.horizontal, Theme.Spacing.xs)
                .accessibilityIdentifier("search.compounds.none")
        case .searching, .idle, .done:
            EmptyView()
        }
    }
}

/// A search field that looks like the one iOS draws, inside ordinary content.
///
/// `.searchable` puts its field in the navigation bar, which is right for the
/// periodic table — search *replaces* that screen. On Build the field is one
/// of two ways in and belongs under the title, next to the thing it is an
/// alternative to.
struct CompoundSearchField: View {
    @Binding var query: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColor.secondaryText)
                .accessibilityHidden(true)

            TextField("Search compounds", text: $query)
                .font(AppFont.body)
                .foregroundStyle(AppColor.primaryText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($isFocused)
                .accessibilityLabel("Search compounds")
                .accessibilityIdentifier("build.search")

            if !query.isEmpty {
                Button {
                    query = ""
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AppColor.tertiaryText)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
                .accessibilityIdentifier("build.searchClear")
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(minHeight: 46)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(AppColor.surfaceMuted)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(AppColor.hairline, lineWidth: 0.7)
        }
    }
}
