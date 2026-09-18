import SwiftUI

/// The top of the Progress tab: how far through the table the learner is.
///
/// A ring and three numbers, then the rank the score adds up to. Calm rather
/// than celebratory — the numbers are the reward.
struct PeriodicMasteryHero: View {
    let mastered: Int
    let total: Int
    let compoundsStudied: Int
    let recentAccuracy: Double?
    let standing: RankStanding

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { total == 0 ? 0 : Double(mastered) / Double(total) }

    var body: some View {
        CardContainer(padding: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.l) {
                ProgressRing(
                    progress: fraction,
                    lineWidth: 12,
                    diameter: 158,
                    tint: AppColor.positive,
                    centerTitle: "\(mastered)",
                    centerCaption: "of \(total)"
                )
                .accessibilityHidden(true)

                VStack(spacing: Theme.Spacing.xs) {
                    Text("Periodic Mastery")
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)
                    Text(summaryLine)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(AppColor.hairline)

                rankRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.hero")
    }

    private var summaryLine: String {
        var parts = ["\(mastered) of \(total) elements mastered"]
        if compoundsStudied > 0 {
            parts.append("\(compoundsStudied) compound\(compoundsStudied == 1 ? "" : "s") studied")
        }
        if let recentAccuracy {
            parts.append("\(Int((recentAccuracy * 100).rounded()))% recent accuracy")
        }
        return parts.joined(separator: " · ")
    }

    private var rankRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                // A shape as well as a color: the rank is never carried by
                // color alone.
                Image(systemName: standing.rank.symbolName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(standing.rank.title)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)
                    Text(standing.rank.summary)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if let next = standing.rank.next {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: standing.progressToNext)
                        .tint(AppColor.accent)
                    Text("Next: \(next.title). The most room left is in \(standing.weakestComponent).")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Every part of the table, the compounds and the chemistry underneath.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rank: \(standing.rank.title). \(standing.rank.summary) "
            + (standing.rank.next.map { "Next rank: \($0.title)." } ?? "Highest rank.")
        )
        .accessibilityIdentifier("progress.rank")
    }
}

/// A recommended order through the chemistry — not a gate on it.
struct LearningPathCard: View {
    let steps: [LearningPathStep]
    let onStart: (LearningPathStage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(
                title: "Learning path",
                subtitle: "A suggested order. Nothing is locked — this is where to start, not where you may go."
            )
            CardContainer {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { offset, step in
                        if offset > 0 { Divider().overlay(AppColor.hairline) }
                        row(step)
                    }
                }
            }
            // A container, not one element with one name. Without this the
            // card's identifier is applied to every element inside it, so all
            // five path rows come back as "progress.learningPath" and the card
            // itself is not there at all.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("progress.learningPath")
        }
    }

    private func row(_ step: LearningPathStep) -> some View {
        Button {
            Haptics.tap()
            onStart(step.stage)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                ZStack {
                    Circle()
                        .fill(step.isComplete
                              ? AppColor.positive.opacity(0.14)
                              : (step.isCurrent ? AppColor.accent.opacity(0.14) : AppColor.surfaceMuted))
                        .frame(width: 34, height: 34)
                    Image(systemName: step.isComplete ? "checkmark" : step.stage.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(step.isComplete
                                         ? AppColor.positive
                                         : (step.isCurrent ? AppColor.accent : AppColor.tertiaryText))
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(step.stage.title)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        if step.isCurrent {
                            // A word, not a color: "you are here" has to
                            // survive being read aloud and being colorblind.
                            Text("NEXT")
                                .font(.system(size: 9, weight: .bold))
                                .kerning(0.6)
                                .foregroundStyle(AppColor.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background { Capsule().fill(AppColor.accent.opacity(0.12)) }
                        }
                    }
                    Text(step.stage.subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .lineLimit(1)
                    if !step.detail.isEmpty {
                        Text(step.detail)
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.tertiaryText)
                    }
                }

                Spacer(minLength: Theme.Spacing.s)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(step.stage.title). \(step.stage.subtitle). \(step.detail)"
            + (step.isComplete ? " Complete." : (step.isCurrent ? " Next up." : ""))
        )
        .accessibilityHint("Starts \(step.stage.recommendedMode.title)")
        .accessibilityIdentifier("progress.path.\(step.stage.rawValue)")
    }
}

/// Families, with what is mastered, how accurate, and what is due.
struct FamilyMasteryCard: View {
    struct Row: Identifiable, Equatable, Sendable {
        let category: ElementCategory
        let mastered: Int
        let total: Int
        let accuracy: Double?
        let due: Int

        var id: String { category.rawValue }
    }

    let rows: [Row]
    let onReview: (ElementCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "By family", subtitle: "Tap a family to review it")
            CardContainer {
                VStack(spacing: Theme.Spacing.l) {
                    ForEach(rows) { row in
                        Button {
                            Haptics.tap()
                            onReview(row.category)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                CategoryProgressBar(
                                    category: row.category,
                                    mastered: row.mastered,
                                    total: row.total
                                )
                                if let detail = detail(row) {
                                    Text(detail)
                                        .font(AppFont.caption2)
                                        .foregroundStyle(AppColor.tertiaryText)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("progress.family.\(row.category.rawValue)")
                    }
                }
            }
            // As above: without `children: .contain` this name lands on all ten
            // family rows and overwrites each row's own, which is how
            // `progress.family.alkaliMetal` came back as "never appeared" from
            // a screen it was on.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("progress.byFamily")
        }
    }

    private func detail(_ row: Row) -> String? {
        var parts: [String] = []
        if let accuracy = row.accuracy {
            parts.append("\(Int((accuracy * 100).rounded()))% accuracy")
        }
        if row.due > 0 {
            parts.append("\(row.due) due for review")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
