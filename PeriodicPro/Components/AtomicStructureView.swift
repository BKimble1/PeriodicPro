import SwiftUI

/// A Bohr-style shell diagram drawn entirely with SwiftUI shapes.
///
/// This is an educational simplification, not a physical picture: electrons do
/// not follow fixed circular paths. The caption shown alongside it on the
/// detail screen says so explicitly.
struct AtomicStructureView: View {
    let element: ChemicalElement
    var diameter: CGFloat = 188
    /// Identify mode turns this off: there the diagram *is* the question, and a
    /// symbol in the nucleus would print the answer in the middle of it.
    var showsSymbol: Bool = true
    /// Overrides the family accent. Identify mode passes a neutral color for
    /// the same reason it hides the symbol: the palette is a legend the app
    /// teaches on page one, so a lavender nucleus narrows 118 candidates to
    /// seven before the learner has counted a single shell.
    var tint: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shells: [Int] { element.shellElectrons.filter { $0 > 0 } }

    private var drawingTint: Color { tint ?? element.category.accentColor }
    /// `AppColor.surface` is white on light and near-black on dark, so it reads
    /// against the neutral nucleus as well as the family's own ink does.
    private var symbolTint: Color {
        tint == nil ? element.category.onAccentColor : AppColor.surface
    }

    private var nucleusDiameter: CGFloat { diameter * 0.235 }
    private var innerRadius: CGFloat { diameter * 0.185 }
    private var outerRadius: CGFloat { diameter * 0.46 }

    private func radius(for index: Int) -> CGFloat {
        guard shells.count > 1 else { return outerRadius }
        let step = (outerRadius - innerRadius) / CGFloat(shells.count - 1)
        return innerRadius + step * CGFloat(index)
    }

    var body: some View {
        ZStack {
            ForEach(Array(shells.indices), id: \.self) { index in
                ShellRing(
                    electronCount: shells[index],
                    radius: radius(for: index),
                    tint: drawingTint,
                    period: 26 + Double(index) * 9,
                    clockwise: index.isMultiple(of: 2),
                    animates: !reduceMotion
                )
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            drawingTint.opacity(0.95),
                            drawingTint.opacity(0.62),
                        ],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 1,
                        endRadius: nucleusDiameter
                    )
                )
                .frame(width: nucleusDiameter, height: nucleusDiameter)
                .overlay {
                    if showsSymbol {
                        Text(element.symbol)
                            .font(.system(size: nucleusDiameter * 0.44, weight: .semibold))
                            .foregroundStyle(symbolTint)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(2)
                    }
                }
                .themeShadow(Theme.Shadow.subtle)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let breakdown = shells.enumerated()
            .map { "shell \($0.offset + 1): \($0.element)" }
            .joined(separator: ", ")
        let subject = showsSymbol ? element.name : "an unnamed element"
        return "Simplified shell diagram for \(subject). "
            + "\(shells.count) electron shells. \(breakdown)."
    }
}

/// One electron shell: a hairline circle plus evenly spaced electrons that
/// drift slowly around it.
private struct ShellRing: View {
    let electronCount: Int
    let radius: CGFloat
    let tint: Color
    let period: Double
    let clockwise: Bool
    let animates: Bool

    @State private var angle: Double = 0

    /// Electrons are sized from the space actually available on the ring so
    /// heavy elements stay legible instead of turning into a solid band.
    private var electronDiameter: CGFloat {
        let circumference = 2 * .pi * radius
        let available = circumference / CGFloat(max(electronCount, 1))
        return max(2.0, min(5.5, available * 0.42))
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.75)
                .frame(width: radius * 2, height: radius * 2)

            ForEach(0..<electronCount, id: \.self) { index in
                Circle()
                    .fill(tint)
                    .frame(width: electronDiameter, height: electronDiameter)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(index) / Double(electronCount) * 360))
            }
            .rotationEffect(.degrees(clockwise ? angle : -angle))
        }
        .onAppear { updateSpin() }
        // Reduce Motion can be turned on while a diagram is on screen. The ring
        // keeps its identity, so onAppear never fires again and the in-flight
        // repeatForever animation would otherwise run on regardless.
        .onChange(of: animates) { _, _ in updateSpin() }
        .onDisappear { withAnimation(nil) { angle = 0 } }
    }

    private func updateSpin() {
        guard animates else {
            // Re-assigning without an animation is what actually cancels a
            // repeatForever; simply not starting a new one does nothing.
            withAnimation(nil) { angle = 0 }
            return
        }
        // Reset first: on a second appearance `angle` is already 360, and
        // animating to the value it already holds is a no-op that leaves the
        // electrons frozen. 0 and 360 look identical, so there is no visible
        // jump.
        withAnimation(nil) { angle = 0 }
        withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
            angle = 360
        }
    }
}
