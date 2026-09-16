import SwiftUI

/// Results list shown in place of the table while a query is active.
struct SearchResultsView: View {
    let results: [ChemicalElement]
    let query: String
    let namespace: Namespace.ID
    /// When compounds matched, an element miss is not a miss at all, so the
    /// empty state stays quiet.
    var hasCompoundResults = false
    let isFavorite: (Int) -> Bool
    let mastery: (Int) -> MasteryLevel
    let onSelect: (ChemicalElement) -> Void

    var body: some View {
        if results.isEmpty, hasCompoundResults {
            EmptyView()
        } else if results.isEmpty {
            EmptyStateView(
                symbolName: "magnifyingglass",
                title: "No matches for \u{201C}\(query)\u{201D}",
                message: "Try an element name, a chemical symbol such as Fe, an atomic number from 1 to 118, "
                    + "or a compound such as water or NaCl."
            )
            .accessibilityIdentifier("search.emptyState")
        } else {
            LazyVStack(spacing: Theme.Spacing.s) {
                ForEach(results) { element in
                    Button {
                        Haptics.tap()
                        onSelect(element)
                    } label: {
                        SearchResultRow(
                            element: element,
                            isFavorite: isFavorite(element.atomicNumber),
                            mastery: mastery(element.atomicNumber)
                        )
                    }
                    .buttonStyle(.plain)
                    .zoomTransitionSource(id: element.atomicNumber, namespace: namespace)
                    .accessibilityIdentifier("searchResult.\(element.symbol)")
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
    }
}

/// One element in the search results: tile, name, number and family.
private struct SearchResultRow: View {
    let element: ChemicalElement
    let isFavorite: Bool
    let mastery: MasteryLevel

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ElementTile(element: element, size: 52, density: .standard, isFavorite: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(element.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                HStack(spacing: Theme.Spacing.s) {
                    Text("Number \(element.atomicNumber)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    CategoryBadge(category: element.category, compact: true)
                }
            }

            Spacer(minLength: 0)

            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(element.category.accentColor)
            }
            if mastery == .mastered {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.positive)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.tertiaryText)
        }
        .padding(Theme.Spacing.m)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(AppColor.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(AppColor.hairline, lineWidth: 0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(element.accessibilityDescription)
        .accessibilityAddTraits(.isButton)
    }
}

/// Recent searches, shown while the search field is focused but empty.
struct RecentSearchesView: View {
    let terms: [String]
    var onSelect: (String) -> Void
    var onClear: () -> Void

    var body: some View {
        if terms.isEmpty {
            EmptyStateView(
                symbolName: "clock",
                title: "No recent searches",
                message: "Search by name, symbol or atomic number \u{2014} results appear instantly."
            )
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Text("Recent")
                        .font(AppFont.footnote.weight(.semibold))
                        .foregroundStyle(AppColor.secondaryText)
                        .textCase(.uppercase)
                        .kerning(0.5)
                    Spacer()
                    Button {
                        Haptics.tap()
                        onClear()
                    } label: {
                        // The frame has to be inside the label: applied to the
                        // Button it would not extend the hit region.
                        Text("Clear")
                            .font(AppFont.footnote)
                            .padding(.horizontal, Theme.Spacing.s)
                            .frame(minHeight: Theme.minimumTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("search.clearRecents")
                }
                .padding(.horizontal, Theme.Spacing.xs)

                ForEach(terms, id: \.self) { term in
                    Button {
                        onSelect(term)
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: "clock")
                                .font(.system(size: 13))
                                .foregroundStyle(AppColor.tertiaryText)
                            Text(term)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.primaryText)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColor.tertiaryText)
                        }
                        .padding(.vertical, Theme.Spacing.m)
                        .padding(.horizontal, Theme.Spacing.m)
                        .frame(minHeight: Theme.minimumTouchTarget)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(AppColor.surface)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
    }
}
