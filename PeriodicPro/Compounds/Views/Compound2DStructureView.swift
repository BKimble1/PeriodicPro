import SwiftUI

/// A compound's flat structure, drawn from its own atoms and bonds.
///
/// One `Canvas`, so it is vector at every size and costs nothing to redraw,
/// and it works the same in the builder's result card and on the compound's
/// detail page. Everything it draws comes from `Compound2DLayout`, which reads
/// the record's real connectivity and coordinates — there is no template, no
/// generated depiction and no molecule this cannot be asked to draw honestly.
///
/// What it is called is decided by the same place: an organic molecule gets a
/// skeletal formula, a small molecule gets a labeled 2D structure, and an
/// ionic or network solid gets its formula unit and a sentence saying why
/// there is no skeleton to draw.
struct Compound2DStructureView: View {
    let drawing: Compound2DDrawing

    @Environment(\.colorScheme) private var colorScheme

    /// Where a bond stops short of a label, as a fraction of the drawing's
    /// shorter side.
    private static let labelInset: CGFloat = 0.055
    /// Half the gap between the two lines of a double bond, same units.
    private static let doubleBondOffset: CGFloat = 0.016

    var body: some View {
        Group {
            if drawing.hasGeometry {
                Canvas(rendersAsynchronously: false) { context, size in
                    draw(in: &context, size: size)
                }
                .accessibilityHidden(true)
            } else {
                formulaUnit
            }
        }
        .accessibilityIdentifier("compound2D.canvas")
    }

    // MARK: - Formula unit

    private var formulaUnit: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(drawing.formula)
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.primaryText)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            if let note = drawing.representation.emptyStateNote {
                Text(note)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Canvas

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let inset = side * 0.08
        let box = CGRect(
            x: (size.width - side) / 2 + inset,
            y: (size.height - side) / 2 + inset,
            width: side - inset * 2,
            height: side - inset * 2
        )
        guard box.width > 1, box.height > 1 else { return }

        func place(_ point: CGPoint) -> CGPoint {
            CGPoint(x: box.minX + point.x * box.width, y: box.minY + point.y * box.height)
        }

        let lineWidth = max(1.4, side * 0.013)
        let gap = side * Self.labelInset
        let offset = side * Self.doubleBondOffset
        let stroke = bondColor

        for bond in drawing.bonds {
            let start = place(bond.from)
            let end = place(bond.to)
            let (from, to) = shortened(
                from: start, to: end,
                startGap: bond.startsAtLabel ? gap : 0,
                endGap: bond.endsAtLabel ? gap : 0
            )
            let direction = normalized(CGPoint(x: to.x - from.x, y: to.y - from.y))
            let perpendicular = CGPoint(x: -direction.y, y: direction.x)

            switch bond.order {
            case 2:
                // Two parallel lines, symmetric about the bond axis, so a
                // double bond is unmistakably not a single one.
                line(&context, from, to, shift: offset, along: perpendicular,
                     width: lineWidth, color: stroke)
                line(&context, from, to, shift: -offset, along: perpendicular,
                     width: lineWidth, color: stroke)
            case 3:
                line(&context, from, to, shift: 0, along: perpendicular,
                     width: lineWidth, color: stroke)
                line(&context, from, to, shift: offset * 1.7, along: perpendicular,
                     width: lineWidth, color: stroke)
                line(&context, from, to, shift: -offset * 1.7, along: perpendicular,
                     width: lineWidth, color: stroke)
            default:
                line(&context, from, to, shift: 0, along: perpendicular,
                     width: lineWidth, color: stroke)
            }
        }

        let labelSize = max(10, side * 0.095)
        for atom in drawing.atoms {
            guard let label = atom.label else { continue }
            let point = place(atom.point)
            // A disc of the backdrop behind the label, so the bonds that reach
            // this atom stop at its glyphs rather than running through them.
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - gap * 0.92, y: point.y - gap * 0.92,
                    width: gap * 1.84, height: gap * 1.84
                )),
                with: .color(backdrop)
            )
            var resolved = context.resolve(
                Text(label).font(.system(size: labelSize, weight: .semibold, design: .rounded))
            )
            resolved.shading = .color(color(for: atom.atomicNumber))
            context.draw(resolved, at: point, anchor: .center)

            if let charge = chargeSymbol(atom.formalCharge) {
                var resolvedCharge = context.resolve(
                    Text(charge).font(.system(size: labelSize * 0.62, weight: .bold, design: .rounded))
                )
                resolvedCharge.shading = .color(color(for: atom.atomicNumber))
                context.draw(
                    resolvedCharge,
                    at: CGPoint(x: point.x + gap * 0.85, y: point.y - gap * 0.75),
                    anchor: .center
                )
            }
        }
    }

    private func line(
        _ context: inout GraphicsContext,
        _ from: CGPoint,
        _ to: CGPoint,
        shift: CGFloat,
        along perpendicular: CGPoint,
        width: CGFloat,
        color: Color
    ) {
        var path = Path()
        path.move(to: CGPoint(x: from.x + perpendicular.x * shift, y: from.y + perpendicular.y * shift))
        path.addLine(to: CGPoint(x: to.x + perpendicular.x * shift, y: to.y + perpendicular.y * shift))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func shortened(
        from: CGPoint, to: CGPoint, startGap: CGFloat, endGap: CGFloat
    ) -> (CGPoint, CGPoint) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.001 else { return (from, to) }
        // Never eat more than a third of the bond from either end, or a short
        // bond between two labeled atoms would disappear entirely.
        let start = min(startGap, length / 3)
        let end = min(endGap, length / 3)
        return (
            CGPoint(x: from.x + dx / length * start, y: from.y + dy / length * start),
            CGPoint(x: to.x - dx / length * end, y: to.y - dy / length * end)
        )
    }

    private func normalized(_ vector: CGPoint) -> CGPoint {
        let length = (vector.x * vector.x + vector.y * vector.y).squareRoot()
        guard length > 0.001 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }

    private func chargeSymbol(_ charge: Int) -> String? {
        switch charge {
        case 0: return nil
        case 1: return "+"
        case -1: return "−"
        case let value where value > 1: return "\(value)+"
        default: return "\(abs(charge))−"
        }
    }

    // MARK: - Ink

    private var bondColor: Color {
        colorScheme == .dark
            ? Color(red: 0.85, green: 0.87, blue: 0.90)
            : Color(red: 0.13, green: 0.16, blue: 0.20)
    }

    /// The backdrop the label discs are filled with. Matches the card these
    /// drawings sit on rather than the page, so the disc is invisible.
    private var backdrop: Color {
        colorScheme == .dark
            ? Color(red: 0.106, green: 0.114, blue: 0.137)
            : .white
    }

    /// Element accents only where they carry information: the heteroatoms a
    /// chemist reads by color. Carbon, hydrogen and everything else are ink.
    private func color(for atomicNumber: Int) -> Color {
        switch atomicNumber {
        case 8: return Color(light: Color(hex: 0xC0392B), dark: Color(hex: 0xFF7A6A))
        case 7: return Color(light: Color(hex: 0x2258C9), dark: Color(hex: 0x74A6FF))
        case 16: return Color(light: Color(hex: 0x9A7B10), dark: Color(hex: 0xE3C94F))
        case 15: return Color(light: Color(hex: 0xC05A16), dark: Color(hex: 0xF2955A))
        case 9, 17: return Color(light: Color(hex: 0x2E7D4F), dark: Color(hex: 0x62D18E))
        case 35: return Color(light: Color(hex: 0x8B3A2E), dark: Color(hex: 0xD98878))
        case 53: return Color(light: Color(hex: 0x6B2E8B), dark: Color(hex: 0xC08BDB))
        default: return bondColor
        }
    }
}

