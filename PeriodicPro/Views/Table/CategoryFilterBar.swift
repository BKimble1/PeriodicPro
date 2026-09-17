import SwiftUI

/// The four primary filters, across the width of the screen.
///
/// All, Metals, Nonmetals and Metalloids — no more, and no horizontal scroll.
/// Detailed family filtering is the Families card under the table
/// (`TableLegend`), which is the only place that state is set or shown, so a
/// detailed selection never adds a fifth control here.
///
/// Four columns at normal text sizes; two rows of two once a quarter of the
/// width can no longer hold "Metalloids" without shrinking it to nothing.
struct CategoryFilterBar: View {
    @Binding var filter: ElementFilter

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One row of four, or a 2×2 block at accessibility text sizes.
    private var columns: [GridItem] {
        let item = GridItem(.flexible(), spacing: Theme.Spacing.s)
        return dynamicTypeSize.isAccessibilitySize ? [item, item] : [item, item, item, item]
    }

    /// True when the broad family chip for `family` is the active filter. A
    /// detailed selection from the Families card leaves all four unselected —
    /// that state belongs to the card, which shows it.
    private func isSelected(_ family: ElementFamily) -> Bool {
        filter.family == family && filter.categories.isEmpty
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.s) {
            control(title: "All", isSelected: !filter.isActive) {
                filter = .all
            }
            ForEach(ElementFamily.allCases) { family in
                control(title: family.displayName, isSelected: isSelected(family)) {
                    filter = isSelected(family) ? .all : ElementFilter(family: family, categories: [])
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table.primaryFilters")
    }

    private func control(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            withAnimation(Theme.Motion.soft) { action() }
        } label: {
            Text(title)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : AppColor.primaryText)
                // One line at normal sizes: the four titles are short, and the
                // smallest of the three phone widths still gives each of them
                // about eighty points. It shrinks a little before it truncates.
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, Theme.Spacing.s)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.minimumTouchTarget)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? AppColor.accent : AppColor.surface)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? .clear : AppColor.hairline, lineWidth: 0.8)
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("filter.\(title.replacingOccurrences(of: " ", with: ""))")
    }
}
