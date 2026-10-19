import SwiftUI
import LiltCore

enum WorkspaceRoute: String { case chat, settings }
enum WorkspaceInspector: Equatable { case notes, files, file(UUID), context }

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @AppStorage("valeAppearance") private var appearance = "system"
    @State private var renameID: UUID?
    @State private var renameTitle = ""
    @State private var forgetID: UUID?
    @State private var walkthrough = false
    @State private var confirmGuide = false

    private var colorScheme: ColorScheme? { appearance == "light" ? .light : appearance == "dark" ? .dark : nil }
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 860
            let showRail = model.sidebarVisible && !compact
            let inlineInspector = geometry.size.width >= 1120 && model.workspaceRoute == .chat
            let chatVisible = model.workspaceRoute == .chat && (model.inspector == nil || inlineInspector) && (!compact || !model.compactHistoryVisible)
            HStack(spacing: 0) {
                if showRail {
                    navigation.frame(width: 224)
                    Rectangle().fill(Theme.line).frame(width: 1)
                }
                VStack(spacing: 0) {
                    toolbar(compact: compact, chatCovered: !chatVisible)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    HStack(spacing: 0) {
                        ZStack {
                            // Retain the native editor and transcript across secondary routes.
                            CoachView(model: model)
                                .opacity(chatVisible ? 1 : 0)
                                .allowsHitTesting(chatVisible)
                                .accessibilityHidden(!chatVisible)
                            if model.workspaceRoute == .settings { SettingsView(model: model) }
                            else if model.inspector != nil && !inlineInspector { inspector }
                            else if compact && model.compactHistoryVisible { compactNavigation }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        if inlineInspector, model.inspector != nil {
                            Rectangle().fill(Theme.line).frame(width: 1)
                            inspector.frame(width: 320)
                        }
                    }
                }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }.padding(.top, 28).background(Theme.background).foregroundStyle(Theme.ink)
        }
        .preferredColorScheme(colorScheme)
        .environment(\.openURL, OpenURLAction { AnswerLink.canOpen($0) ? .systemAction : .discarded })
        .alert("Rename chat", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("Chat title", text: $renameTitle)
            Button("Cancel", role: .cancel) { renameID = nil }
            Button("Save") { if let id = renameID { model.rename(id, to: renameTitle) }; renameID = nil }.disabled(ChatTitle.saved(renameTitle) == nil)
        }
        .confirmationDialog("Forget this chat and its uploaded files?", isPresented: Binding(get: { forgetID != nil }, set: { if !$0 { forgetID = nil } }), titleVisibility: .visible) {
            Button("Forget chat", role: .destructive) { if let id = forgetID { model.delete(id) }; forgetID = nil }
            Button("Cancel", role: .cancel) { forgetID = nil }
        }
        .alert("Show the walkthrough?", isPresented: $walkthrough) {
            Button("Keep thinking", role: .cancel) {}
            Button("Show walkthrough") { model.send("Please give me the full walkthrough now, explaining why each step works.", reveal: true) }
        } message: { Text("This reveals the method. Your current hints stay in the conversation.") }
        .alert("Start a step-by-step guide?", isPresented: $confirmGuide) {
            Button("Keep writing", role: .cancel) {}
            Button("Start guide") { model.startGuide() }
        } message: { Text("This sends what you have typed and clears the composer.") }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) { LogoMark(size: 25); Text("Vale").font(.system(size: 17, weight: .medium)); Spacer() }
                .padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 24)
            Button { model.newSession() } label: {
                Label("New chat", systemImage: "square.and.pencil").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.buttonStyle(.plain).background(Theme.fillRaised).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12)
            WorkspaceHistory(model: model, rename: rename, forget: { forgetID = $0 }).padding(.top, 18)
            Spacer(minLength: 8)
            Button { model.openSettings() } label: {
                Label("Settings", systemImage: "gearshape").font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.buttonStyle(.plain).foregroundStyle(model.workspaceRoute == .settings ? Theme.ink : Theme.muted)
                .background(model.workspaceRoute == .settings ? Theme.fillPressed : .clear).clipShape(RoundedRectangle(cornerRadius: 8)).padding(12)
        }.frame(maxHeight: .infinity).background(Theme.rail)
    }
    private var compactNavigation: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Your chats").font(.system(size: 22, weight: .medium)); Spacer(); Button("Back to chat") { model.compactHistoryVisible = false; model.backToChat() }.buttonStyle(QuietButton()) }
            Button { model.newSession(); model.compactHistoryVisible = false } label: { Label("New chat", systemImage: "square.and.pencil") }.buttonStyle(QuietButton())
            WorkspaceHistory(model: model, rename: rename, forget: { forgetID = $0 }, selected: { model.compactHistoryVisible = false })
        }.padding(24).background(Theme.background)
    }
    private func rename(_ chat: LearningSession) { model.commitComposer?(); renameID = chat.id; renameTitle = chat.title }

    private func toolbar(compact: Bool, chatCovered: Bool) -> some View {
        HStack(spacing: 12) {
            IconButton(symbol: "sidebar.left", label: (compact ? model.compactHistoryVisible : model.sidebarVisible) ? "Hide chat history" : "Show chat history") { model.commitComposer?(); if compact { if model.compactHistoryVisible { model.backToChat() } else { model.showHistory() } } else { model.compactHistoryVisible = false; model.sidebarVisible.toggle() } }
            if model.workspaceRoute == .settings {
                Button { model.backToChat() } label: { Label("Back to chat", systemImage: "chevron.left") }.buttonStyle(.plain).font(.system(size: 13))
            } else {
                Text(model.active?.title ?? "Your chats").font(.system(size: 14, weight: .medium)).lineLimit(1).help(model.active?.title ?? "Your chats")
            }
            Spacer(minLength: 12)
            if chatCovered && hasTransientActivity {
                HStack(spacing: 8) {
                    Label(activityLabel, systemImage: model.voice.listening || model.voice.speaking ? "waveform" : "macwindow").lineLimit(1).font(.system(size: 12)).foregroundStyle(Theme.accent)
                    Button("Stop") { model.stopInteraction() }.buttonStyle(QuietButton())
                }
            }
            if model.workspaceRoute == .chat, let chat = model.active {
                if chat.duration > 0 { Text(chat.timerText).font(.system(size: 12, design: .monospaced)).monospacedDigit().foregroundStyle(Theme.muted) }
                Menu {
                    Button("Assistant") { model.setMode(.assistant) }
                    Button("Learn with hints") { model.setMode(.learn) }
                } label: { Text(chat.mode == .learn ? "Learn" : "Assistant").font(.system(size: 12)).foregroundStyle(Theme.muted) }.menuStyle(.borderlessButton).fixedSize().help("Choose chat mode")
                IconButton(symbol: "sidebar.right", label: model.inspector == nil ? "Show files and notes" : "Hide details") { if model.inspector == nil { model.showInspector(.notes) } else { model.closeInspector() } }
                Menu {
                    Button("Chat notes") { model.showInspector(.notes) }
                    Button("Files") { model.showInspector(.files) }
                    Divider()
                    Button("Rename…") { rename(chat) }
                    Button("Export chat…") { model.export(chat) }
                    Button("Forget chat…", role: .destructive) { forgetID = chat.id }
                    Divider()
                    Toggle("Read typed replies aloud", isOn: $model.readAloud)
                    if chat.mode == .learn {
                        Button("Start step-by-step guide…") { if GuideStart.needsConfirmation(draft: model.draft, attachmentCount: model.pendingFiles.count) { confirmGuide = true } else { model.startGuide() } }.disabled(model.busy || model.paused)
                        Button("Show full walkthrough…") { walkthrough = true }.disabled(chat.messages.isEmpty || model.busy)
                    }
                    Menu("Focus timer") {
                        Button("30 minutes") { model.setFocus(minutes: 30) }
                        Button("60 minutes") { model.setFocus(minutes: 60) }
                        Button("No timer") { model.setFocus(minutes: 0) }
                    }
                    Button(model.paused ? "Resume chat" : "Pause chat") { model.togglePause() }
                    Button("Close chat") { model.complete() }
                    Divider()
                    Button("Settings…") { model.openSettings() }
                } label: { Label("Chat actions", systemImage: "ellipsis").labelStyle(.iconOnly).frame(width: 30, height: 30) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Chat actions")
            }
        }.padding(.horizontal, 18).frame(height: 52)
    }

    private var hasTransientActivity: Bool { model.busy || model.context.hasSelection || model.voice.starting || model.voice.listening || model.voice.speaking || model.conversation }
    private var activityLabel: String {
        if model.voice.starting { return "Starting microphone…" }
        if model.voice.listening { return "Listening" }
        if model.voice.speaking { return "Speaking" }
        if model.busy { return "Thinking…" }
        if model.conversation { return "Conversation on" }
        return model.context.live ? "Live window" : "Window shared"
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.closeInspector() } label: { Label("Back to chat", systemImage: "chevron.left") }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                Menu("Details") { Button("Notes") { model.showInspector(.notes) }; Button("Files") { model.showInspector(.files) } }.font(.system(size: 12)).fixedSize()
            }.padding(16)
            Rectangle().fill(Theme.line).frame(height: 1)
            Group {
                switch model.inspector {
                case .notes:
                    if let chat = model.active { WorkspaceNotes(model: model, session: chat) } else { Text("Choose a chat to see its notes.").foregroundStyle(Theme.muted) }
                case .files:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Files").font(.system(size: 22, weight: .medium))
                            if model.active?.files.isEmpty != false { Text("Files you attach to this chat appear here.").foregroundStyle(Theme.muted) }
                            ForEach(model.active?.files ?? []) { file in FileChip(record: file, among: model.active?.files ?? [], model: model, removable: SentFile.canRemove(id: file.id, session: model.active)) }
                            Button("Attach files…") { model.attachFiles() }.buttonStyle(QuietButton()).disabled(model.importing)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    }
                case .file(let id):
                    if let record = model.active?.files.first(where: { $0.id == id }), let store = model.fileStore {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(record.name).font(.system(size: 13, weight: .medium)).textSelection(.enabled).padding(16)
                            FilePreviewView(record: record, store: store).id(id)
                        }
                    } else { Text("This file is no longer available.").foregroundStyle(Theme.muted) }
                case .context:
                    if let image = model.contextPreview { Image(nsImage: image).resizable().scaledToFit().padding(20) }
                    else { Text("No window preview is held. Choose Live to keep a local preview.").foregroundStyle(Theme.muted).padding(24) }
                case nil: EmptyView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Theme.fillRaised)
    }
}

