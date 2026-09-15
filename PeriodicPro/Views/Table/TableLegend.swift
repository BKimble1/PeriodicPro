import SwiftUI

/// Compact color key. Each row is tappable and filters the table, so the
/// legend does real work instead of just taking up space.
struct TableLegend: View {
    @Binding var filter: ElementFilter
    let catalog: ElementCatalog

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.m, alignment: .leading),
        GridItem(.flexible(), spacing: Theme.Spacing.m, alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Families")
                .font(AppFont.footnote.weight(.semibold))
                .foregroundStyle(AppColor.secondaryText)
                .textCase(.uppercase)
                .kerning(0.5)

            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(ElementCategory.displayOrder) { category in
                    legendRow(category)
                }
            }
        }
    }

    private func legendRow(_ category: ElementCategory) -> some View {
        let isSelected = filter.categories == [category]
        return Button {
            Haptics.tap()
            withAnimation(Theme.Motion.soft) {
                filter = isSelected ? .all : ElementFilter(family: nil, categories: [category])
            }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(category.tileFill)
                        .frame(width: 16, height: 16)
                    Image(systemName: category.glyph)
                        .font(.system(size: 6))
                        .foregroundStyle(category.accentColor)
                }
                Text(category.shortName)
                    .font(AppFont.caption)
                    .foregroundStyle(isSelected ? AppColor.primaryText : AppColor.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppColor.surfaceMuted : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.pluralName), \(catalog.count(of: category)) elements")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