/// The structure drawing with its honest label and one line of explanation.
///
/// Used by the builder's result card and by the compound detail page, so the
/// picture and the words that describe it can never come apart.
struct Compound2DStructureCard: View {
    let compound: ChemicalCompound
    var height: CGFloat = 200
    var showsCaption = true

    @Environment(\.elementCatalog) private var catalog

    private var drawing: Compound2DDrawing {
        Compound2DLayout.drawing(for: compound, catalog: catalog)
    }

    var body: some View {
        let drawing = self.drawing
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Compound2DStructureView(drawing: drawing)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(AppColor.surface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(AppColor.hairline, lineWidth: 0.7)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityDescription(drawing))
                .accessibilityIdentifier("compound2D.view")

            HStack(spacing: Theme.Spacing.s) {
                Text(drawing.representation.label)
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColor.secondaryText)
                    .accessibilityIdentifier("compound2D.label")
                Spacer(minLength: 0)
            }

            if showsCaption {
                Text(drawing.representation.caption)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func accessibilityDescription(_ drawing: Compound2DDrawing) -> String {
        guard drawing.hasGeometry else {
            return "\(drawing.representation.label) for \(compound.preferredName), "
                + CompoundFormula.spoken(compound.formula)
        }
        let doubles = drawing.bonds.filter { $0.order == 2 }.count
        let triples = drawing.bonds.filter { $0.order == 3 }.count
        var parts = [
            "\(drawing.representation.label) for \(compound.preferredName)",
            "\(drawing.atoms.count) drawn atoms",
            "\(drawing.bonds.count) bonds",
        ]
        if doubles > 0 { parts.append("\(doubles) double") }
        if triples > 0 { parts.append("\(triples) triple") }
        return parts.joined(separator: ", ")
    }
}