private struct WorkspaceHistory: View {
    @ObservedObject var model: AppModel
    var rename: (LearningSession) -> Void
    var forget: (UUID) -> Void
    var selected: () -> Void = {}
    @FocusState private var searchFocused: Bool
    private var chats: [LearningSession] { HistoryLists.sidebar(model.sessions, query: model.historyQuery, searchVisible: true) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search chats", text: $model.historyQuery, prompt: Text("Search chats").foregroundStyle(Theme.muted)).textFieldStyle(.plain).focused($searchFocused).accessibilityLabel("Search messages, notes, and files")
                if !model.historyQuery.isEmpty { Button { model.historyQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search").foregroundStyle(Theme.muted) }
            }.font(.system(size: 12)).padding(9).background(Theme.fillRaised).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if chats.isEmpty { Text(model.historyQuery.isEmpty ? "Your chats will be here." : "No chats found.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(12) }
                    ForEach(chats) { chat in
                        Button { model.navigateToChat(chat.id); selected() } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(chat.title).font(.system(size: 13)).lineLimit(1)
                                    if chat.unsentDraft != nil || !chat.pendingAttachments.isEmpty { Image(systemName: "pencil").font(.system(size: 10)).accessibilityLabel("Unsent draft") }
                                }
                                if !model.historyQuery.isEmpty { Text(ChatListLine.text(from: chat.historyPreview(matching: model.historyQuery)) ?? "").font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(2) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 10)
                                .background(chat.id == model.activeID && model.workspaceRoute == .chat ? Theme.fillPressed : .clear).clipShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).help(chat.title).contextMenu {
                            Button("Rename…") { rename(chat) }; Button("Export chat…") { model.export(chat) }; Button("Forget chat…", role: .destructive) { forget(chat.id) }
                        }
                    }
                }.padding(.horizontal, 12)
            }
        }.onAppear { if model.compactHistoryVisible { searchFocused = true } }
        .onChange(of: model.historyFocus) { searchFocused = true }
    }
}

private struct WorkspaceNotes: View {
    @ObservedObject var model: AppModel
    let session: LearningSession
    @State private var note = ""
    @State private var noteID: UUID?
    @State private var storedNote = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Notes").font(.system(size: 22, weight: .medium))
                Text(session.mode == .learn ? "Keep what clicked." : "A little space to keep the useful parts.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                TextEditor(text: $note).font(.system(size: 15)).scrollContentBackground(.hidden).frame(minHeight: 180).padding(10).background(Theme.background).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Chat notes")
                if let steps = session.guide?.savedSteps { Text("Saved guide").font(.system(size: 14, weight: .medium)); Text(steps).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled) }
                Text("Saved with this chat").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }
        .onAppear { if noteID != session.id || note == storedNote { note = session.takeaway }; storedNote = session.takeaway; noteID = session.id }
        .onChange(of: session.id) { note = session.takeaway; storedNote = session.takeaway; noteID = session.id }
        .onChange(of: session.takeaway) { if note == storedNote { note = session.takeaway }; storedNote = session.takeaway }
        .onChange(of: note) { guard noteID == session.id else { return }; storedNote = note; if note != session.takeaway { model.setTakeaway(note, for: session.id) } }
    }
}
