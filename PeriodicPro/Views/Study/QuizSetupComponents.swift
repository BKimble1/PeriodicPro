import SwiftUI

/// One block of the quiz setup: a question, and the answers to it.
struct QuizSetupSection<Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                if let detail {
                    Text(detail)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A large, obviously tappable choice: icon over label, accent border and a
/// checkmark when it is the one selected.
///
/// Deliberately not a segmented control. "Compounds", "Not yet mastered" and
/// "Recently missed" do not fit in a segment on a 375-point screen without
/// being shrunk to something nobody can read.
struct QuizOptionCard: View {
    let title: String
    var symbolName: String?
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .footnote) private var labelHeight: CGFloat = 34

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: Theme.Spacing.s) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isSelected ? AppColor.accent : AppColor.secondaryText)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    // A reserved two-line area, so a one-word option is
                    // exactly as tall as a two-word one and the row of cards
                    // sits on one baseline.
                    .frame(maxWidth: .infinity)
                    .frame(height: labelHeight, alignment: .top)
            }
            .padding(.vertical, Theme.Spacing.m)
            .padding(.horizontal, Theme.Spacing.s)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isSelected ? AppColor.accent.opacity(0.10) : AppColor.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(isSelected ? AppColor.accent : AppColor.hairline,
                                  lineWidth: isSelected ? 2 : 0.8)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.accent)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// A full-width choice with a title and, when it is the selected one, a single
/// sentence saying what it means.
struct QuizOptionRow: View {
    let title: String
    let detail: String
    let symbolName: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.secondaryText)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .multilineTextAlignment(.leading)
                    // Only the selected option explains itself. Five
                    // explanations at once is the settings database this
                    // screen used to be.
                    if isSelected {
                        Text(detail)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.hairline)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Theme.minimumTouchTarget)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isSelected ? AppColor.accent.opacity(0.08) : AppColor.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(isSelected ? AppColor.accent : AppColor.hairline,
                                  lineWidth: isSelected ? 1.6 : 0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "\(title). \(detail)" : title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}
