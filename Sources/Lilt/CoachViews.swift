import SwiftUI
import LiltCore

struct CoachView: View {
    @ObservedObject var model: AppModel
    var chatVisible = true
    @State private var composerHeight: CGFloat = CGFloat(ComposerHeight.minimum)
    @State private var composerFocused = false
    private var account: ChatGPTAccount { model.provider.account }
    private var sendReady: Bool { account.permitsPlanUsage && model.hasInput && PausedTyping.allowsQuestion(paused: model.paused) && model.active != nil && !model.importing }
    private var webEnabled: Bool { model.active?.webEnabled == true }
    private var empty: Bool { model.active?.messages.isEmpty == true && model.active?.guide == nil && !model.busy }
    private var voiceActive: Bool { model.voice.starting || model.voice.listening || model.voice.speaking || model.conversation }
    private var voiceStatus: String {
        if model.voice.starting { return "Starting microphone…" }
        if model.voice.listening { return model.conversation ? "Conversation · listening" : "Listening" }
        if model.voice.speaking { return model.conversation ? "Conversation · speaking" : "Speaking" }
        return "Conversation on"
    }
    var body: some View {
        VStack(spacing: 0) {
            if let warning = ShortcutNotice.text(model.shortcutWarning) { notice(warning) }
            if model.active?.showsEarlierContextNotice == true {
                Text("Using recent messages. Full history stays saved here.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 12)
            }
            if let guide = model.active?.guide { GuideCard(model: model, guide: guide).frame(maxWidth: 728) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let session = model.active {
                            ForEach(session.messages) { message in CoachMessage(model: model, session: session, message: message).id(message.id) }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Choose a chat or start a new one.").font(.system(size: 20))
                                Button("New chat") { model.newSession() }.buttonStyle(QuietButton())
                            }.padding(.vertical, 12)
                        }
                        if model.busy { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").font(.system(size: 13)).foregroundStyle(Theme.muted) }.id("thinking") }
                        Color.clear.frame(height: 1).id("bottom")
                    }.frame(maxWidth: 680, alignment: .leading).padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20).frame(maxWidth: .infinity)
                }.clipped()
                .onChange(of: model.active?.messages.count) { revealLatest(proxy) }
                .onChange(of: model.busy) { revealLatest(proxy) }
                .onChange(of: model.activeID) { revealLatest(proxy) }
            }.frame(minHeight: 0, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                if let error = model.error {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) { Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 4); IconButton(symbol: "xmark", label: "Dismiss message") { model.error = nil } }
                        HStack(spacing: 16) {
                            if model.errorOffersSettings { Button("Open Settings") { model.openSettings() } }
                            if model.context.hasSelection { Button("Change window") { model.context.choose() } }
                            if let id = model.deletionToRetry { Button("Retry Forget") { model.delete(id) } }
                        }.font(.system(size: 12)).buttonStyle(ActionButton()).foregroundStyle(Theme.accent)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.warning.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if model.canRetry { Button("Retry message") { model.retry() }.buttonStyle(ActionButton()).foregroundStyle(Theme.accent).font(.system(size: 13)).disabled(!account.permitsPlanUsage) }
                if model.active != nil {
                    if model.context.hasSelection { ContextStrip(model: model).fixedSize(horizontal: false, vertical: true) }
                    if model.paused { HStack { Text("Paused · mic and sharing off").foregroundStyle(Theme.muted); Spacer(); Button("Resume") { model.togglePause() }.buttonStyle(ActionButton()).foregroundStyle(Theme.accent) }.font(.system(size: 12)) }
                    if model.active?.mode == .learn {
                        HStack(spacing: 16) {
                            Button { model.nextHint() } label: { Label("Hint", systemImage: "lightbulb") }
                            Button { model.pointItOut() } label: { Label("Point it out", systemImage: "cursorarrow.rays") }
                            Spacer()
                        }.buttonStyle(ActionButton()).font(.system(size: 12)).foregroundStyle(Theme.muted).disabled(model.busy || model.paused || !account.permitsPlanUsage)
                    }
                    if empty, account.permitsPlanUsage, let session = model.active { EmptyGreeting(model: model, session: session) }
                    if voiceActive {
                        HStack(spacing: 8) {
                            Label(voiceStatus, systemImage: model.voice.listening ? "mic.fill" : "waveform").foregroundStyle(Theme.accent)
                            Spacer(minLength: 8)
                            Button("Stop voice") { model.stopInteraction() }.buttonStyle(ActionButton()).help("Stop voice and window sharing")
                        }.font(.system(size: 12))
                    }
                    connectionStatus
                    composer
                }
            }.fixedSize(horizontal: false, vertical: true).layoutPriority(1).frame(maxWidth: 680).padding(.horizontal, 24).padding(.bottom, 20).frame(maxWidth: .infinity)
        }.background(Theme.background)
        .dropDestination(for: URL.self) { urls, _ in
            model.keepDroppedLinks(urls)
            let files = FieldDrop.attaches(urls); if !files.isEmpty { model.importDroppedFiles(files) }
            return !files.isEmpty || DroppedLink.text(from: urls) != nil
        }
    }
    @ViewBuilder private var connectionStatus: some View {
        if account.permitsPlanUsage {
            HStack(spacing: 8) {
                Text("Using ChatGPT plan")
                Link("Manage usage", destination: URL(string: "https://chatgpt.com/settings/usage")!).foregroundStyle(Theme.accent)
                Spacer(minLength: 0)
            }.font(.system(size: 12)).foregroundStyle(Theme.muted)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(account.isSigningIn ? "Finish connecting in your browser. Your draft stays here." : account.needsIdentityValidation ? "Verify your ChatGPT connection to send." : "Connect ChatGPT to send.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                if let error = account.error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
            }
        }
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if !model.pendingFiles.isEmpty { ScrollView(.horizontal) { HStack(spacing: 8) { ForEach(model.pendingFiles) { FileChip(record: $0, among: model.pendingFiles, model: model, removable: true) } } }.scrollIndicators(.hidden).fixedSize(horizontal: false, vertical: true) }
            ZStack(alignment: .topLeading) {
                if FieldPrompt.showsIdle(model.draft) { Text(model.busy ? "Add a thought for your next message…" : "Message Vale…").font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.top, 5).padding(.leading, 2).allowsHitTesting(false).accessibilityHidden(true) }
                DraftEditor(text: Binding(get: { model.draft }, set: { model.editDraft($0) }), draftID: model.activeID, focusToken: model.composerFocus, permitsFocus: { _ in
                    chatVisible && model.workspaceRoute == .chat
                }, submit: { if account.permitsPlanUsage && ComposerReturn.sends(whileWaiting: model.busy) { model.send() } }, cancel: { model.stopInteraction() }, pasteFiles: { model.importDroppedFiles($0) }, pasteImage: { model.pasteImage($0) }, pastePDF: { model.pastePDF($0) }, installCommit: { model.commitComposer = $0 }, onMeasuredHeight: { measured in
                    let height = CGFloat(ComposerHeight.clamped(Double(measured))); if abs(composerHeight - height) > 0.5 { composerHeight = height }
                }, onFocusChange: { composerFocused = $0 }).frame(height: composerHeight)
            }.help(account.permitsPlanUsage ? "Return sends. Shift–Return adds a line." : "Your draft is saved locally. Continue with ChatGPT to send. Shift–Return adds a line.")
            HStack(spacing: 8) {
                IconButton(symbol: "paperclip", label: "Attach files") { model.attachFiles() }.disabled(model.importing)
                if !model.context.hasSelection { IconButton(symbol: "macwindow", label: "Share a window") { model.context.choose() }.disabled(model.paused) }
                Menu {
                    Toggle("Web search", isOn: Binding(get: { model.active?.webEnabled == true }, set: { model.setWeb($0) })).disabled(!WebToggle.changes(waiting: model.busy))
                    Text("Availability depends on your ChatGPT account and selected model.")
                } label: {
                    Label(webEnabled ? "Web on" : "Web off", systemImage: "globe").foregroundStyle(webEnabled ? Theme.accent : Theme.muted)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(webEnabled ? "Web search is enabled for this chat. Availability depends on your account and model." : "Web search is off for this chat.")
                    .accessibilityLabel("Web search").accessibilityValue(webEnabled ? "On" : "Off")
                voiceControl
                Spacer(minLength: 4)
                submitControl
            }.buttonStyle(ActionButton()).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }.padding(10).background(Theme.fillRaised).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(composerFocused && chatVisible ? Theme.accent : Theme.line, lineWidth: 1))
    }
    @ViewBuilder private var voiceControl: some View {
        if voiceActive {
            if model.voice.listening { Button("Finish speaking") { model.toggleVoice() }.foregroundStyle(Theme.accent) }
        } else {
            Menu {
                Button("Talk") { model.toggleVoice() }.disabled(model.paused || !account.permitsPlanUsage)
                Button("Start conversation") { model.setConversation(true) }.disabled(model.paused || !account.permitsPlanUsage)
                Divider()
                Toggle("Read typed replies aloud", isOn: $model.readAloud)
                Text("Talk records one turn. Conversation listens again after each answer.")
            } label: { Label("Voice", systemImage: "mic") }
                .menuStyle(.borderlessButton).fixedSize().help("Talk or start a spoken conversation")
        }
    }
    @ViewBuilder private var submitControl: some View {
        if model.busy {
            Button { model.stopIfSeparate() } label: { Image(systemName: "stop.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.onAction).frame(width: 30, height: 30) }
                .buttonStyle(ActionButton(background: Theme.action, feedback: Theme.onAction)).help("Stop response (Escape)").accessibilityLabel("Stop response")
        } else if !account.permitsPlanUsage {
            if account.isSigningIn {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Button("Cancel") { account.cancelSignIn() }.buttonStyle(.bordered) }.accessibilityLabel("Connecting to ChatGPT")
            } else if account.needsIdentityValidation {
                Button("Retry connection") { account.refreshModels() }.buttonStyle(.borderedProminent).tint(Theme.action).disabled(account.isSigningOut)
            } else {
                Button("Continue with ChatGPT") { if account.isSignedIn { account.enablePlanUsage() } else { account.signIn() } }
                    .buttonStyle(.borderedProminent).tint(Theme.action).disabled(account.isSigningOut)
            }
        } else {
            Button { model.send() } label: { Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.onAction).frame(width: 30, height: 30) }
                .buttonStyle(ActionButton(background: Theme.action, feedback: Theme.onAction)).disabled(!sendReady).help("Send message (Return)").accessibilityLabel("Send message")
        }
    }
    private func notice(_ text: String) -> some View { Text(text).font(.system(size: 12)).foregroundStyle(Theme.warning).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
    private func revealLatest(_ proxy: ScrollViewProxy) {
        let latest = model.active?.messages.last
        let opensAtStart = QuestionScroll.opensAtTheStart(role: latest?.role, text: latest?.text ?? "")
        if model.busy, !opensAtStart { proxy.scrollTo("thinking", anchor: .bottom) }
        else if let id = latest?.id { proxy.scrollTo(id, anchor: opensAtStart ? .top : .bottom) }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

private struct CoachMessage: View {
    @ObservedObject var model: AppModel
    let session: LearningSession
    let message: Message
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if SpeakerTurn.trails(message.role) { Spacer(minLength: SpeakerTurn.leadingClearance).layoutPriority(-1) }
            VStack(alignment: .leading, spacing: 7) {
                MessageHeading(message: message)
                if !message.text.isEmpty { MessageText(message: message).font(.system(size: 15)).lineSpacing(6).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                if StoppedReply.shows(role: message.role, stopped: message.replyStopped) { Text(StoppedReply.label).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                if FailedAnswer.shows(failed: message.answerFailed, waiting: model.busy && message.id == session.messages.last?.id) { Text(FailedAnswer.label).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                if !message.attachments.isEmpty { MessageAttachments(model: model, session: session, records: message.attachments) }
                if message.highlightUnavailable { Label("Highlight unavailable · check your selected window", systemImage: "eye.slash").font(.system(size: 12)).foregroundStyle(Theme.muted) }
                if StaleWindowAnswer.applies(to: message) {
                    HStack {
                        Image(systemName: "arrow.clockwise"); Text(StaleWindowAnswer.notice)
                        if message.id == model.active?.messages.last?.id { Button("Refresh") { model.refreshAnswer() }.buttonStyle(ActionButton()).foregroundStyle(Theme.accent) }
                    }.font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                if message.role == "assistant" { ReplyTools(model: model, message: message) }
            }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
                .padding(message.role == "user" ? 12 : 0)
                .background(message.role == "user" ? Theme.fill : .clear)
                .clipExchange(ReplyControls.clips(message.role))
        }
    }
}

struct MessageHeading: View {
    let message: Message
    var body: some View {
        HStack(spacing: 6) {
            if ReplySpeaker.showsMark(for: message.role) { Image(systemName: "sparkle").font(.system(size: 8)).foregroundStyle(Theme.accent) }
            Text(message.role == "user" ? "You" : ReplySpeaker.name.localizedCapitalized).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
            if ReplyClock.shows(on: message.role) { Text(ReplyClock.label(for: message.date, now: Date())).font(.system(size: 12)).foregroundStyle(Theme.muted) }
        }
    }
}

struct MessageAttachments: View {
    @ObservedObject var model: AppModel
    let session: LearningSession
    let records: [AttachmentRecord]
    var body: some View {
        Group {
            if SentFiles.listedInFull || !FileScroll.usesScroll(fileCount: records.count) {
                VStack(alignment: .leading, spacing: 7) { ForEach(records) { record in attachment(record) } }
            } else {
                ScrollView(.horizontal) { HStack(spacing: 7) { ForEach(records) { record in attachment(record) } } }.scrollIndicators(.hidden)
            }
        }.stayInTheCoach()
    }
    @ViewBuilder private func attachment(_ record: AttachmentRecord) -> some View {
        if SentPicture.shows(record), let image = model.fileStore?.image(for: record) {
            Button { model.showFile?(record) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: SentPicture.maxHeight, alignment: .leading).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(FileName.shown(record.name)).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }.buttonStyle(ActionButton()).help("Preview \(record.name)").accessibilityLabel("Preview \(record.name)")
        } else {
            FileChip(record: record, among: records, model: model, removable: SentFile.canRemove(id: record.id, session: session))
        }
    }
}

private struct ReplyTools: View {
    @ObservedObject var model: AppModel
    let message: Message
    @State private var copied = false
    @State private var copyToken = UUID()
    private var reading: Bool { ReplyPlayback.reading(message: message.text, spoken: model.voice.spokenText, speaking: model.voice.speaking) }
    var body: some View {
        HStack(spacing: 16) {
            Button {
                if reading { model.voice.stopSpeaking() } else { model.voice.speak(SpokenReply.text(from: message.text)) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: ReplyPlayback.symbol(reading: reading)).symbolRenderingMode(.monochrome).foregroundStyle(reading ? Theme.accent : Theme.muted)
                    Text(ReplyPlayback.label(reading: reading))
                }
            }
                .buttonStyle(ActionButton()).font(.system(size: 12, weight: .medium)).foregroundStyle(reading ? Theme.accent : Theme.muted).help(reading ? "Stop reading" : "Read this reply").accessibilityLabel(reading ? "Stop reading" : "Read this reply")
            Button {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(ReplyCopy.text(from: message.text), forType: .string)
                let token = UUID(); copyToken = token; copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copyToken == token { copied = false } }
            } label: { Label(copied ? "Copied" : ReplyActions.copy, systemImage: copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(ActionButton()).font(.system(size: 12, weight: .medium)).foregroundStyle(copied ? Theme.accent : Theme.muted).help("Copy reply").accessibilityLabel(copied ? "Copied" : "Copy reply")
        }.padding(.top, 2)
    }
}

struct MessageText: View {
    let message: Message
    var body: some View {
        if message.showsMarkdown {
            let prepared = ReplyAddress.forDisplay(ReplyLines.forDisplay(message.text))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(ReplyCode.segments(prepared).enumerated()), id: \.offset) { _, segment in
                    if segment.code {
                        Text(ReadableLine.display(segment.text)).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if needsLiteral(segment.text) {
                        Text(ReadableLine.display(segment.text))
                    } else {
                        Text(.init(ReadableLine.display(segment.text)))
                    }
                }
            }
        } else {
            Text(QuestionLine.shown(HintRequest.shown(GuideTurn.shown(PointRequest.shown(message.text)))))
        }
    }
    private func needsLiteral(_ text: String) -> Bool {
        let rendered = (try? AttributedString(markdown: text)).map { String($0.characters) } ?? ""
        return AssistantReplyDisplay.needsLiteral(source: text, rendered: rendered)
    }
}

private extension View {
    @ViewBuilder func stayInTheCoach() -> some View {
        if FileRowWidth.staysWithinTheCoach { self.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading) }
        else { self }
    }
    @ViewBuilder func clipExchange(_ clips: Bool) -> some View {
        if clips { self.clipShape(RoundedRectangle(cornerRadius: 10)) } else { self }
    }
}

struct EmptyGreeting: View {
    @ObservedObject var model: AppModel
    let session: LearningSession
    var body: some View {
        Text(session.mode == .learn ? "What are we working through?" : "What would you like to work on?")
            .font(.system(size: 20, weight: .regular)).foregroundStyle(Theme.ink).padding(.bottom, 2)
    }
}
