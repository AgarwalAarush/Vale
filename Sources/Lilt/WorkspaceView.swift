import SwiftUI
import LiltCore

enum WorkspaceRoute: String { case chat, settings }
enum WorkspaceInspector: Equatable { case notes, files, file(UUID), context }

/// Keep panel decisions in one place so editor focus follows the visible layout.
struct WorkspaceLayout {
    static let sidebarThreshold: CGFloat = 860
    static let sidebarWidth: CGFloat = 200
    static let inspectorWidth: CGFloat = 320
    let width: CGFloat
    let sidebarVisible: Bool
    let historyOverlay: Bool
    let inspectorOpen: Bool
    var compact: Bool { width < Self.sidebarThreshold }
    var showsSidebar: Bool { sidebarVisible && !compact }
    var inlineInspector: Bool { width - (showsSidebar ? Self.sidebarWidth + 1 : 0) - Self.inspectorWidth - 1 >= 560 }
    var chatVisible: Bool { (!inspectorOpen || inlineInspector) && (!compact || !historyOverlay) }
}

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @AppStorage("valeAppearance") private var appearance = "system"
    @State private var renameID: UUID?
    @State private var renameTitle = ""
    @State private var forgetID: UUID?
    @State private var walkthrough = false
    @State private var confirmGuide = false
    @State private var planConfirmationAccount: String?

    private var colorScheme: ColorScheme? { appearance == "light" ? .light : appearance == "dark" ? .dark : nil }
    var body: some View {
        GeometryReader { geometry in
            let layout = WorkspaceLayout(width: geometry.size.width, sidebarVisible: model.sidebarVisible, historyOverlay: model.compactHistoryVisible, inspectorOpen: model.inspector != nil)
            let chatVisible = model.workspaceRoute == .chat && layout.chatVisible
            HStack(spacing: 0) {
                if layout.showsSidebar {
                    navigation.frame(width: WorkspaceLayout.sidebarWidth)
                    Rectangle().fill(Theme.line).frame(width: 1)
                }
                HStack(spacing: 0) {
                    ZStack {
                        // Keep the actual NSTextView mounted across every secondary route.
                        CoachView(model: model, chatVisible: chatVisible)
                            .opacity(chatVisible ? 1 : 0)
                            .allowsHitTesting(chatVisible)
                            .accessibilityHidden(!chatVisible)
                        if model.workspaceRoute == .settings { SettingsView(model: model) }
                        else if model.inspector != nil && !layout.inlineInspector { inspector(inline: false) }
                        else if layout.compact && model.compactHistoryVisible { compactNavigation }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.workspaceRoute == .chat, layout.inlineInspector, model.inspector != nil {
                        Rectangle().fill(Theme.line).frame(width: 1)
                        inspector(inline: true).frame(width: WorkspaceLayout.inspectorWidth)
                    }
                }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }.background(Theme.background).foregroundStyle(Theme.ink)
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
        .onReceive(NotificationCenter.default.publisher(for: NativeWorkspaceToolbar.command, object: model)) { notification in
            switch notification.userInfo?["action"] as? String {
            case "rename": if let chat = model.active { rename(chat) }
            case "forget": forgetID = model.activeID
            case "walkthrough": walkthrough = true
            case "guide":
                if GuideStart.needsConfirmation(draft: model.draft, attachmentCount: model.pendingFiles.count) { confirmGuide = true }
                else { model.startGuide() }
            default: break
            }
        }
        .onChange(of: model.provider.account.permitsPlanUsage) { wasEnabled, enabled in
            let account = model.provider.account
            guard !wasEnabled, enabled, !account.isDisposableFixture, !account.needsIdentityValidation,
                  let id = account.activeAccountID,
                  !UserDefaults.standard.bool(forKey: "vale.planUsageAcknowledged.\(id)") else { return }
            planConfirmationAccount = id
        }
        .alert("ChatGPT is connected", isPresented: Binding(get: { planConfirmationAccount != nil }, set: { if !$0 { acknowledgePlanUsage() } })) {
            Button("Got it") { acknowledgePlanUsage() }
        } message: { Text("Eligible requests in Vale use your ChatGPT plan and app limits. You can manage usage or disconnect Vale in ChatGPT Settings → Usage. Your draft is ready when you choose to send it.") }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspaceHistory(model: model, rename: rename, forget: { forgetID = $0 }).padding(.top, 12)
            Button { model.openSettings() } label: {
                Label("Settings", systemImage: "gearshape").font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 7)
            }.buttonStyle(ActionButton(background: model.workspaceRoute == .settings ? Theme.fillPressed : .clear))
                .foregroundStyle(model.workspaceRoute == .settings ? Theme.ink : Theme.muted).padding(8)
        }.frame(maxHeight: .infinity).background(Theme.rail)
    }
    private var compactNavigation: some View {
        WorkspaceHistory(model: model, rename: rename, forget: { forgetID = $0 }, selected: { model.compactHistoryVisible = false })
            .padding(.top, 12).padding(.bottom, 12).background(Theme.background)
    }
    private func rename(_ chat: LearningSession) { model.commitComposer?(); renameID = chat.id; renameTitle = chat.title }
    private func acknowledgePlanUsage() {
        if let id = planConfirmationAccount { UserDefaults.standard.set(true, forKey: "vale.planUsageAcknowledged.\(id)") }
        planConfirmationAccount = nil
    }

    private func inspector(inline: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if model.inspector == .context { Text("Window preview").fontWeight(.medium) }
                if case .file = model.inspector { Text("File preview").fontWeight(.medium) }
                Button { model.showInspector(.notes) } label: { Text("Notes").padding(.horizontal, 8).padding(.vertical, 6) }
                    .buttonStyle(ActionButton(background: model.inspector == .notes ? Theme.fill : .clear))
                    .accessibilityValue(model.inspector == .notes ? "Selected" : "")
                Button { model.showInspector(.files) } label: { Text("Files").padding(.horizontal, 8).padding(.vertical, 6) }
                    .buttonStyle(ActionButton(background: model.inspector == .files ? Theme.fill : .clear))
                    .accessibilityValue(model.inspector == .files ? "Selected" : "")
                if inline {
                    Spacer(minLength: 0)
                    IconButton(symbol: "xmark", label: "Close details") { model.closeInspector() }
                }
            }.font(.system(size: 12)).padding(.horizontal, 16).padding(.vertical, 10)
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
                        }.frame(maxWidth: 680, alignment: .leading).padding(24).frame(maxWidth: .infinity)
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
    private var chats: [LearningSession] {
        HistoryLists.sidebar(model.sessions, query: model.historyQuery, searchVisible: true).filter { chat in
            let pristine = chat.id == model.activeID && !model.importing && chat.takeaway.isEmpty && chat.guide == nil && EmptyChat.canDiscard(title: chat.title, messageCount: chat.messages.count, draft: chat.draft, fileCount: chat.files.count, duration: chat.duration, mode: chat.mode, webEnabled: chat.webEnabled)
            return !pristine
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search chats", text: $model.historyQuery, prompt: Text("Search chats").foregroundStyle(Theme.muted)).textFieldStyle(.plain).focused($searchFocused).accessibilityLabel("Search messages, notes, and files")
                if !model.historyQuery.isEmpty { Button { model.historyQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(ActionButton()).accessibilityLabel("Clear search").foregroundStyle(Theme.muted) }
            }.font(.system(size: 12)).padding(.horizontal, 7).padding(.vertical, 6).background(Theme.fillRaised).clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(searchFocused ? Theme.accent : Theme.line, lineWidth: 1)).padding(.horizontal, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if chats.isEmpty { Text(model.historyQuery.isEmpty ? "Your chats will be here." : "No chats found.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(12) }
                    ForEach(chats) { chat in
                        Button { model.navigateToChat(chat.id); selected() } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(chat.title).font(.system(size: 13)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    if chat.unsentDraft != nil || !chat.pendingAttachments.isEmpty { Image(systemName: "pencil").font(.system(size: 10)).help("Unsent draft").accessibilityLabel("Unsent draft") }
                                }
                                if !model.historyQuery.isEmpty { Text(chat.historyExcerpt(matching: model.historyQuery)).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 7)
                        }.buttonStyle(ActionButton(background: chat.id == model.activeID && model.workspaceRoute == .chat ? Theme.fillPressed : .clear)).help(chat.title)
                            .accessibilityValue(chat.id == model.activeID && model.workspaceRoute == .chat ? "Selected chat" : "")
                            .contextMenu {
                            Button("Rename…") { rename(chat) }; Button("Export chat…") { model.export(chat) }; Button("Forget chat…", role: .destructive) { forget(chat.id) }
                        }
                    }
                }.padding(.horizontal, 8)
            }
        }.frame(maxHeight: .infinity).onAppear { if model.compactHistoryVisible { searchFocused = true } }
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
            }.frame(maxWidth: 680, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }
        .onAppear { if noteID != session.id || note == storedNote { note = session.takeaway }; storedNote = session.takeaway; noteID = session.id }
        .onChange(of: session.id) { note = session.takeaway; storedNote = session.takeaway; noteID = session.id }
        .onChange(of: session.takeaway) { if note == storedNote { note = session.takeaway }; storedNote = session.takeaway }
        .onChange(of: note) { guard noteID == session.id else { return }; storedNote = note; if note != session.takeaway { model.setTakeaway(note, for: session.id) } }
    }
}
