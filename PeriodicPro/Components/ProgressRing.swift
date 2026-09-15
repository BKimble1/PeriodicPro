import SwiftUI

/// Tasteful progress ring used for overall mastery.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10
    var diameter: CGFloat = 116
    var tint: Color = AppColor.positive
    var centerTitle: String
    var centerCaption: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var typeScale: CGFloat = 1
    @State private var animatedProgress: Double = 0

    private var clamped: Double { min(max(progress, 0), 1) }

    /// The ring grows with Dynamic Type so the number inside keeps its
    /// proportion of the circle, capped so it never swallows the screen.
    private var scale: CGFloat { min(max(typeScale, 1), 1.55) }
    private var scaledDiameter: CGFloat { diameter * scale }
    private var scaledLineWidth: CGFloat { lineWidth * scale }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.hairline, lineWidth: scaledLineWidth)

            // No floor on the trim: a round line cap on a zero-length subpath
            // renders as a filled dot, so a brand-new learner would see a solid
            // spot at twelve o'clock instead of an empty track.
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.75), tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: scaledLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(centerTitle)
                    .font(.system(size: scaledDiameter * 0.20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppColor.primaryText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(centerCaption)
                    .font(.system(size: max(9, scaledDiameter * 0.085)))
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(scaledLineWidth * 1.6)
        }
        .frame(width: scaledDiameter, height: scaledDiameter)
        .onAppear {
            if reduceMotion {
                animatedProgress = clamped
            } else {
                withAnimation(.easeOut(duration: 0.85).delay(0.1)) { animatedProgress = clamped }
            }
        }
        .onChange(of: clamped) { _, newValue in
            withAnimation(reduceMotion ? nil : Theme.Motion.reveal) { animatedProgress = newValue }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(centerTitle) \(centerCaption)")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

/// Slim horizontal bar used for per-family progress.
struct CategoryProgressBar: View {
    let category: ElementCategory
    let mastered: Int
    let total: Int

    private var fraction: Double {
        total == 0 ? 0 : Double(mastered) / Double(total)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: category.glyph)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(category.accentColor)
                    .frame(width: 14)
                Text(category.pluralName)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: Theme.Spacing.s)
                Text("\(mastered) / \(total)")
                    .font(.system(.subheadline, weight: .medium).monospacedDigit())
                    .foregroundStyle(AppColor.secondaryText)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.surfaceMuted)
                    Capsule()
                        .fill(category.accentColor)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 6 : 0))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.pluralName)
        .accessibilityValue("\(mastered) of \(total) mastered")
    }
}
