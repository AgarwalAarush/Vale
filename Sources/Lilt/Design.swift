import SwiftUI
import AppKit
import LiltCore

enum Theme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        }
    }
    static let inkColor = adaptive(0x252629, 0xf0f0ed)
    static let ink = Color(nsColor: inkColor)
    static let muted = Color(nsColor: adaptive(0x67686b, 0xb0b1b8))
    static let accentColor = adaptive(0x5759c6, 0xb9bcff)
    static let accent = Color(nsColor: accentColor)
    static let line = Color(nsColor: adaptive(0xddddd6, 0x363840))
    static let windowBackground = adaptive(0xf7f6f2, 0x18191d)
    static let background = Color(nsColor: windowBackground)
    static let rail = Color(nsColor: adaptive(0xeeede8, 0x141519))
    static let fill = Color(nsColor: adaptive(0xeeede8, 0x292b32))
    static let fillRaised = Color(nsColor: adaptive(0xffffff, 0x22242a))
    static let fillPressed = Color(nsColor: adaptive(0xe2e1da, 0x363840))
    static let action = Color(nsColor: adaptive(0x28292d, 0xecece8))
    static let onAction = Color(nsColor: adaptive(0xffffff, 0x252629))
    static let warning = Color(nsColor: adaptive(0x825010, 0xecc48a))
}
struct QuietField: ViewModifier {
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).padding(.horizontal, 10).padding(.vertical, 8).background(Theme.fill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.7))
    }
}
struct QuietButton: ButtonStyle {
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        ActionFeedback(label: configuration.label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8), isPressed: configuration.isPressed, background: filled ? Theme.fillRaised : Theme.fill, outlined: true)
    }
}
/// Feedback changes only the surface; native Button activation and focus stay intact.
struct ActionButton: ButtonStyle {
    var background: Color = .clear
    var feedback: Color = Theme.ink
    func makeBody(configuration: Configuration) -> some View {
        ActionFeedback(label: configuration.label, isPressed: configuration.isPressed, background: background, feedback: feedback)
    }
}
private struct ActionFeedback<Label: View>: View {
    let label: Label
    let isPressed: Bool
    var background: Color
    var feedback: Color = Theme.ink
    var outlined = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var hovered = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        label
            .contentShape(shape)
            .background {
                shape.fill(background)
                    .overlay(shape.fill(feedback.opacity(isEnabled ? (isPressed ? 0.12 : hovered ? 0.06 : 0) : 0)))
            }
            .overlay(shape.strokeBorder(isEnabled && isFocused ? Theme.accent : outlined ? Theme.line : .clear, lineWidth: isEnabled && isFocused ? 1 : 0.7))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovered = $0 }
    }
}
struct IconButton: View {
    var symbol: String; var label: String; var tint: Color = Theme.muted; var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(tint).frame(width: 30, height: 30) }
            .buttonStyle(ActionButton()).help(label).accessibilityLabel(label)
    }
}
struct LogoMark: View {
    var size: CGFloat = 25
    private static let artwork = Bundle.main.url(forResource: "Vale", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) } ?? NSApp.applicationIconImage!
    var body: some View {
        Image(nsImage: Self.artwork).resizable().interpolation(.high)
            .aspectRatio(contentMode: .fit).frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
struct AudioMark: View {
    var active: Bool
    var body: some View {
        HStack(spacing: 3) { ForEach(Array([9.0,18.0,25.0,15.0,7.0].enumerated()), id: \.offset) { _, value in Capsule().fill(IdleWave.usesAccent(active: active) ? Theme.accent : Theme.muted.opacity(0.35)).frame(width: 3, height: value) } }.frame(width: 29, height: 27).accessibilityHidden(true)
    }
}

final class ComposerTextView: NSTextView {
    var submit: (() -> Void)?
    var escape: (() -> Void)?
    var pasteFiles: (([URL]) -> Void)?
    var pasteImage: ((Data) -> Void)?
    var pastePDF: ((Data) -> Void)?
    var focusChanged: ((Bool) -> Void)?
    private(set) var observedFocus = false
    private var focusObservationPending = false
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { observeFocus() }
        return accepted
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeFocus()
    }
    /// AppKit finishes the responder transition before SwiftUI receives an update.
    /// Coalesce changes and read the current responder, never a queued focus value.
    func observeFocus() {
        guard !focusObservationPending else { return }
        focusObservationPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.focusObservationPending = false
            let focused = self.window?.firstResponder === self
            guard self.observedFocus != focused else { return }
            self.observedFocus = focused
            self.focusChanged?(focused)
        }
    }
    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        let plain = board.string(forType: .string)
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let image = board.data(forType: .png) ?? board.data(forType: .tiff)
            ?? ClipboardImage.attachableJPEG(jpeg: board.data(forType: NSPasteboard.PasteboardType("public.jpeg")), plainText: plain)
        switch ComposerPaste.choice(text: plain, hasFile: !urls.isEmpty, hasImage: image != nil) {
        case .files:
            if let pasteFiles { pasteFiles(urls); return }
        case .image:
            if let image, let pasteImage { pasteImage(image); return }
        case .text:
            if let plain, !plain.isEmpty { insertText(plain, replacementRange: selectedRange()); return }
        }
        let pdf = board.data(forType: NSPasteboard.PasteboardType("com.adobe.pdf"))
        if PasteChoice.usePDF(hasFile: !urls.isEmpty, hasImage: image != nil, hasPDF: pdf != nil), let pdf, let pastePDF { pastePDF(pdf); return }
        if let words = ClipboardHTML.text(html: board.string(forType: .html), plain: plain) { insertText(words, replacementRange: selectedRange()); return }
        if let address = ClipboardAddress.text(plain: plain, urls: board.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []) { insertText(address, replacementRange: selectedRange()); return }
        super.paste(sender)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        FieldDrop.attaches(fileURLs(from: sender)).isEmpty ? super.draggingEntered(sender) : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        FieldDrop.attaches(fileURLs(from: sender)).isEmpty ? super.draggingUpdated(sender) : .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = FieldDrop.attaches(fileURLs(from: sender))
        guard !files.isEmpty, let pasteFiles else { return super.performDragOperation(sender) }
        pasteFiles(files)
        return true
    }
    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), LineBreak.sends(shift: event.modifierFlags.contains(.shift), option: event.modifierFlags.contains(.option), marked: hasMarkedText()) { submit?(); return }
        if event.keyCode == 53 { escape?(); return }
        // NSTextView has no period-substitution setter. Insert a literal space before
        // the input system can rewrite a double space, preserving IME composition.
        if !DoubleSpace.insertsPeriod, event.characters == " ", !hasMarkedText(), event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            insertText(" ", replacementRange: selectedRange())
            return
        }
        super.keyDown(with: event)
    }
    override func resignFirstResponder() -> Bool {
        commitMarkedTextIfNeeded()
        let accepted = super.resignFirstResponder()
        if accepted { observeFocus() }
        return accepted
    }
    /// Keep an in-progress IME word when leaving or sending from this editor.
    func commitMarkedTextIfNeeded() {
        guard ComposerSubmit.commitsMarkedTextBeforeSend(hasMarkedText: hasMarkedText()) else { return }
        let range = markedRange()
        let original = string as NSString
        guard range.location != NSNotFound, range.location >= 0, range.location <= original.length,
              range.length > 0, range.length <= original.length - range.location else { unmarkText(); return }
        let committed = original.substring(with: range)
        unmarkText()
        let current = string as NSString
        let length = (committed as NSString).length
        let kept = range.location <= current.length && length <= current.length - range.location &&
            current.substring(with: NSRange(location: range.location, length: length)) == committed
        if !kept { insertText(committed, replacementRange: NSRange(location: min(range.location, current.length), length: 0)) }
    }
}
struct DraftEditor: NSViewRepresentable {
    @Binding var text: String
    var draftID: UUID? = nil
    var focusToken: Int = 0
    var permitsFocus: (NSWindow) -> Bool = { _ in true }
    var submit: () -> Void
    var cancel: () -> Void
    var pasteFiles: (([URL]) -> Void)? = nil
    var pasteImage: ((Data) -> Void)? = nil
    var pastePDF: ((Data) -> Void)? = nil
    var installCommit: (@escaping () -> Void) -> Void = { _ in }
    var onMeasuredHeight: ((CGFloat) -> Void)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil
    static func measuredHeight(_ editor: NSTextView) -> CGFloat {
        guard let layout = editor.layoutManager, let container = editor.textContainer else { return 61 }
        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).height + editor.textContainerInset.height * 2
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let editor = ComposerTextView(); editor.isRichText = false; editor.drawsBackground = false; editor.allowsUndo = true
        editor.font = .systemFont(ofSize: 15); editor.textColor = Theme.inkColor; editor.insertionPointColor = Theme.accentColor
        editor.textContainerInset = NSSize(width: 2, height: 5); editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false; editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = TypedText.correctsSpelling
        editor.isContinuousSpellCheckingEnabled = TypedText.correctsSpelling
        editor.isAutomaticTextCompletionEnabled = WordCompletion.insertsSuggestions
        editor.isGrammarCheckingEnabled = ComposerMarks.grammar
        editor.isAutomaticDataDetectionEnabled = ComposerMarks.dataDetectors
        editor.smartInsertDeleteEnabled = PasteSpacing.adjustsAutomatically
        editor.delegate = context.coordinator; editor.identifier = NSUserInterfaceItemIdentifier("lilt.composer")
        context.coordinator.editor = editor
        editor.focusChanged = { [weak editor, weak coordinator = context.coordinator] focused in
            guard let editor, let coordinator, coordinator.editor === editor else { return }
            coordinator.parent.onFocusChange?(focused)
        }
        editor.setAccessibilityLabel("Message Vale"); editor.submit = submit; editor.escape = cancel; editor.pasteFiles = pasteFiles; editor.pasteImage = pasteImage; editor.pastePDF = pastePDF
        editor.registerForDraggedTypes([.fileURL])
        keepFieldClear(scroll)
        scroll.documentView = editor; return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        keepFieldClear(nsView)
        guard let editor = nsView.documentView as? ComposerTextView else { return }
        editor.observeFocus()
        editor.textColor = Theme.inkColor; editor.insertionPointColor = Theme.accentColor
        editor.submit = submit; editor.escape = cancel; editor.pasteFiles = pasteFiles; editor.pasteImage = pasteImage; editor.pastePDF = pastePDF
        installCommit { [weak editor, weak coordinator = context.coordinator] in
            guard let editor, let coordinator else { return }
            // Ordinary edits already publish through textDidChange. Only a live IME
            // composition can need committing here; model changes may be newer than this view.
            guard ComposerSubmit.commitsMarkedTextBeforeSend(hasMarkedText: editor.hasMarkedText()) else { return }
            editor.commitMarkedTextIfNeeded()
            if editor.string != coordinator.parent.text { coordinator.parent.text = editor.string }
        }
        let ownerChanged = context.coordinator.draftID != draftID
        context.coordinator.draftID = draftID
        if ownerChanged { editor.undoManager?.removeAllActions() }
        if editor.string != text, !editor.hasMarkedText() {
            let previous = editor.string.utf16.count
            let caret = editor.selectedRange().location
            let dropUndo = ComposerUndo.clearsUndo(previous: editor.string, replacement: text)
            editor.undoManager?.disableUndoRegistration()
            editor.string = text
            editor.undoManager?.enableUndoRegistration()
            if dropUndo { editor.undoManager?.removeAllActions() }
            editor.setSelectedRange(NSRange(location: DraftCaret.location(previousUTF16: previous, nextUTF16: text.utf16.count, caret: caret), length: 0))
            editor.scrollRangeToVisible(editor.selectedRange())
        }
        if context.coordinator.lastFocus != focusToken {
            context.coordinator.lastFocus = focusToken
            if ComposerFocus.returns(afterSending: true) {
                DispatchQueue.main.async { [weak editor, weak coordinator = context.coordinator] in
                    guard let editor, let coordinator, coordinator.parent.focusToken == focusToken, let window = editor.window,
                          window.isVisible, !window.isMiniaturized, window.attachedSheet == nil, NSApp.modalWindow == nil,
                          NSApp.keyWindow?.isSheet != true,
                          !NSApp.windows.contains(where: { $0.isVisible && ($0.isSheet || $0.attachedSheet != nil) }),
                          coordinator.parent.permitsFocus(window) else { return }
                    window.makeFirstResponder(editor)
                }
            }
        }
        DispatchQueue.main.async { [weak editor, weak coordinator = context.coordinator] in
            guard let editor, let coordinator else { return }
            coordinator.parent.onMeasuredHeight?(Self.measuredHeight(editor))
        }
    }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        (nsView.documentView as? ComposerTextView)?.focusChanged = nil
        coordinator.editor = nil
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DraftEditor
        weak var editor: ComposerTextView?
        var lastFocus: Int
        var draftID: UUID?
        init(_ parent: DraftEditor) { self.parent = parent; lastFocus = parent.focusToken; draftID = parent.draftID }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            parent.onMeasuredHeight?(DraftEditor.measuredHeight(editor))
        }
    }
}

private func keepFieldClear(_ scroll: NSScrollView) {
    guard FieldSurface.staysClear else { return }
    scroll.drawsBackground = false
    scroll.backgroundColor = .clear
    scroll.contentView.drawsBackground = false
    scroll.contentView.backgroundColor = .clear
}
