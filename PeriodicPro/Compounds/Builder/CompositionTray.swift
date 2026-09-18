import SwiftUI

/// The elements in the builder and how many of each.
///
/// One compact row per element: the symbol tile, the name on a single line,
/// and a stepper. The old row carried the tile, the name *and* the family on
/// two lines, then three 44-point buttons — which on an iPhone SE left the
/// name about sixty points and wrapped "Post-Transition Metal" into a
/// three-line card. The family is not what the learner is editing here; the
/// count is.
struct CompositionTray: View {
    let entries: [CompoundBuilderModel.Entry]
    let canAddElement: Bool
    let onIncrement: (Int) -> Void
    let onDecrement: (Int) -> Void
    /// Typing a count directly, which is the only way C₂₇H₄₆O is reasonable
    /// to enter: forty-six taps is not an interface.
    let onSetCount: (Int, Int) -> Void
    let onRemove: (Int) -> Void
    let onAdd: () -> Void
    let onClear: () -> Void

    /// The entry whose count is being typed, and what has been typed so far.
    @State private var editing: CompoundBuilderModel.Entry?
    @State private var typed = ""

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Build a composition")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppColor.primaryText)
                    Spacer(minLength: Theme.Spacing.s)
                    if !entries.isEmpty {
                        Button("Clear", action: onClear)
                            .font(.system(.footnote, weight: .medium))
                            .foregroundStyle(AppColor.secondaryText)
                            .frame(minHeight: Theme.minimumTouchTarget)
                            .accessibilityIdentifier("build.clear")
                    }
                }

                if entries.isEmpty {
                    Text("Add elements and Elemora identifies the composition as you go — "
                         + "its own catalog first, then PubChem.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("build.empty")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider().overlay(AppColor.hairline)
                            }
                            row(entry)
                        }
                    }
                }

                Button(action: onAdd) {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "plus.circle.fill")
                        Text(entries.isEmpty ? "Add an element" : "Add another element")
                    }
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(canAddElement ? AppColor.accent : AppColor.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(AppColor.accent.opacity(canAddElement ? 0.10 : 0.04))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canAddElement)
                .accessibilityIdentifier("build.addElement")

                if !canAddElement {
                    Text("Up to \(CompoundBuilderModel.maximumDistinctElements) different elements "
                         + "in one composition.")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build.tray")
        .alert("How many \(editing?.element.name.lowercased() ?? "atoms")?",
               isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            // No identifier on the field. SwiftUI hands an alert's contents to
            // a UIAlertController, which takes a button's accessibility
            // identifier and drops a text field's — the identifier compiles,
            // reads as if it works, and never reaches the accessibility tree.
            // The alert has exactly one field, so that is how a test names it.
            TextField("Count", text: $typed)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) { editing = nil }
            Button("Set") { commitTypedCount() }
                .accessibilityIdentifier("build.countConfirm")
        } message: {
            Text("Between 1 and \(CompoundBuilderModel.maximumCountPerElement).")
        }
    }

    private func commitTypedCount() {
        defer { editing = nil }
        guard let entry = editing, let count = CompoundBuilderModel.parseCount(typed) else { return }
        Haptics.tap()
        onSetCount(entry.element.atomicNumber, count)
    }

    private func row(_ entry: CompoundBuilderModel.Entry) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            ElementTile(element: entry.element, size: 38, density: .minimal)
                .accessibilityHidden(true)

            // One line, always. A long name shrinks a little and then
            // truncates; it never turns the row into a paragraph.
            Text(entry.element.name)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(AppColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)

            Spacer(minLength: Theme.Spacing.xs)

            stepper(entry)

            Button {
                Haptics.tap()
                onRemove(entry.element.atomicNumber)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColor.tertiaryText)
                    .frame(width: 30, height: Theme.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(entry.element.name.lowercased())")
            .accessibilityIdentifier("build.remove.\(entry.element.symbol)")
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entry.count) \(entry.element.name)")
    }

    /// Minus, the count, plus — one capsule, so the controls read as a single
    /// thing that changes one number rather than three loose buttons.
    ///
    /// The count in the middle is a button. Tapping it types the number
    /// instead of counting to it, and holding either end runs the count up or
    /// down, so an alkane's worth of hydrogens is a moment's work either way.
    private func stepper(_ entry: CompoundBuilderModel.Entry) -> some View {
        HStack(spacing: 0) {
            RepeatingStepButton(
                symbol: "minus",
                label: "Remove one \(entry.element.name.lowercased())",
                identifier: "build.decrement.\(entry.element.symbol)"
            ) {
                onDecrement(entry.element.atomicNumber)
            }

            Button {
                Haptics.tap()
                typed = "\(entry.count)"
                editing = entry
            } label: {
                Text("\(entry.count)")
                    .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 34)
                    .frame(height: Theme.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.count) \(entry.element.name)")
            .accessibilityHint("Type a different count")
            .accessibilityIdentifier("build.count.\(entry.element.symbol)")

            RepeatingStepButton(
                symbol: "plus",
                label: "Add one more \(entry.element.name.lowercased())",
                identifier: "build.increment.\(entry.element.symbol)"
            ) {
                onIncrement(entry.element.atomicNumber)
            }
        }
        .frame(height: 38)
        .background { Capsule().fill(AppColor.accent.opacity(0.10)) }
    }
}

