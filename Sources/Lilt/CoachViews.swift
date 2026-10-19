import SwiftUI
import LiltCore

struct CoachView: View {
    @ObservedObject var model: AppModel
    @State private var composerHeight: CGFloat = 61
    private var sendReady: Bool { model.hasInput && PausedTyping.allowsQuestion(paused: model.paused) && model.active != nil && !model.importing }
    var body: some View {
        VStack(spacing: 0) {
            if let warning = ShortcutNotice.text(model.shortcutWarning) { notice(warning) }
            if model.active?.showsEarlierContextNotice == true {
                Text("Using recent messages. Full history stays saved here.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 12)
            }
            if let guide = model.active?.guide { GuideCard(model: model, guide: guide).frame(maxWidth: 740) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if let session = model.active {
                            if session.messages.isEmpty { EmptyGreeting(model: model, session: session) }
                            ForEach(session.messages) { message in CoachMessage(model: model, session: session, message: message).id(message.id) }
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("A place to pick up the thread.").font(.system(size: 28))
                                Text("Choose a chat from history, or start something new.").font(.system(size: 15)).foregroundStyle(Theme.muted)
                                Button("New chat") { model.prepareChat() }.buttonStyle(QuietButton(filled: true))
                            }.padding(.vertical, 32)
                        }
                        if model.busy { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").font(.system(size: 13)).foregroundStyle(Theme.muted) }.id("thinking") }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 24).frame(maxWidth: 740, alignment: .leading).frame(maxWidth: .infinity)
                }
                .clipped()
                .onChange(of: model.active?.messages.count) { revealLatest(proxy) }
                .onChange(of: model.busy) { revealLatest(proxy) }
                .onChange(of: model.activeID) { revealLatest(proxy) }
            }.frame(minHeight: 0, maxHeight: .infinity)
            VStack(spacing: 12) {
                if let error = model.error {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) { Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 4); IconButton(symbol: "xmark", label: "Dismiss message") { model.error = nil } }
                        HStack(spacing: 16) {
                            if model.errorOffersSettings { Button("Open Settings") { model.openSettings() } }
                            if model.context.hasSelection { Button("Change window") { model.context.choose() } }
                            if let id = model.deletionToRetry { Button("Retry Forget") { model.delete(id) } }
                        }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(Theme.accent)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.warning.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if model.canRetry { HStack { Button("Retry message") { model.retry() }.buttonStyle(.plain).foregroundStyle(Theme.accent); Spacer() }.font(.system(size: 13)) }
                if model.active != nil {
                    if model.context.hasSelection { ContextStrip(model: model).fixedSize(horizontal: false, vertical: true) }
                    if model.paused { HStack { Text("Paused · mic and sharing off").foregroundStyle(Theme.muted); Spacer(); Button("Resume") { model.togglePause() }.buttonStyle(.plain).foregroundStyle(Theme.accent) }.font(.system(size: 12)) }
                    if model.active?.mode == .learn {
                        HStack(spacing: 16) {
                            Button { model.nextHint() } label: { Label("Hint", systemImage: "lightbulb") }
                            Button { model.pointItOut() } label: { Label("Point it out", systemImage: "cursorarrow.rays") }
                            Spacer()
                        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.muted).disabled(model.busy || model.paused)
                    }
                    composer
                    HStack {
                        Text(model.status).font(.system(size: 12)).foregroundStyle(model.voice.listening ? Theme.accent : Theme.muted)
                        Spacer()
                        Button { model.setConversation(!model.conversation) } label: { Label(model.conversation ? "Conversation on" : "Conversation", systemImage: model.conversation ? "waveform.circle.fill" : "waveform.circle") }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(model.conversation ? Theme.accent : Theme.muted).disabled(model.paused).help("Opt in to spoken turn-taking. Escape stops voice and sharing.")
                    }.padding(.horizontal, 2)
                }
            }.fixedSize(horizontal: false, vertical: true).layoutPriority(1).padding(.horizontal, 32).padding(.bottom, 22).frame(maxWidth: 740).frame(maxWidth: .infinity)
        }.background(Theme.background)
        .dropDestination(for: URL.self) { urls, _ in
            if let links = DroppedLink.text(from: urls) { if model.active == nil { model.prepareChat() }; model.editDraft(model.draft.isEmpty ? links : model.draft + "\n" + links) }
            let files = FieldDrop.attaches(urls); if !files.isEmpty { model.importDroppedFiles(files) }
            return !files.isEmpty || DroppedLink.text(from: urls) != nil
        }
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if !model.pendingFiles.isEmpty { ScrollView(.horizontal) { HStack(spacing: 8) { ForEach(model.pendingFiles) { FileChip(record: $0, among: model.pendingFiles, model: model, removable: true) } } }.scrollIndicators(.hidden).fixedSize(horizontal: false, vertical: true) }
            ZStack(alignment: .topLeading) {
                if FieldPrompt.showsIdle(model.draft) { Text(model.busy ? "Add a thought for your next message…" : "Message Vale…").font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.top, 5).padding(.leading, 2).allowsHitTesting(false) }
                DraftEditor(text: Binding(get: { model.draft }, set: { model.editDraft($0) }), focusToken: model.composerFocus, submit: { if ComposerReturn.sends(whileWaiting: model.busy) { model.send() } }, cancel: { model.stopInteraction() }, pasteFiles: { model.importDroppedFiles($0) }, pasteImage: { model.pasteImage($0) }, pastePDF: { model.pastePDF($0) }, installCommit: { model.commitComposer = $0 }, onMeasuredHeight: { measured in
                    let height = CGFloat(ComposerHeight.clamped(Double(measured))); if abs(composerHeight - height) > 0.5 { composerHeight = height }
                }).frame(height: composerHeight)
            }.help("Return sends. Shift–Return adds a line.")
            HStack(spacing: 10) {
                Button { model.attachFiles() } label: { Label("Attach", systemImage: "plus") }.disabled(model.importing)
                if !model.context.hasSelection { Button { model.context.choose() } label: { Label("Share window", systemImage: "macwindow") }.disabled(model.paused) }
                Menu {
                    Toggle("Web search", isOn: Binding(get: { model.active?.webEnabled == true }, set: { model.setWeb($0) })).disabled(!WebToggle.changes(waiting: model.busy))
                    Text("Web search is unavailable with the current Codex runtime.")
                } label: { Image(systemName: "globe").frame(width: 24, height: 24) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Web search availability").accessibilityLabel("Web search options")
                Spacer(minLength: 8)
                if model.voice.speaking { IconButton(symbol: "stop.fill", label: "Stop playback", tint: Theme.accent) { model.stopResponse() } }
                IconButton(symbol: model.voice.listening ? "mic.fill" : "mic", label: model.voice.listening ? "Finish speaking" : "Talk", tint: model.voice.listening ? Theme.accent : Theme.muted) { model.toggleVoice() }.disabled(model.paused)
                Button { if model.busy { model.stopIfSeparate() } else { model.send() } } label: {
                    Image(systemName: model.busy ? "stop.fill" : "arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.onAction).frame(width: 30, height: 30).background(sendReady || model.busy ? Theme.action : Theme.muted).clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(!model.busy && !sendReady).help(model.busy ? "Stop response" : "Send message (Return)").accessibilityLabel(model.busy ? "Stop response" : "Send message")
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }.padding(12).background(Theme.fillRaised).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 1))
    }
    private func notice(_ text: String) -> some View { Text(text).font(.system(size: 12)).foregroundStyle(Theme.warning).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
    private func revealLatest(_ proxy: ScrollViewProxy) {
        if model.busy, !QuestionScroll.opensAtTheStart(role: model.active?.messages.last?.role) { proxy.scrollTo("thinking", anchor: .bottom) }
        else if let id = model.active?.messages.last?.id { proxy.scrollTo(id, anchor: .top) }
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
                if StoppedReply.shows(role: message.role, stopped: message.replyStopped) { Text(StoppedReply.label).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                if FailedAnswer.shows(failed: message.answerFailed, waiting: model.busy && message.id == session.messages.last?.id) { Text(FailedAnswer.label).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                if !message.attachments.isEmpty { MessageAttachments(model: model, session: session, records: message.attachments) }
                if message.highlightUnavailable { Label("Highlight unavailable · check your selected window", systemImage: "eye.slash").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                if StaleWindowAnswer.applies(to: message) {
                    HStack {
                        Image(systemName: "arrow.clockwise"); Text(StaleWindowAnswer.notice)
                        if message.id == model.active?.messages.last?.id { Button("Refresh") { model.refreshAnswer() }.buttonStyle(.plain).foregroundStyle(Theme.accent) }
                    }.font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                if message.role == "assistant" { ReplyTools(model: model, message: message) }
            }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
                .padding(message.role == "user" ? 12 : 0)
                .padding(.leading, ReplyTurn.ruled(message.role) ? ReplyTurn.inset : 0)
                .background(message.role == "user" ? Theme.fill : .clear)
                .overlay(alignment: .leading) { if ReplyTurn.ruled(message.role) { RoundedRectangle(cornerRadius: 1.5).fill(Theme.accent.opacity(0.8)).frame(width: ReplyTurn.ruleWidth) } }
                .clipExchange(ReplyControls.clips(message.role))
        }
    }
}

struct MessageHeading: View {
    let message: Message
    var body: some View {
        HStack(spacing: 6) {
            if ReplySpeaker.showsMark(for: message.role) { Image(systemName: "sparkle").font(.system(size: 8)).foregroundStyle(Theme.accent) }
            Text(message.role == "user" ? "You" : ReplySpeaker.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted)
            if ReplyClock.shows(on: message.role) { Text(ReplyClock.label(for: message.date, now: Date())).font(.system(size: 9)).foregroundStyle(Theme.muted) }
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
                    Text(FileName.shown(record.name)).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }.buttonStyle(.plain).help("Preview \(record.name)").accessibilityLabel("Preview \(record.name)")
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
                if reading { model.voice.stopSpeaking() } else { model.voice.speak(message.text) }
            } label: { Label(reading ? "Stop playback" : ReplyActions.read, systemImage: reading ? "stop.fill" : "speaker.wave.2") }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(reading ? Theme.accent : Theme.muted).help(reading ? "Stop playback" : "Read this reply").accessibilityLabel(reading ? "Stop playback" : "Read this reply")
            Button {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string)
                let token = UUID(); copyToken = token; copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copyToken == token { copied = false } }
            } label: { Label(copied ? "Copied" : ReplyActions.copy, systemImage: copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(copied ? Theme.accent : Theme.muted).help("Copy reply").accessibilityLabel(copied ? "Copied" : "Copy reply")
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
            Text(QuestionLine.shown(message.text))
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
        VStack(alignment: .leading, spacing: 12) {
            Text(session.mode == .learn ? "What are we working through?" : "How can I help?").font(.system(size: 30, weight: .regular)).tracking(-0.6)
            Text(session.mode == .learn ? "Take it one step at a time, with a little guidance." : "Think something through, make sense of a file, or start with a question.").font(.system(size: 15)).foregroundStyle(Theme.muted).lineSpacing(4)
            if CodexNotice.shows(executableKnown: model.provider.executable != nil, lookupFinished: model.provider.lookupFinished) { CodexSignInCard(model: model).padding(.top, 8) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 32)
    }
}

struct CodexSignInCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let notice = CodexSignInNotice.beforeFirstSend(executableFound: model.provider.executable != nil)
        VStack(alignment: .leading, spacing: 8) {
            Text(notice.title).font(.system(size: 13, weight: .semibold))
            Text(notice.detail).font(.system(size: 12)).foregroundStyle(Theme.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Button("Settings") { model.openSettings() }.buttonStyle(QuietButton())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 0.8))
        .accessibilityElement(children: .contain)
    }
}
