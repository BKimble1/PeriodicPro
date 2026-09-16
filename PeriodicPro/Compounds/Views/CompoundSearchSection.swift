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

            if model.askedRemote {
                Text("Online compound searches are sent to PubChem.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.compounds")
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
