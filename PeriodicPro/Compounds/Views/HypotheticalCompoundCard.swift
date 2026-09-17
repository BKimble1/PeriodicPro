import Foundation
import Observation
import SwiftUI

/// Re-asks PubChem about a composition the learner saved when nothing matched.
///
/// A miss is a fact about a database on a day, not about chemistry. PubChem
/// gains records, and a composition that matched nothing in March may match
/// something in September — so the saved record carries a button that asks
/// again rather than being frozen at the answer it got.
///
/// A find never overwrites what the learner saved. It is offered, named, and
/// replaces the saved record only if they say so.
@MainActor
@Observable
final class HypotheticalRecheckModel {
    enum State: Equatable, Sendable {
        case idle
        case checking
        /// Asked again, and PubChem still has nothing with this formula.
        case stillUnmatched
        /// One or more records now match.
        case found([CompoundMatchCandidate])
        /// The question could not be put — which is not an answer to it.
        case failed(String)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var task: Task<Void, Never>?

    var isChecking: Bool { state == .checking }

    func check(_ compound: ChemicalCompound, store: CompoundStore) {
        task?.cancel()
        guard store.isOnlineLookupEnabled else {
            state = .failed(PubChemError.offline.userMessage)
            return
        }
        state = .checking
        let formula = compound.hillFormula
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let local = store.localCandidates(hillFormula: formula)
                let page = try await store.remoteCandidates(hillFormula: formula)
                guard !Task.isCancelled else { return }
                var seen = Set<String>()
                let matches = (local + page.candidates).filter { seen.insert($0.id).inserted }
                self.state = matches.isEmpty ? .stillUnmatched : .found(matches)
            } catch let error as PubChemError {
                guard !Task.isCancelled, error != .canceled else { return }
                self.state = error == .notFound ? .stillUnmatched : .failed(error.userMessage)
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(PubChemError.malformed("").userMessage)
            }
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        state = .idle
    }

    /// Waits for a check in flight. For tests; see `CompoundBuilderModel`.
    func waitForPendingCheck() async {
        await task?.value
    }
}

/// What the app can honestly say about a composition it could not verify.
///
/// The wording is the point of this view. "No match" is a statement about
/// Elemora's catalog and PubChem on the day it was asked; it is never
/// rendered as "this compound does not exist", and nothing here invents a
/// name, a structure, a property or a use to fill the gap. What is shown is
/// what the composition itself determines: the formula, the atom counts and
/// the molar mass the standard atomic weights give it.
struct UnverifiedCompositionCard: View {
    let compound: ChemicalCompound
    let recheck: HypotheticalRecheckModel
    let onCheckAgain: () -> Void
    let onReplace: (CompoundMatchCandidate) -> Void
    let onDelete: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Unverified composition")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppColor.primaryText)
                    UnverifiedBadge()
                }

                Text("No matching compound was found in Elemora or PubChem when this was saved. "
                     + "That does not establish that the composition is impossible or novel — only "
                     + "that neither source had a record for it.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Nothing on this page is inferred beyond the composition itself: the formula, "
                     + "how many of each atom, and the molar mass those atoms add up to.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(AppColor.hairline)

                recheckSection

                Button(role: .destructive, action: onDelete) {
                    Label("Delete composition", systemImage: "trash")
                        .font(.system(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.warning)
                .accessibilityIdentifier("compound.deleteComposition")
            }
        }
        .accessibilityIdentifier("compound.unverifiedCard")
    }

    @ViewBuilder
    private var recheckSection: some View {
        switch recheck.state {
        case .idle, .checking:
            Button(action: onCheckAgain) {
                HStack(spacing: Theme.Spacing.s) {
                    if recheck.isChecking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    Text(recheck.isChecking ? "Asking PubChem…" : "Check PubChem again")
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(AppColor.accent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.minimumTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(recheck.isChecking)
            .accessibilityIdentifier("compound.checkAgain")

        case .stillUnmatched:
            Text("Asked again just now: PubChem still has no record with this formula.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("compound.stillUnmatched")

        case .failed(let message):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("PubChem could not be reached, so nothing was learned either way.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                Button("Try again", action: onCheckAgain)
                    .font(AppFont.caption.weight(.semibold))
                    .accessibilityIdentifier("compound.checkAgainRetry")
            }
            .accessibilityIdentifier("compound.checkFailed")

        case .found(let matches):
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(matches.count == 1
                     ? "A verified record with this formula exists now."
                     : "\(matches.count) verified records with this formula exist now.")
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your saved composition has not been changed. Replacing it swaps in the verified "
                     + "record and keeps its place in Study.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(matches.prefix(6)) { match in
                    Button {
                        Haptics.tap()
                        onReplace(match)
                    } label: {
                        HStack(spacing: Theme.Spacing.s) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(match.name)
                                    .font(.system(.subheadline, weight: .medium))
                                    .foregroundStyle(AppColor.primaryText)
                                    .lineLimit(1)
                                Text(match.displayFormula)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.secondaryText)
                            }
                            Spacer(minLength: Theme.Spacing.s)
                            Text("Replace")
                                .font(AppFont.caption.weight(.semibold))
                                .foregroundStyle(AppColor.accent)
                        }
                        .frame(minHeight: Theme.minimumTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("compound.replaceWith.\(match.cid)")
                }
            }
        }
    }
}
