import SwiftUI

/// A dictation's polished text with markable words; marking a word or a run opens the
/// "Correct spelling" field under it.
/// Used by the popover's Home card and by the "Fix a word" window.
struct FixWordView: View {
    let text: String
    var fontSize: CGFloat = 13
    /// Lines of text shown before "…"; nil shows all. The popover card shows up to four,
    /// fewer when it has less room, and there the open field is compact (heard
    /// form, spelling box and any warnings), so the fixed-size popover never overflows.
    var maxLines: Int? = nil
    /// Called after an add or a cancel, when the field (and its keyboard focus) goes away.
    var onDone: () -> Void = {}

    @EnvironmentObject private var dictionaryService: DictionaryService
    @State private var pick: WordRange? = nil
    @State private var model: AddToDictionaryModel? = nil
    @State private var lastModel: AddToDictionaryModel? = nil
    @State private var confirmation: String? = nil
    @State private var undoFailed = false
    @FocusState private var fieldFocused: Bool

    /// `pick` and `confirmation` set a starting state for the off-screen render test.
    init(text: String, fontSize: CGFloat = 13, maxLines: Int? = nil, pick: WordRange? = nil, correct: String = "", confirmation: String? = nil,
         onDone: @escaping () -> Void = {}) {
        self.text = text
        self.fontSize = fontSize
        self.maxLines = maxLines
        self.onDone = onDone
        _pick = State(initialValue: pick)
        _confirmation = State(initialValue: confirmation)
        if let pick {
            let m = AddToDictionaryModel(heard: WordPick.text(of: WordPick.tokens(of: text), from: pick.anchor, to: pick.index), service: .shared)
            m.correct = correct
            _model = State(initialValue: m)
        }
    }

    private var tokens: [String] { WordPick.tokens(of: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkableWords(tokens: tokens, fontSize: fontSize, maxLines: maxLines, pick: $pick)
                .id(text)

            if let model {
                Divider()
                FixWordField(model: model, compact: maxLines != nil, focused: $fieldFocused, onSave: save, onCancel: cancel)
            } else if let confirmation {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Label(confirmation, systemImage: undoFailed ? "exclamationmark.circle" : "checkmark")
                        .foregroundStyle(undoFailed ? .orange : .green)
                        .fixedSize(horizontal: false, vertical: true)
                    if lastModel != nil, !undoFailed {
                        Button("Undo", action: undo).buttonStyle(.link)
                    }
                }
                .font(.system(size: 11))
            } else {
                Text("Select the words Dicticus got wrong")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: pick) { _, newPick in
            guard let newPick else { model = nil; return }
            let heard = WordPick.text(of: tokens, from: newPick.anchor, to: newPick.index)
            guard !heard.isEmpty else { model = nil; return }
            let m = AddToDictionaryModel(heard: heard, service: dictionaryService)
            m.correct = model?.correct ?? ""
            model = m
            confirmation = nil
            fieldFocused = true
        }
        .onChange(of: text) { _, _ in
            pick = nil
            model = nil
            confirmation = nil
            lastModel = nil
        }
    }

    private func save() {
        guard let model, let line = model.save() else { return }
        confirmation = line
        undoFailed = false
        lastModel = model
        self.model = nil
        pick = nil
        onDone()
    }

    private func cancel() {
        model = nil
        pick = nil
        onDone()
    }

    private func undo() {
        if lastModel?.undo() == true {
            confirmation = nil
        } else {
            confirmation = "Not undone: the entry was changed since."
            undoFailed = true
        }
        lastModel = nil
    }
}

/// "Heard as" chip and "Correct spelling" field, with the join note and the warnings.
private struct FixWordField: View {
    @ObservedObject var model: AddToDictionaryModel
    /// The popover's form: one row, the heard form's chip then the spelling box, and no note line.
    /// The chip stays because the marked words can sit on a line the text gives up.
    var compact = false
    var focused: FocusState<Bool>.Binding
    var onSave: () -> Void
    var onCancel: () -> Void

