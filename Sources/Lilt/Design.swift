import SwiftUI
import AppKit
import LiltCore

enum Theme {
    static let inkColor = NSColor(srgbRed: 0.94, green: 0.95, blue: 0.96, alpha: 1)
    static let ink = Color(nsColor: inkColor)
    static let muted = Color(red: 0.61, green: 0.64, blue: 0.68)
    static let accent = Color(red: 0.57, green: 0.67, blue: 1)
    static let line = Color.white.opacity(0.09)
    /// Quiet warm charcoal for opaque windows. Distinct from the cool glass tint.
    static let windowBackground = NSColor(srgbRed: 0.165, green: 0.145, blue: 0.125, alpha: 1)
    static let background = Color(nsColor: windowBackground)
    /// Deeper warm recess for the history rail.
    static let rail = Color(nsColor: NSColor(srgbRed: 0.11, green: 0.095, blue: 0.08, alpha: 1))
    static let fill = Color.white.opacity(0.045)
    static let fillRaised = Color.white.opacity(0.08)
    static let fillPressed = Color.white.opacity(0.12)
    /// Capsule and coach glass tint. Unchanged so those panels keep their current fill.
    static let glassTint = Color(red: 0.10, green: 0.11, blue: 0.12)
}
struct GlassMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        view.appearance = NSAppearance(named: .darkAqua); return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
struct GlassSurface: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content.background(GlassMaterial().overlay(Theme.glassTint.opacity(0.86)))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.7))
            .foregroundStyle(Theme.ink).preferredColorScheme(.dark)
    }
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
        configuration.label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
            .background(configuration.isPressed ? Theme.fillPressed : (filled ? Theme.fillRaised : Theme.fill))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.7))
    }
}
struct IconButton: View {
    var symbol: String; var label: String; var tint: Color = Theme.muted; var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(tint).frame(width: 30, height: 30).background(hover ? Theme.fillRaised : .clear).clipShape(Circle()) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label).onHover { hover = $0 }
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
}
struct DraftEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int = 0
    var submit: () -> Void
    var cancel: () -> Void
    var pasteFiles: (([URL]) -> Void)? = nil
    var pasteImage: ((Data) -> Void)? = nil
    var pastePDF: ((Data) -> Void)? = nil
    var installCommit: (@escaping () -> Void) -> Void = { _ in }
    var onMeasuredHeight: ((CGFloat) -> Void)? = nil
    static func measuredHeight(_ editor: NSTextView) -> CGFloat {
        guard let layout = editor.layoutManager, let container = editor.textContainer else { return 61 }
        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).height + editor.textContainerInset.height * 2
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let editor = ComposerTextView(); editor.isRichText = false; editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 15); editor.textColor = NSColor(white: 0.94, alpha: 1); editor.insertionPointColor = NSColor(red: 0.57, green: 0.67, blue: 1, alpha: 1)
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
        editor.setAccessibilityLabel("Message Vale"); editor.submit = submit; editor.escape = cancel; editor.pasteFiles = pasteFiles; editor.pasteImage = pasteImage; editor.pastePDF = pastePDF
        editor.registerForDraggedTypes([.fileURL])
        keepFieldClear(scroll)
        scroll.documentView = editor; return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        keepFieldClear(nsView)
        guard let editor = nsView.documentView as? ComposerTextView else { return }
        editor.submit = submit; editor.escape = cancel; editor.pasteFiles = pasteFiles; editor.pasteImage = pasteImage; editor.pastePDF = pastePDF
        installCommit { [weak editor, weak coordinator = context.coordinator] in
            guard let editor, let coordinator else { return }
            // Ordinary edits already publish through textDidChange. Only a live IME
            // composition can need committing here; model changes may be newer than this view.
            guard ComposerSubmit.commitsMarkedTextBeforeSend(hasMarkedText: editor.hasMarkedText()) else { return }
            editor.unmarkText()
            if editor.string != coordinator.parent.text { coordinator.parent.text = editor.string }
        }
        if editor.string != text, !editor.hasMarkedText() {
            let previous = editor.string.utf16.count
            let caret = editor.selectedRange().location
            if ComposerUndo.dropsSentText { editor.undoManager?.disableUndoRegistration() }
            editor.string = text
            if ComposerUndo.dropsSentText { editor.undoManager?.enableUndoRegistration(); editor.undoManager?.removeAllActions() }
            editor.setSelectedRange(NSRange(location: DraftCaret.location(previousUTF16: previous, nextUTF16: text.utf16.count, caret: caret), length: 0))
            editor.scrollRangeToVisible(editor.selectedRange())
        }
        if context.coordinator.lastFocus != focusToken {
            context.coordinator.lastFocus = focusToken
            if ComposerFocus.returns(afterSending: true) {
                DispatchQueue.main.async { [weak editor, weak coordinator = context.coordinator] in
                    guard let editor, let coordinator, coordinator.parent.focusToken == focusToken, let window = editor.window else { return }
                    window.makeFirstResponder(editor)
                }
            }
        }
        DispatchQueue.main.async { [weak editor, weak coordinator = context.coordinator] in
            guard let editor, let coordinator else { return }
            coordinator.parent.onMeasuredHeight?(Self.measuredHeight(editor))
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DraftEditor
        var lastFocus: Int
        init(_ parent: DraftEditor) { self.parent = parent; lastFocus = parent.focusToken }
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
