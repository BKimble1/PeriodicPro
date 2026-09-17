import SwiftUI

/// The live formula, and what is known about it.
///
/// The visual center of the builder. The formula updates on every atom added
/// or removed; underneath it, one line says what the app currently knows —
/// checking, matched, several matches, no match, or could not ask — and the
/// name shown is always a record's name. Nothing here is derived from
/// stoichiometry: a formula with no match says so.
struct BuilderIdentityCard: View {
    let formula: String
    let hillFormula: String
    let molarMass: Double?
    let atomCount: Int
    let state: CompoundBuilderModel.LookupState
    let statusMessage: String?
    let onChoose: (CompoundMatchCandidate) -> Void
    let onOpenDetails: (ChemicalCompound) -> Void
    let onSaveHypothetical: () -> Void
    let onRetry: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text(formula)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.primaryText)
                    .minimumScaleFactor(0.4)
                    .lineLimit(2)
                    .accessibilityLabel("Formula " + CompoundFormula.spoken(hillFormula))
                    .accessibilityIdentifier("build.formula")

                HStack(spacing: Theme.Spacing.l) {
                    fact("Hill formula", hillFormula, monospaced: true)
                    if let molarMass {
                        fact("Molar mass", "\((molarMass * 100).rounded() / 100) g/mol",
                             identifier: "build.molarMass")
                    }
                    fact("Atoms", "\(atomCount)")
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                Divider().overlay(AppColor.hairline)

                identity
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build.identity")
    }

    // MARK: - Identity

    @ViewBuilder
    private var identity: some View {
        switch state {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: Theme.Spacing.s) {
                ProgressView().controlSize(.small)
                Text(statusMessage ?? "Checking known compounds…")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .frame(minHeight: Theme.minimumTouchTarget, alignment: .leading)
            .accessibilityIdentifier("build.searching")
        case .matched(let compound), .hypothetical(let compound):
            matchRow(compound)
        case .choices(let candidates):
            candidateList(candidates)
        case .noMatch:
            noMatch
        case .failed(let message):
            failure(message)
        }
    }

    private func matchRow(_ compound: ChemicalCompound) -> some View {
        Button {
            Haptics.tap()
            onOpenDetails(compound)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(compound.preferredName)
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let statusMessage {
                        Text(statusMessage)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.tertiaryText)
            }
            .frame(minHeight: Theme.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(compound.preferredName). Open details")
        .accessibilityIdentifier("build.identity.match")
    }

    private func candidateList(_ candidates: [CompoundMatchCandidate]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(statusMessage ?? "\(candidates.count) known compounds share this formula")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(AppColor.primaryText)
                .accessibilityIdentifier("build.identity.ambiguous")
            Text("A formula gives the atoms, not how they are joined. Choose the compound you mean.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(candidates) { candidate in
                Button {
                    Haptics.tap()
                    onChoose(candidate)
                } label: {
                    CompoundRow(candidate: candidate)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("build.candidate.\(candidate.cid)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build.candidates")
    }

    private var noMatch: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("No known match found")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(AppColor.primaryText)
            Text("This composition may be hypothetical, unstable, unindexed, or otherwise unknown. "
                 + "A database miss is not evidence of a new chemical discovery.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                onSaveHypothetical()
            } label: {
                Text("Save as hypothetical composition")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(AppColor.accent.opacity(0.10))
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("build.saveHypothetical")
            Text("Saved with its formula and molar mass only. No name, structure or property is invented.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build.noMatch")
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Could not check PubChem")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(AppColor.primaryText)
            Text(message)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Nothing has been decided about this composition: the catalog has no match and "
                 + "PubChem could not be asked.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Search this formula again", action: onRetry)
                .font(.system(.subheadline, weight: .semibold))
                .frame(minHeight: Theme.minimumTouchTarget)
                .accessibilityIdentifier("build.retry")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build.failed")
    }

    private func fact(
        _ label: String,
        _ value: String,
        monospaced: Bool = false,
        identifier: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.tertiaryText)
            Text(value)
                .font(monospaced
                      ? .system(.footnote, design: .monospaced, weight: .medium)
                      : .system(.footnote, weight: .medium).monospacedDigit())
                .foregroundStyle(AppColor.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier(identifier ?? "")
        }
    }
}
