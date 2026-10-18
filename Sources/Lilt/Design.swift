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
    private static let glassTint = Color(red: 0.10, green: 0.11, blue: 0.12)
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
    var body: some View {
        Text("V").font(.system(size: size * 0.61, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.13, green: 0.23, blue: 0.62))
            .frame(width: size, height: size).background(LinearGradient(colors: [Color(red: 0.76, green: 0.81, blue: 1), Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(.white.opacity(0.2), lineWidth: 0.6))
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
        let board=NSPasteboard.general
        let urls=board.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]
        let hasFile=urls?.isEmpty==false
        let plain=board.string(forType:.string)
        let html=board.string(forType:.html)
        let image=board.data(forType:.png) ?? board.data(forType:.tiff)
        switch ComposerPaste.choice(text:plain,hasFile:hasFile,hasImage:image != nil) {
        case .files:
            if let urls,let pasteFiles {pasteFiles(urls);return}
        case .image:
            if let image,let pasteImage {pasteImage(image);return}
        case .text:
            if let words=ClipboardHTML.text(html:html, plain:plain) {
                insertText(words, replacementRange: selectedRange())
                return
            }
            super.paste(sender);return
        }
        let pdf=board.data(forType:NSPasteboard.PasteboardType("com.adobe.pdf"))
        if PasteChoice.usePDF(hasFile:hasFile,hasImage:image != nil,hasPDF:pdf != nil),let pdf,let pastePDF {pastePDF(pdf);return}
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
        guard !files.isEmpty else { return super.performDragOperation(sender) }
        pasteFiles?(files)
        return true
    }
    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), LineBreak.sends(shift: event.modifierFlags.contains(.shift), option: event.modifierFlags.contains(.option), marked: hasMarkedText()) { submit?(); return }
        if event.keyCode == 53 { escape?(); return }
        super.keyDown(with: event)
    }
    override func resignFirstResponder() -> Bool {
        commitMarkedTextIfNeeded()
        return super.resignFirstResponder()
    }
    /// A word still being composed is part of the question. Leaving it marked drops it when the field is cleared.
    func commitMarkedTextIfNeeded() {
        guard ComposerSubmit.commitsMarkedTextBeforeSend(hasMarkedText: hasMarkedText()) else { return }
        let range = markedRange()
        guard range.location != NSNotFound, range.length > 0 else { unmarkText(); return }
        let committed = (string as NSString).substring(with: range)
        let location = range.location
        unmarkText()
        let current = string as NSString
        let length = (committed as NSString).length
        let kept = location + length <= current.length && current.substring(with: NSRange(location: location, length: length)) == committed
        if !kept {
            insertText(committed, replacementRange: NSRange(location: min(location, current.length), length: 0))
        }
    }
}

func commitComposerMarkedText() {
    for window in NSApp.windows {
        guard let root = window.contentView else { continue }
        func walk(_ view: NSView) -> ComposerTextView? {
            if let editor = view as? ComposerTextView { return editor }
            for child in view.subviews { if let found = walk(child) { return found } }
            return nil
        }
        walk(root)?.commitMarkedTextIfNeeded()
    }
}
struct DraftEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int = 0
    var submit: () -> Void
    var cancel: () -> Void
    var pasteFiles: (([URL]) -> Void)? = nil
    var pasteImage: ((Data) -> Void)? = nil
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
        editor.isAutomaticPeriodSubstitutionEnabled = DoubleSpace.insertsPeriod
        editor.isGrammarCheckingEnabled = ComposerMarks.grammar
        editor.isAutomaticDataDetectionEnabled = ComposerMarks.dataDetectors
        editor.smartInsertDeleteEnabled = PasteSpacing.adjustsAutomatically
        editor.delegate = context.coordinator; editor.identifier = NSUserInterfaceItemIdentifier("lilt.composer")
        editor.setAccessibilityLabel("Message Lilt"); editor.submit = submit; editor.escape = cancel; editor.pasteFiles = pasteFiles; editor.pasteImage = pasteImage
        scroll.documentView = editor; return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        keepFieldClear(nsView)
        guard let editor = nsView.documentView as? ComposerTextView else { return }
        editor.submit = submit; editor.escape = cancel; editor.pasteFiles = pasteFiles; editor.pasteImage = pasteImage
        if editor.string != text {
            let selection = editor.selectedRange()
            let previous = editor.string.utf16.count
            let dropUndo = ComposerUndo.clearsUndo(previous: editor.string, replacement: text)
            editor.undoManager?.disableUndoRegistration()
            editor.string = text
            editor.undoManager?.enableUndoRegistration()
            if dropUndo { editor.undoManager?.removeAllActions() }
            let caret = DraftCaret.location(previousUTF16: previous, nextUTF16: text.utf16.count, caret: selection.location)
            editor.setSelectedRange(NSRange(location: caret, length: 0))
        }
        onMeasuredHeight?(Self.measuredHeight(editor))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DraftEditor
        init(_ parent: DraftEditor) { self.parent = parent }
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
