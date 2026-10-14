import AppKit
import SwiftUI
import LiltCore

enum SurfaceMetrics {
    static let compact = NSSize(width: 232, height: 36)
    static let open = NSSize(width: 372, height: 512)
    static let large = NSSize(width: 520, height: 680)
}

enum CompanionMenus {
    static func outline(_ model: AppModel) -> [[String]] {
        var primary = ["toggle", "new", "history"]
        if model.active != nil { primary.append("close") }
        var tools = ["aloud", "point", "focus30", "focus60", "focus0"]
        if model.active?.mode == .learn { tools.append("walkthrough") }
        return [primary, tools, ["settings", "quit"]]
    }
    static func height(_ model: AppModel) -> CGFloat {
        let sections = outline(model)
        let rows = sections.reduce(0) { $0 + $1.count }
        return 1 + 8 + CGFloat(rows) * 28 + CGFloat(max(0, sections.count - 1)) * 9
    }
}

struct CommandEntry: Identifiable {
    var id: String
    var title: String
    var symbol: String
    var shortcut: String = ""
    var disabled = false
    var checked = false
    var action: () -> Void
}

struct CompanionSurface: View {
    @ObservedObject var model: AppModel
    var summon: () -> Void
    var dismiss: () -> Void
    var layout: () -> Void
    var focus: () -> Void
    @State private var walkthrough = false
    @State private var highlight = 0
    var body: some View {
        VStack(spacing: 0) {
            bar
            if model.commandMenu && !model.coachPresented {
                Rectangle().fill(Theme.line).frame(height: 1)
                commandMenu
            }
            if model.coachPresented { CoachBody(model: model) }
        }
        .modifier(GlassSurface(radius: model.coachPresented || model.commandMenu ? 14 : 18))
        .overlay { if model.commandMenu && model.coachPresented { Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture { model.commandMenu = false } } }
        .overlay(alignment: .topTrailing) { if model.commandMenu && model.coachPresented { commandMenu.padding(.top, 42).padding(.trailing, 8) } }
        .background(CommandKeyCatcher(active: model.commandMenu, onKey: handleKey))
        .dropDestination(for: URL.self) { urls, _ in Task { await model.importFiles(urls) }; return urls.contains(where: { $0.isFileURL }) }
        .environment(\.openURL, OpenURLAction { url in ["https", "http"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded })
        .onChange(of: model.commandMenu) { layout(); if !model.commandMenu && model.coachPresented { focus() } }
        .alert("Show the walkthrough?", isPresented: $walkthrough) {
            Button("Keep thinking", role: .cancel) {}
            Button("Show walkthrough") { model.send("Please give me the full walkthrough now, explaining why each step works.", reveal: true) }
        } message: { Text("This will reveal the method. Your current hints stay in the conversation.") }
    }
    private var bar: some View {
        HStack(spacing: 2) {
            Button(action: summon) {
                HStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        AudioMark(active: model.voice.listening || model.voice.speaking, height: 14)
                        if model.context.hasSelection { Circle().fill(model.context.live ? Theme.accent : Theme.muted).frame(width: 5, height: 5).offset(x: 2, y: 1) }
                    }
                    if let chat = model.active, chat.duration > 0 { Text(chat.timerText).font(.system(size: 11, weight: .semibold, design: .monospaced)).monospacedDigit() }
                    Text(model.active?.title == "New chat" ? "Vale" : model.active?.title ?? "Vale").font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
            }.buttonStyle(.plain).help(model.coachPresented ? "Conversation is open" : "Open the conversation").accessibilityLabel(model.coachPresented ? "Vale conversation" : "Open Vale")
            Spacer(minLength: 6)
            if !model.coachPresented {
                IconButton(symbol: model.voice.listening ? "mic.fill" : "mic", label: talkLabel, tint: model.voice.listening ? Theme.accent : Theme.ink, side: 22) { model.toggleVoice() }.disabled(model.paused || model.active == nil)
            }
            IconButton(symbol: model.paused ? "play.fill" : "pause.fill", label: model.paused ? "Resume" : "Pause", tint: model.paused ? Theme.accent : Theme.ink, side: 22) { model.togglePause() }.disabled(model.active == nil)
            if model.coachPresented { IconButton(symbol: "chevron.down", label: "Hide conversation", side: 22, action: dismiss) }
            IconButton(symbol: "ellipsis", label: "More options", tint: model.commandMenu ? Theme.ink : Theme.muted, side: 22) { model.commandMenu.toggle() }
        }.padding(.leading, 10).padding(.trailing, 4).frame(height: SurfaceMetrics.compact.height)
    }
    private var commandMenu: some View {
        let sections = menuSections
        let flat = sections.flatMap { $0 }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                if index > 0 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4) }
                ForEach(section) { item in
                    let selected = flat.indices.contains(highlight) && flat[highlight].id == item.id
                    Button { guard !item.disabled else { return }; model.commandMenu = false; item.action() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.symbol).font(.system(size: 11)).frame(width: 14)
                            Text(item.title).lineLimit(1)
                            Spacer(minLength: 8)
                            if item.checked { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent) }
                            else if !item.shortcut.isEmpty { Text(item.shortcut).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted) }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(item.disabled ? Theme.muted.opacity(0.45) : Theme.ink)
                        .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected && !item.disabled ? Color.white.opacity(0.08) : .clear))
                    }.buttonStyle(.plain).disabled(item.disabled).onHover { if $0, let idx = flat.firstIndex(where: { $0.id == item.id }) { highlight = idx } }
                }
            }
        }
        .padding(4)
        .frame(maxWidth: model.coachPresented ? 250 : .infinity, alignment: .leading)
        .background { if model.coachPresented { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 0.12, green: 0.125, blue: 0.135)).overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)) } }
        .onAppear { highlight = 0 }
    }
    private var menuSections: [[CommandEntry]] {
        let enabled = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return CompanionMenus.outline(model).map { ids in ids.compactMap { enabled[$0] } }
    }
    private var entries: [CommandEntry] {
        [
            CommandEntry(id: "toggle", title: model.coachPresented ? "Hide" : "Open", symbol: model.coachPresented ? "chevron.down" : "bubble.left", shortcut: model.coachPresented ? "esc" : "", action: { model.coachPresented ? dismiss() : summon() }),
            CommandEntry(id: "new", title: "New chat", symbol: "square.and.pencil", shortcut: "⌘N", action: { model.newSession() }),
            CommandEntry(id: "history", title: "Chat history", symbol: "clock", action: { model.showLibrary?() }),
            CommandEntry(id: "close", title: "Close chat", symbol: "xmark", action: { model.complete() }),
            CommandEntry(id: "aloud", title: "Read replies aloud", symbol: "speaker.wave.2", checked: model.readAloud, action: { model.readAloud.toggle() }),
            CommandEntry(id: "point", title: "Point it out", symbol: "cursorarrow.rays", disabled: !model.context.hasSelection || model.busy, action: { summon(); model.pointItOut() }),
            CommandEntry(id: "focus30", title: "Focus 30 minutes", symbol: "timer", action: { model.setFocus(minutes: 30) }),
            CommandEntry(id: "focus60", title: "Focus 60 minutes", symbol: "timer", action: { model.setFocus(minutes: 60) }),
            CommandEntry(id: "focus0", title: "No timer", symbol: "timer", checked: model.active?.duration == 0, action: { model.setFocus(minutes: 0) }),
            CommandEntry(id: "walkthrough", title: "Show a full walkthrough", symbol: "list.bullet.rectangle", disabled: model.active?.messages.isEmpty != false || model.busy, action: { summon(); walkthrough = true }),
            CommandEntry(id: "settings", title: "Settings", symbol: "slider.horizontal.3", shortcut: "⌘,", action: { model.settings = true; model.showLibrary?() }),
            CommandEntry(id: "quit", title: "Quit Vale", symbol: "power", shortcut: "⌘Q", action: { NSApplication.shared.terminate(nil) })
        ]
    }
    private var talkLabel: String { model.voice.listening ? "Finish speaking" : (model.voice.speaking || model.busy ? "Interrupt and talk" : "Talk") }
    private func handleKey(_ code: UInt16) {
        let flat = menuSections.flatMap { $0 }
        let enabled = flat.indices.filter { !flat[$0].disabled }
        guard !enabled.isEmpty else { model.commandMenu = false; return }
        switch code {
        case 125: highlight = enabled.firstIndex(of: highlight).map { enabled[min($0 + 1, enabled.count - 1)] } ?? enabled[0]
        case 126: highlight = enabled.firstIndex(of: highlight).map { enabled[max($0 - 1, 0)] } ?? enabled[0]
        case 36, 76:
            let item = (flat.indices.contains(highlight) && !flat[highlight].disabled) ? flat[highlight] : flat[enabled[0]]
            model.commandMenu = false; item.action()
        case 53: model.commandMenu = false
        default: break
        }
    }
}

