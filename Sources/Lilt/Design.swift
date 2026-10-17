import SwiftUI
import AppKit

enum Theme {
    static let ink = Color(red: 0.94, green: 0.95, blue: 0.96)
    static let muted = Color(red: 0.61, green: 0.64, blue: 0.68)
    static let accent = Color(red: 0.57, green: 0.67, blue: 1)
    static let line = Color.white.opacity(0.09)
    static let background = Color(red: 0.10, green: 0.11, blue: 0.12)
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
        content.background(GlassMaterial().overlay(Theme.background.opacity(0.86)))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
            .foregroundStyle(Theme.ink).preferredColorScheme(.dark)
    }
}
struct QuietButton: ButtonStyle {
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(configuration.isPressed ? 0.15 : filled ? 0.075 : 0.025))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.7))
    }
}
struct IconButton: View {
    var symbol: String; var label: String; var tint: Color = Theme.muted; var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(tint).frame(width: 30, height: 30).background(Color.white.opacity(hover ? 0.075 : 0)).clipShape(Circle()) }
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
        HStack(spacing: 3) { ForEach(Array([9.0,18.0,25.0,15.0,7.0].enumerated()), id: \.offset) { _, value in Capsule().fill(active ? Theme.accent : Theme.accent.opacity(0.75)).frame(width: 3, height: value) } }.frame(width: 29, height: 27).accessibilityHidden(true)
    }
}

final class ComposerTextView: NSTextView {
    var submit: (() -> Void)?
    var escape: (() -> Void)?
    var pasteFiles: (([URL]) -> Void)?
    var pasteImage: ((Data) -> Void)?
    override func paste(_ sender: Any?) {
        let board=NSPasteboard.general
        if let urls=board.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL], !urls.isEmpty,let pasteFiles {pasteFiles(urls);return}
        if let data=board.data(forType:.png) ?? board.data(forType:.tiff),let pasteImage {pasteImage(data);return}
        super.paste(sender)
    }
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), !event.modifierFlags.contains(.shift), !hasMarkedText() { submit?(); return }
        if event.keyCode == 53 { escape?(); return }
        super.keyDown(with: event)
    }
}
struct DraftEditor: NSViewRepresentable {
    @Binding var text: String
    var submit: () -> Void
    var cancel: () -> Void
    var pasteFiles: (([URL]) -> Void)? = nil
    var pasteImage: ((Data) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let editor = ComposerTextView(); editor.isRichText = false; editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 14); editor.textColor = NSColor(white: 0.93, alpha: 1); editor.insertionPointColor = NSColor(red: 0.57, green: 0.67, blue: 1, alpha: 1)
        editor.textContainerInset = NSSize(width: 2, height: 5); editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false; editor.isAutomaticTextReplacementEnabled = false
        editor.delegate = context.coordinator; editor.identifier = NSUserInterfaceItemIdentifier("lilt.composer")
        editor.setAccessibilityLabel("Message Lilt"); editor.submit = submit; editor.escape = cancel; editor.pasteFiles = pasteFiles; editor.pasteImage = pasteImage
        scroll.documentView = editor; return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = nsView.documentView as? ComposerTextView else { return }
        editor.submit = submit; editor.escape = cancel; editor.pasteFiles = pasteFiles; editor.pasteImage = pasteImage
        if editor.string != text {
            let previous=editor.string.utf16.count
            let caret=editor.selectedRange().location
            editor.string = text
            editor.setSelectedRange(NSRange(location: DraftCaret.location(previousUTF16: previous, nextUTF16: text.utf16.count, caret: caret), length: 0))
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DraftEditor
        init(_ parent: DraftEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let editor = notification.object as? NSTextView { parent.text = editor.string } }
    }
}