/// A stepper end that fires once on a tap and keeps firing while held.
///
/// Built from a drag gesture with no movement threshold rather than a
/// `LongPressGesture`, so the press is known to have started and ended; a long
/// press only reports that it succeeded, which cannot stop a repeat.
private struct RepeatingStepButton: View {
    let symbol: String
    let label: String
    let identifier: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var repeater: Task<Void, Never>?
    @State private var isPressed = false

    /// How long a press has to be held before it starts repeating, and how
    /// fast it repeats once it does — slow to begin with, then quicker, so a
    /// short hold is precise and a long one covers ground.
    private static let holdDelay = Duration.milliseconds(450)
    private static let startingInterval = Duration.milliseconds(140)
    private static let fastestInterval = Duration.milliseconds(35)

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppColor.accent)
            .frame(width: 38, height: Theme.minimumTouchTarget)
            .contentShape(Rectangle())
            .scaleEffect(isPressed && !reduceMotion ? 0.86 : 1)
            .animation(Theme.Motion.tap, value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in start() }
                    .onEnded { _ in stop() }
            )
            .onDisappear { stop() }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
            .accessibilityAction { action() }
    }

    private func start() {
        guard repeater == nil else { return }
        isPressed = true
        Haptics.tap()
        action()
        repeater = Task { @MainActor in
            try? await Task.sleep(for: Self.holdDelay)
            var interval = Self.startingInterval
            while !Task.isCancelled {
                action()
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                // Accelerate toward the floor: about a second of holding gets
                // from one a tap to a hundred a second.
                interval = max(Self.fastestInterval, interval * 0.82)
            }
        }
    }

    private func stop() {
        repeater?.cancel()
        repeater = nil
        isPressed = false
    }
}

/// Picks one element for the tray: the full catalog, searchable by name,
/// symbol or number.
struct ElementPickerSheet: View {
    let catalog: ElementCatalog
    let onPick: (ChemicalElement) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [ChemicalElement] {
        query.isEmpty ? catalog.elements : catalog.search(query, limit: 118)
    }

    var body: some View {
        NavigationStack {
            List(results) { element in
                Button {
                    Haptics.tap()
                    onPick(element)
                    dismiss()
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        ElementTile(element: element, size: 40, density: .standard)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(element.name)
                                .font(.system(.body, weight: .medium))
                                .foregroundStyle(AppColor.primaryText)
                            Text("\(element.category.displayName) · Number \(element.atomicNumber)")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        // Stretches the label across the row. Without it the
                        // tap area ended with the text, and on an iPad's wide
                        // form sheet a tap in the middle of the row hit nothing.
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(element.accessibilityDescription)
                .accessibilityIdentifier("build.pick.\(element.symbol)")
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Element, symbol, or number")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle("Add an element")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("build.pickerCancel")
                }
            }
        }
        .tint(AppColor.accent)
        .presentationDetents([.large])
    }
}
