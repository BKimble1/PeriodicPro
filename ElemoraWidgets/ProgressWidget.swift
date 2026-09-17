import SwiftUI
import WidgetKit

/// How far through the table, at a glance.
///
/// Not interactive: there is nothing here to answer. Tapping it opens Elemora,
/// which is the ordinary behavior for a widget with no buttons.
struct ElemoraProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: ElemoraWidgetKind.progress,
            provider: ElemoraTimelineProvider()
        ) { entry in
            ElemoraProgressView(entry: entry)
                .containerBackground(WidgetPalette.canvas, for: .widget)
        }
        .configurationDisplayName("Progress")
        .description("Elements mastered, your streak, and what is due for review.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ElemoraProgressView: View {
    let entry: ElemoraEntry

    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetProgressSnapshot { entry.snapshot }

    private var fraction: Double {
        guard snapshot.totalElements > 0 else { return 0 }
        return min(1, Double(snapshot.masteredElements) / Double(snapshot.totalElements))
    }

    var body: some View {
        if !entry.isSharedStorageAvailable {
            WidgetMessage(
                symbolName: "exclamationmark.triangle",
                title: "Widget storage unavailable",
                message: "Open Elemora once to set the widget up."
            )
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ring
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(snapshot.masteredElements) of \(snapshot.totalElements)")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(WidgetPalette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("elements mastered")
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.secondaryText)
                        .lineLimit(1)
                }
            }

            Text(snapshot.rankTitle)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(WidgetPalette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            // The streak and the review count, with the symbol carrying the
            // meaning as well as the color.
            HStack(spacing: family == .systemSmall ? 8 : 14) {
                stat(
                    symbolName: "flame.fill",
                    tint: WidgetPalette.gold,
                    value: "\(snapshot.currentStreak)",
                    caption: snapshot.currentStreak == 1 ? "day" : "days"
                )
                stat(
                    symbolName: "clock.arrow.circlepath",
                    tint: WidgetPalette.accent,
                    value: "\(snapshot.dueReviewCount)",
                    caption: "due"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(WidgetPalette.accent.opacity(0.18), lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(fraction, 0.005))
                .stroke(
                    WidgetPalette.accent,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    private func stat(
        symbolName: String, tint: Color, value: String, caption: String
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.caption2)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(WidgetPalette.primaryText)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(WidgetPalette.secondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// One sentence, because the parts read as a list of numbers otherwise.
    private var accessibilityDescription: String {
        let streak = snapshot.currentStreak == 1 ? "1 day" : "\(snapshot.currentStreak) days"
        return """
            \(snapshot.masteredElements) of \(snapshot.totalElements) elements mastered. \
            \(snapshot.rankTitle). \(streak) streak. \
            \(snapshot.dueReviewCount) due for review.
            """
    }
}