    private var heardChip: some View {
        Text("“\(model.heard)”")
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.1)))
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
    }

    private var spellingField: some View {
        TextField(compact ? "Correct spelling" : "Type how it should be written", text: $model.correct)
            .textFieldStyle(.roundedBorder)
            .focused(focused)
            .onSubmit(onSave)
            .onExitCommand(perform: onCancel)
    }

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            if compact {
                GridRow {
                    heardChip.accessibilityLabel("Heard as \(model.heard)")
                    spellingField
                }
            } else {
                GridRow {
                    Text("Heard as").foregroundStyle(.secondary)
                    heardChip
                }
                GridRow {
                    Text("Correct spelling").foregroundStyle(.secondary)
                    spellingField
                }
            }
            if !compact || !model.warnings.isEmpty {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                VStack(alignment: .leading, spacing: 4) {
                    if !compact {
                        Text([model.note, "Return adds · Esc cancels"].filter { !$0.isEmpty }.joined(separator: " "))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(model.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.system(size: 11))
            }
            }
        }
        .font(.system(size: 12))
    }
}

/// Words that can be marked: click marks one, shift-click or a drag across words marks a run.
/// One drag gesture on the whole text handles both, so a click and a drag never compete.
struct MarkableWords: View {
    let tokens: [String]
    var fontSize: CGFloat = 13
    var maxLines: Int? = nil
    @Binding var pick: WordRange?
    @State private var hovered: Int? = nil
    @State private var frames: [Int: CGRect] = [:]

    var body: some View {
        WrappingLayout(spacing: 4, lineSpacing: 3, maxLines: maxLines) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                Text(token)
                    .font(.system(size: fontSize))
                    .padding(.horizontal, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(pick?.contains(index) == true ? 0.25 : (hovered == index ? 0.1 : 0)))
                    )
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[index] = $0 }
                    .onHover { inside in hovered = inside ? index : (hovered == index ? nil : hovered) }
            }
            if maxLines != nil {
                Text("…").font(.system(size: fontSize)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .coordinateSpace(.named(Self.space))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    guard hypot(value.translation.width, value.translation.height) > 3,
                          let start = index(at: value.startLocation) ?? nearestIndex(to: value.startLocation),
                          let current = index(at: value.location) ?? nearestIndex(to: value.location) else { return }
                    pick = WordRange(anchor: start, index: current)
                }
                .onEnded { value in
                    guard hypot(value.translation.width, value.translation.height) <= 3,
                          let index = index(at: value.startLocation) else { return }
                    if NSEvent.modifierFlags.contains(.shift), let current = pick {
                        pick = WordRange(anchor: current.anchor, index: index)
                    } else {
                        pick = WordRange(anchor: index, index: index)
                    }
                }
        )
    }

    private static let space = "markableWords"

    /// Words cut off by `maxLines` are placed with zero size and never picked.
    private var shownFrames: [Int: CGRect] { frames.filter { !$0.value.isEmpty } }

    private func index(at point: CGPoint) -> Int? {
        shownFrames.first { $0.value.insetBy(dx: -2, dy: -2).contains(point) }?.key
    }

    /// While dragging past the end of a line, the word closest to the pointer.
    private func nearestIndex(to point: CGPoint) -> Int? {
        shownFrames.min { a, b in
            hypot(a.value.midX - point.x, a.value.midY - point.y) < hypot(b.value.midX - point.x, b.value.midY - point.y)
        }?.key
    }
}

/// A pick of tokens: the first-clicked word and the word clicked last (with Shift).
struct WordRange: Equatable {
    var anchor: Int
    var index: Int
    var lo: Int { min(anchor, index) }
    var hi: Int { max(anchor, index) }
    func contains(_ i: Int) -> Bool { (lo...hi).contains(i) }
}