private struct CommandKeyCatcher: NSViewRepresentable {
    var active: Bool
    var onKey: (UInt16) -> Void
    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) {
        view.onKey = onKey
        let becameActive = active && !view.active
        view.active = active
        if becameActive { DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }
    }
    final class Catcher: NSView {
        var onKey: ((UInt16) -> Void)?
        var active = false
        override var acceptsFirstResponder: Bool { active }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func keyDown(with event: NSEvent) { onKey?(event.keyCode) }
    }
}

struct CoachBody: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            ContextStrip(model: model).padding(.top, 10)
            if let warning = model.shortcutWarning { Text(warning).font(.system(size: 10)).foregroundStyle(.orange).padding(.horizontal, 16).padding(.top, 8) }
            if model.active?.contextLimited == true {
                HStack(alignment: .top, spacing: 7) { Image(systemName: "clock.arrow.circlepath"); Text("Using recent messages only. Earlier context stays in History."); Spacer(minLength: 0); Button("History") { model.showLibrary?() }.buttonStyle(.plain).foregroundStyle(Theme.accent) }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.horizontal, 16).padding(.top, 8)
            }
            if let guide = model.active?.guide { GuideCard(model: model, guide: guide) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let session = model.active {
                            if session.messages.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(session.mode == .learn ? "What are we working through?" : "How can I help?").font(.system(size: 16, weight: .semibold)).tracking(-0.3)
                                    Text(session.mode == .learn ? "Think it through with a little guidance." : "Ask anything, drop a file, or share a window.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(2)
                                }.padding(.top, 6)
                            }
                            ForEach(session.messages) { message in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(message.role == "user" ? "YOU" : "LILT").font(.system(size: 9, weight: .medium)).tracking(0.8).foregroundStyle(Theme.muted)
                                    Text(.init(message.text)).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    if !message.attachments.isEmpty { ScrollView(.horizontal) { HStack(spacing: 7) { ForEach(message.attachments) { record in FileChip(record: record, model: model, removable: true) } } }.scrollIndicators(.hidden) }
                                    if message.highlightUnavailable { Label("Highlight unavailable · check your selected window", systemImage: "eye.slash").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                                    if message.screenChanged {
                                        HStack { Image(systemName: "arrow.clockwise"); Text("Window changed during this answer"); if message.id == model.active?.messages.last?.id { Button("Refresh") { model.refreshAnswer() }.buttonStyle(.plain).foregroundStyle(Theme.accent) } }.font(.system(size: 10)).foregroundStyle(Theme.muted)
                                    }
                                    if message.role == "assistant" {
                                        HStack(spacing: 4) {
                                            IconButton(symbol: "speaker.wave.2", label: "Read this reply", side: 24) { model.voice.speak(message.text) }
                                            IconButton(symbol: "doc.on.doc", label: "Copy reply", side: 24) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) }
                                        }.padding(.leading, -4)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(message.role == "user" ? 10 : 0).background(message.role == "user" ? Color.white.opacity(0.04) : .clear).clipShape(RoundedRectangle(cornerRadius: 8)).id(message.id)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) { Text("Ready when you are.").font(.system(size: 18, weight: .medium)); Button("New chat") { model.prepareChat() }.buttonStyle(QuietButton(filled: true)) }.padding(.top, 12)
                        }
                        if model.busy { HStack(spacing: 8) { ProgressView().controlSize(.mini); Text("Thinking…").font(.system(size: 12)).foregroundStyle(Theme.muted) }.padding(.vertical, 4).id("thinking") }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 16).padding(.bottom, 8).frame(maxWidth: .infinity, alignment: .leading)
                }.scrollIndicators(.hidden)
                .onChange(of: model.active?.messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: model.busy) { proxy.scrollTo("bottom", anchor: .bottom) }
            }.frame(maxHeight: .infinity)
            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) { Text(error).font(.system(size: 11)).foregroundStyle(Color(red: 0.96, green: 0.77, blue: 0.49)); Spacer(minLength: 0); Button { model.error = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).accessibilityLabel("Dismiss message") }
                    HStack(spacing: 14) {
                        if model.active?.messages.last?.role == "user" { Button("Retry message") { model.retry() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent) }
                        if model.context.hasSelection { Button("Change window") { model.context.choose() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent) }
                    }
                }.padding(10).background(Color.orange.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 14).padding(.bottom, 8)
            }
            if model.paused, model.active != nil {
                HStack { Text("Paused · mic and sharing off").font(.system(size: 11)).foregroundStyle(Theme.muted); Spacer(); Button("Resume") { model.togglePause() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.accent) }.padding(.horizontal, 16).padding(.bottom, 8)
            }
            if model.active?.mode == .learn {
                HStack(spacing: 8) {
                    Button { model.nextHint() } label: { Label("Hint", systemImage: "lightbulb").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
                    Button { model.pointItOut() } label: { Label("Point it out", systemImage: "cursorarrow.rays").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
                }.disabled(model.busy || model.paused || model.active == nil).padding(.horizontal, 14).padding(.bottom, 8)
            }
            if !model.pendingFiles.isEmpty { ScrollView(.horizontal) { HStack(spacing: 7) { ForEach(model.pendingFiles) { record in FileChip(record: record, model: model, removable: true) } }.padding(.horizontal, 14) }.scrollIndicators(.hidden).padding(.bottom, 8) }
            VStack(spacing: 2) {
                ZStack(alignment: .topLeading) {
                    if model.draft.isEmpty { Text("Ask quietly…").font(.system(size: 13)).foregroundStyle(Theme.muted.opacity(0.8)).padding(.top, 5).padding(.leading, 6).allowsHitTesting(false) }
                    DraftEditor(text: Binding(get: { model.draft }, set: { model.editDraft($0) }), submit: { model.send() }, cancel: { model.stopInteraction() }, pasteFiles: { urls in Task { await model.importFiles(urls) } }, pasteImage: { model.pasteImage($0) }).frame(height: 46)
                }
                HStack(spacing: 0) {
                    IconButton(symbol: "plus", label: "Attach files", side: 26) { model.attachFiles() }.disabled(model.importing)
                    IconButton(symbol: "globe", label: model.active?.webEnabled == true ? "Web search on" : "Enable web search", tint: model.active?.webEnabled == true ? Theme.accent : Theme.muted, side: 26) { model.setWeb(!(model.active?.webEnabled ?? false)) }
                    IconButton(symbol: "list.number", label: "Start step-by-step help", side: 26) { model.startGuide() }.disabled(model.busy || model.paused)
                    Spacer(minLength: 0)
                    if model.voice.speaking { IconButton(symbol: "stop.fill", label: "Stop playback", tint: Theme.accent, side: 26) { model.stopResponse() } }
                    IconButton(symbol: model.voice.listening ? "mic.fill" : "mic", label: model.voice.listening ? "Finish speaking" : (model.voice.speaking || model.busy ? "Interrupt and talk" : "Talk"), tint: model.voice.listening ? Theme.accent : Theme.muted, side: 26) { model.toggleVoice() }.disabled(model.paused || model.active == nil)
                    Button { if model.busy { model.stopResponse() } else { model.send() } } label: {
                        Image(systemName: model.busy ? "stop.fill" : "arrow.up").font(.system(size: 11, weight: .bold)).foregroundStyle(model.hasInput || model.busy ? Color(red: 0.08, green: 0.09, blue: 0.11) : Theme.muted).frame(width: 24, height: 24).background(model.hasInput || model.busy ? Theme.accent : Color.white.opacity(0.06)).clipShape(Circle())
                    }.buttonStyle(.plain).disabled(!model.busy && (!model.hasInput || model.paused || model.active == nil || model.importing)).help(model.busy ? "Stop response" : "Send message").accessibilityLabel(model.busy ? "Stop response" : "Send message").padding(.leading, 4)
                }
            }.padding(.horizontal, 8).padding(.vertical, 4).background(.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)).padding(.horizontal, 12)
            HStack(spacing: 8) {
                Text(model.status).font(.system(size: 10)).foregroundStyle(model.voice.listening ? Theme.accent : Theme.muted).lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    ForEach(ChatMode.allCases, id: \.self) { mode in
                        Button(mode.label) { if model.active?.mode != mode { model.setMode(mode) } }.buttonStyle(.plain).font(.system(size: 10, weight: model.active?.mode == mode ? .semibold : .medium)).foregroundStyle(model.active?.mode == mode ? Theme.ink : Theme.muted).padding(.horizontal, 8).padding(.vertical, 3).background(model.active?.mode == mode ? Color.white.opacity(0.08) : .clear).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous)).accessibilityLabel(mode == .assistant ? "Assistant mode" : "Learn mode")
                    }
                }.padding(2).overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
                Button { model.setConversation(!model.conversation) } label: { Image(systemName: model.conversation ? "waveform.circle.fill" : "waveform.circle").font(.system(size: 12)).foregroundStyle(model.conversation ? Theme.accent : Theme.muted) }.buttonStyle(.plain).disabled(model.paused).help(model.conversation ? "End conversation" : "Conversation").accessibilityLabel(model.conversation ? "End conversation" : "Conversation")
                IconButton(symbol: model.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", label: model.expanded ? "Compact assistant" : "Expand assistant", side: 22) { model.expandCoach?() }
            }.padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 8)
        }
    }
}
