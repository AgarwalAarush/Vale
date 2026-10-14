import SwiftUI
import AppKit

enum Theme {
    static let canvasNS = NSColor(white: 0.07, alpha: 1)
    static let inkNS = NSColor(white: 0.93, alpha: 1)
    static let accentNS = NSColor(red: 0.62, green: 0.70, blue: 0.86, alpha: 1)
    static let background = Color(nsColor: canvasNS)
    static let ink = Color(nsColor: inkNS)
    static let muted = Color(white: 0.64)
    static let faint = Color(white: 0.46)
    static let accent = Color(nsColor: accentNS)
    static let danger = Color(red: 0.86, green: 0.48, blue: 0.45)
    static let line = Color.white.opacity(0.08)
    static let raised = Color.white.opacity(0.04)
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
        content.background(GlassMaterial().overlay(Theme.background.opacity(0.9)))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            .foregroundStyle(Theme.ink).preferredColorScheme(.dark)
    }
}
struct QuietButton: ButtonStyle {
    var filled = false
    func makeBody(configuration: Configuration) -> some View { QuietButtonBody(configuration: configuration, filled: filled) }
    private struct QuietButtonBody: View {
        let configuration: ButtonStyleConfiguration
        var filled: Bool
        @State private var hover = false
        var body: some View {
            configuration.label.font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(configuration.isPressed ? 0.10 : hover ? 0.06 : filled ? 0.05 : 0))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
                .onHover { hover = $0 }
        }
    }
}
struct IconButton: View {
    var symbol: String; var label: String; var tint: Color = Theme.muted; var side: CGFloat = 30; var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: side > 26 ? 13 : 11, weight: .medium)).foregroundStyle(tint).frame(width: side, height: side).background(Color.white.opacity(hover ? 0.08 : 0)).clipShape(Circle()) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label).onHover { hover = $0 }
    }
}
struct LogoMark: View {
    var size: CGFloat = 24
    var body: some View {
        Text("V").font(.system(size: size * 0.52, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
            .frame(width: size, height: size).background(Theme.raised)
            .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.28), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: max(4, size * 0.28), style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
struct AudioMark: View {
    var active: Bool
    var height: CGFloat = 15
    var body: some View {
        HStack(spacing: 2) { ForEach(Array([0.38,0.72,1.0,0.62,0.3].enumerated()), id: \.offset) { _, value in Capsule().fill(active ? Theme.accent : Theme.muted).frame(width: 2, height: max(3, height * value)) } }.frame(width: 16, height: height).accessibilityHidden(true)
    }
}
struct CommandEntry: Identifiable {
    var id: String
    var title: String
    var symbol: String
    var shortcut: String = ""
    var disabled = false
    var checked = false
    var destructive = false
    var action: () -> Void
}
struct CommandList: View {
    var sections: [[CommandEntry]]
    @Binding var highlight: Int
    var onSelect: (CommandEntry) -> Void
    var body: some View {
        let flat = sections.flatMap { $0 }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                if index > 0 { Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4) }
                ForEach(section) { item in
                    let selected = flat.indices.contains(highlight) && flat[highlight].id == item.id
                    Button { onSelect(item) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.symbol).font(.system(size: 11)).frame(width: 14)
                            Text(item.title).lineLimit(1)
                            Spacer(minLength: 8)
                            if item.checked { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent) }
                            else if !item.shortcut.isEmpty { Text(item.shortcut).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.faint) }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(item.disabled ? Theme.faint : item.destructive ? Theme.danger : Theme.ink)
                        .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected && !item.disabled ? Color.white.opacity(0.06) : .clear))
                    }.buttonStyle(.plain).disabled(item.disabled).onHover { if $0, let idx = flat.firstIndex(where: { $0.id == item.id }) { highlight = idx } }
                }
            }
        }.padding(4)
    }
}
struct LineField: View {
    var title: String
    var prompt: String
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 13, design: .monospaced)).focused($focused)
                .padding(.horizontal, 8).padding(.vertical, 8).background(Theme.raised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(focused ? Theme.accent : Theme.line, lineWidth: 0.5))
        }
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
        editor.font = .systemFont(ofSize: 13); editor.textColor = Theme.inkNS; editor.insertionPointColor = Theme.accentNS
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
            let selection = editor.selectedRange(); editor.string = text
            editor.setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0))
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DraftEditor
        init(_ parent: DraftEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let editor = notification.object as? NSTextView { parent.text = editor.string } }
    }
}
