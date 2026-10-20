import SwiftUI
import LiltCore

private struct CompanionReplyHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The approved Pearl composition: ready, question and reply are one continuous
/// material panel. The native editor below never changes identity between them.
struct CompactCompanionView: View {
    @ObservedObject var model: AppModel
    var chatVisible = true
    private var account: ChatGPTAccount { model.provider.account }
    private var expanded: Bool { model.companionExpanded }
    private var hasReply: Bool { model.active?.messages.isEmpty == false || model.busy || model.active?.guide != nil }
    private var voiceActive: Bool { model.voice.starting || model.voice.listening || model.voice.speaking || model.conversation }
    private var sendReady: Bool { chatVisible && account.permitsPlanUsage && model.hasInput && !model.paused && model.active != nil && !model.importing }
    private var voiceStatus: String {
        if model.voice.starting { return "Starting microphone…" }
        if model.voice.listening { return model.conversation ? "Conversation · listening" : "Listening…" }
        if model.voice.speaking { return model.conversation ? "Conversation · speaking" : "Reading aloud" }
        return "Conversation on"
    }
    private var visibleMessages: [Message] {
        let messages = model.active?.messages ?? []
        if model.companionShowsEarlierMessages { return messages }
        guard let index = messages.lastIndex(where: { $0.role == "user" }) else { return Array(messages.suffix(1)) }
        return Array(messages[index...])
    }
    var body: some View {
        GeometryReader { geometry in
            panel(availableHeight: geometry.size.height)
        }
    }
    private func panel(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            header.frame(height: expanded ? 43 : 0).clipped().accessibilityHidden(!expanded)
            ScrollView {
                VStack(spacing: 0) {
                    if expanded {
                        if let warning = ShortcutNotice.text(model.shortcutWarning) {
                            Text(warning).font(.system(size: 11)).foregroundStyle(Theme.warning)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 17).padding(.bottom, 9)
                        }
                    if model.context.hasSelection { contextChip.padding(.horizontal, 16).padding(.bottom, 9) }
                    if hasReply { replies(availableHeight: availableHeight).padding(.horizontal, 17).padding(.bottom, 8) }
                    if let error = model.error { errorNotice(error).padding(.horizontal, 16).padding(.bottom, 8) }
                    if model.canRetry {
                        Button("Retry message", systemImage: "arrow.clockwise") { model.retry() }
                            .buttonStyle(ActionButton()).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                            .disabled(!model.retryEnabled).accessibilityIdentifier("vale.retryMessage")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 17).padding(.bottom, 9)
                    }
                    if model.paused { statusLine("Paused", symbol: "pause.fill", action: "Resume", run: model.togglePause) }
                    if voiceActive { statusLine(voiceStatus, symbol: model.voice.listening ? "mic.fill" : "waveform", action: "Stop", run: model.stopInteraction) }
                    if let status = model.importStatus { AttachmentImportStatus(text: status).padding(.horizontal, 17).padding(.bottom, 8) }
                    if !model.pendingFiles.isEmpty {
                        ScrollView(.horizontal) { HStack(spacing: 6) { ForEach(model.pendingFiles) { FileChip(record: $0, among: model.pendingFiles, model: model, removable: true) } } }
                            .scrollIndicators(.hidden).frame(height: 30).padding(.horizontal, 16).padding(.bottom, 6)
                    }
                    if model.active?.mode == .learn { learnActions }
                    if !account.permitsPlanUsage { connectionStatus }
                    }
                }.frame(maxWidth: .infinity)
            }.scrollIndicators(.automatic)
                .frame(maxHeight: expanded ? .infinity : 0)
                .accessibilityHidden(!expanded)
            composer.fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.fillRaised.opacity(0.16))
        .onChange(of: model.draft) { _, text in if !text.isEmpty && chatVisible { model.companionExpanded = true } }
        .onChange(of: model.busy) { _, busy in if busy { model.companionExpanded = true } }
        .onChange(of: model.pendingFiles.count) { _, count in if count > 0 && chatVisible { model.companionExpanded = true } }
        .onChange(of: model.shortcutWarning) { _, warning in if warning != nil && chatVisible { model.companionExpanded = true } }
        .onChange(of: model.error) { _, error in if error != nil && chatVisible { model.companionExpanded = true } }
        .onChange(of: model.context.hasSelection) { _, selected in if selected { model.companionExpanded = true } }
        .onChange(of: model.activeID) { model.companionShowsEarlierMessages = false; model.companionReplyHeight = 0 }
        .dropDestination(for: URL.self) { urls, _ in
            guard chatVisible else { return false }
            model.expandCompanion(); model.keepDroppedLinks(urls)
            let files = FieldDrop.attaches(urls); if !files.isEmpty { model.importDroppedFiles(files) }
            return !files.isEmpty || DroppedLink.text(from: urls) != nil
        }
    }
    private var header: some View {
        HStack(spacing: 9) {
            LogoMark(size: 20)
            Text("Vale").font(.system(size: 12, weight: .medium))
            if model.active?.mode == .learn { Text("Learn").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted) }
            Spacer(minLength: 0)
            CompactOverflowMenu(model: model)
            Button { model.collapseCompanion() } label: { Label("Collapse Vale", systemImage: "chevron.down").labelStyle(.iconOnly).font(.system(size: 11, weight: .medium)).frame(width: 22, height: 28) }
                .buttonStyle(ActionButton()).help("Collapse Vale, keeping your draft")
        }.padding(.horizontal, 15).foregroundStyle(Theme.ink)
    }
    private var contextChip: some View {
        HStack(spacing: 7) {
            Menu {
                Button("Preview shared window") { model.previewContext() }.disabled(model.context.preview == nil)
                Toggle("Live locally", isOn: Binding(get: { model.context.live }, set: { if $0 { model.context.startLive() } else { model.context.stopLive() } })).disabled(model.paused)
                Button("Choose another window…") { model.context.choose() }
                Divider()
                Text("Captured only when you ask. Live keeps one local preview.")
            } label: {
                HStack(spacing: 6) { Image(systemName: model.context.live ? "rectangle.inset.filled.and.person.filled" : "macwindow"); Text(model.contextName ?? "Selected window").lineLimit(1) }
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ink)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                .accessibilityLabel("Shared window: \(model.contextName ?? "Selected window")").help("Window context · preview and Live options")
            Button { model.stopSharing() } label: { Label("Remove window context", systemImage: "xmark").labelStyle(.iconOnly).font(.system(size: 9, weight: .medium)) }
                .buttonStyle(ActionButton()).help("Stop window sharing")
        }.padding(.horizontal, 9).frame(height: 27).background(Theme.fill.opacity(0.7)).clipShape(Capsule())
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func replies(availableHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if let guide = model.active?.guide { GuideCard(model: model, guide: guide).padding(.horizontal, -18).padding(.top, -10) }
                    ForEach(visibleMessages) { message in
                        CompactCompanionMessage(model: model, message: message).id(message.id)
                    }
                    if model.busy {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").font(.system(size: 12)).foregroundStyle(Theme.muted) }.padding(.vertical, 3)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { geometry in Color.clear.preference(key: CompanionReplyHeightKey.self, value: geometry.size.height) })
            }.scrollIndicators(.automatic)
                .frame(height: CompanionPresentation.replyViewportHeight(for: model, availableHeight: availableHeight))
                .onPreferenceChange(CompanionReplyHeightKey.self) { height in
                    guard chatVisible, model.chatSurfaceVisible, abs(model.companionReplyHeight - height) > 1 else { return }
                    DispatchQueue.main.async { model.companionReplyHeight = height }
                }
                .onChange(of: model.active?.messages.last?.id) { _, id in
                    guard model.companionShowsEarlierMessages, let id else { return }
                    proxy.scrollTo(id, anchor: .top)
                }
        }
    }
    private var composer: some View {
        let draftID = model.activeID
        let editorHeight = expanded ? max(hasReply ? 36 : 70, min(110, model.companionInputHeight)) : 26
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: expanded ? 0 : 7) {
                Button { model.expandCompanion() } label: { LogoMark(size: 19).frame(width: 24, height: 26) }
                    .buttonStyle(ActionButton()).help("Expand Vale").accessibilityLabel("Expand Vale")
                    .frame(width: expanded ? 0 : 24).opacity(expanded ? 0 : 1).clipped().accessibilityHidden(expanded)
                ZStack(alignment: .topLeading) {
                    if model.active != nil && model.draft.isEmpty { Text(expanded ? (hasReply ? "Ask a follow-up…" : "Ask Vale anything…") : "Ask Vale…").font(.system(size: expanded ? 14 : 12)).foregroundStyle(Theme.muted.opacity(0.8)).padding(.leading, 2).padding(.top, 5).allowsHitTesting(false).accessibilityHidden(true) }
                    DraftEditor(text: Binding(get: { model.draft }, set: { if model.activeID == draftID { model.editDraft($0) } }), draftID: draftID, focusToken: model.composerFocus, fontSize: expanded ? 14 : 12, ownsDraft: { model.activeID == draftID }, permitsFocus: { _ in model.active != nil && model.chatSurfaceVisible && chatVisible }, submit: {
                        if chatVisible && model.chatSurfaceVisible && account.permitsPlanUsage && ComposerReturn.sends(whileWaiting: model.busy) { model.companionExpanded = true; model.send() }
                    }, cancel: { if let escape = model.requestCompanionEscape { escape() } else { model.stopInteraction() } }, pasteFiles: { model.expandCompanion(); model.importDroppedFiles($0) }, pasteImage: { model.expandCompanion(); model.pasteImage($0) }, pastePDF: { model.expandCompanion(); model.pastePDF($0) }, installCommit: { model.commitComposer = $0 }, onMeasuredHeight: { height in
                        guard chatVisible, model.chatSurfaceVisible else { return }
                        let value = min(110, max(26, height)); if abs(model.companionInputHeight - value) > 1 { model.companionInputHeight = value }
                    })
                    .id("vale.continuous.composer")
                    .allowsHitTesting(model.active != nil).accessibilityHidden(model.active == nil)
                    if model.active == nil {
                        Button { model.newSession(); model.expandCompanion() } label: {
                            Text("Ask Vale…").font(.system(size: expanded ? 14 : 12)).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.top, 5).padding(.leading, 2)
                        }.buttonStyle(.plain).accessibilityLabel("Start a new chat")
                    }
                }.frame(height: editorHeight)
                micButton.frame(width: expanded ? 0 : 25).opacity(expanded ? 0 : 1).clipped().accessibilityHidden(expanded)
                CompactOverflowMenu(model: model).frame(width: expanded ? 0 : 25).opacity(expanded ? 0 : 1).clipped().accessibilityHidden(expanded)
            }
            HStack(spacing: 8) {
                attachmentMenu
                micButton
                if model.active?.webEnabled == true { Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(Theme.accent).help("Web search on").accessibilityLabel("Web search on") }
                Spacer(minLength: 3)
                submitButton
            }.frame(height: expanded ? 43 : 0).opacity(expanded ? 1 : 0).clipped().accessibilityHidden(!expanded)
        }.padding(.horizontal, expanded ? 16 : 11).padding(.top, expanded ? 0 : 9.5).padding(.bottom, expanded ? 8 : 9.5)
    }
    private var attachmentMenu: some View {
        Menu {
            Button("Attach files…", systemImage: "paperclip") { model.attachFiles() }.disabled(model.importing)
            Button("Share a window…", systemImage: "macwindow") { model.context.choose() }.disabled(model.paused)
            if model.context.hasSelection {
                Button("Preview shared window") { model.previewContext() }.disabled(model.context.preview == nil)
                Toggle("Live locally", isOn: Binding(get: { model.context.live }, set: { if $0 { model.context.startLive() } else { model.context.stopLive() } })).disabled(model.paused)
                Button("Stop window sharing") { model.stopSharing() }
            }
            Divider()
            Toggle("Web search", isOn: Binding(get: { model.active?.webEnabled == true }, set: { model.setWeb($0) })).disabled(!WebToggle.changes(waiting: model.busy))
        } label: {
            Label("Add context", systemImage: "plus").labelStyle(.iconOnly).font(.system(size: 15, weight: .regular)).frame(width: 32, height: 32)
                .background(Theme.fill.opacity(0.65)).clipShape(Circle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Attach files, share a window, or enable Web")
    }
    private var micButton: some View {
        Button {
            model.expandCompanion(); model.toggleVoice()
        } label: {
            Label(model.voice.listening ? "Finish speaking" : model.voice.speaking || model.voice.starting ? "Stop voice" : "Dictate a question", systemImage: model.voice.listening ? "stop.fill" : "mic")
                .labelStyle(.iconOnly).font(.system(size: expanded ? 14 : 12, weight: .regular))
                .foregroundStyle(voiceActive ? Theme.accent : Theme.ink)
                .frame(width: expanded ? 32 : 25, height: expanded ? 32 : 26)
                .background(expanded ? Theme.fill.opacity(0.65) : .clear).clipShape(Circle())
        }.buttonStyle(ActionButton()).disabled(model.active == nil || model.paused || !account.permitsPlanUsage)
            .help(model.voice.listening ? "Finish speaking and send" : "Dictate one question")
    }
    @ViewBuilder private var submitButton: some View {
        if model.busy {
            Button { model.stopIfSeparate() } label: { Label("Stop response", systemImage: "stop.fill").labelStyle(.iconOnly).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.onAction).frame(width: 34, height: 34).background(Theme.action).clipShape(Circle()) }
                .buttonStyle(ActionButton()).help("Stop response (Escape)")
        } else if account.permitsPlanUsage {
            Button { if chatVisible { model.send() } } label: { Label("Send message", systemImage: "arrow.up").labelStyle(.iconOnly).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.onAction).frame(width: 34, height: 34).background(Theme.action).clipShape(Circle()) }
                .buttonStyle(ActionButton()).disabled(!sendReady).help("Send message (Return)")
        } else if account.isSigningIn {
            Button("Cancel connection") { account.cancelSignIn() }.font(.system(size: 11)).buttonStyle(ActionButton()).foregroundStyle(Theme.accent)
        } else {
            Button(account.needsIdentityValidation ? "Retry connection" : "Connect ChatGPT") {
                if account.needsIdentityValidation { account.refreshModels() }
                else if account.isSignedIn { account.enablePlanUsage() }
                else { account.signIn() }
            }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).frame(height: 32)
                .foregroundStyle(Theme.onAction).background(Theme.action).clipShape(Capsule()).buttonStyle(ActionButton()).disabled(account.isSigningOut)
        }
    }
    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(account.isSigningIn ? "Finish connecting in your browser." : account.needsIdentityValidation ? "Verify your ChatGPT connection to send." : "Connect ChatGPT to send. Your draft stays here.")
            if let error = account.error { Text(error).foregroundStyle(Theme.warning).lineLimit(3) }
        }.font(.system(size: 11)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 17).padding(.bottom, 10)
    }
    private var learnActions: some View {
        HStack(spacing: 16) {
            Button("Hint", systemImage: "lightbulb") { model.nextHint() }
            Button("Point it out", systemImage: "cursorarrow.rays") { model.pointItOut() }.disabled(!model.context.hasSelection)
            Spacer(minLength: 0)
        }.buttonStyle(ActionButton()).font(.system(size: 11)).foregroundStyle(Theme.muted).disabled(model.busy || model.paused || !account.permitsPlanUsage).padding(.horizontal, 17).padding(.bottom, 12)
    }
    private func statusLine(_ text: String, symbol: String, action: String, run: @escaping () -> Void) -> some View {
        HStack(spacing: 6) { Label(text, systemImage: symbol).lineLimit(1); Spacer(minLength: 3); Button(action, action: run).buttonStyle(ActionButton()).foregroundStyle(Theme.accent) }
            .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.horizontal, 17).padding(.bottom, 10)
    }
    private func errorNotice(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 5) { Text(error).font(.system(size: 11)).foregroundStyle(Theme.warning).lineLimit(4); Spacer(minLength: 0); Button { model.error = nil } label: { Label("Dismiss message", systemImage: "xmark").labelStyle(.iconOnly).font(.system(size: 9)) }.buttonStyle(ActionButton()) }
            HStack(spacing: 12) {
                if model.errorOffersSettings { Button("Open Settings") { model.openSettings() } }
                if model.context.hasSelection { Button("Change window") { model.context.choose() } }
                if let id = model.deletionToRetry { Button("Retry Forget") { model.delete(id) } }
            }.font(.system(size: 11)).buttonStyle(ActionButton()).foregroundStyle(Theme.accent)
        }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(Theme.warning.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
