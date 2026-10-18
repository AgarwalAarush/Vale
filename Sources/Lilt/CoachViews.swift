import SwiftUI
import LiltCore

struct CapsuleView: View {
    @ObservedObject var model: AppModel
    var openCoach: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            if CapsuleFace.nameLeads {
                Button(action: openCoach) {
                    HStack(spacing: 12) {
                        ForEach(CapsuleFace.order(hasTimer: (model.active?.duration ?? 0) > 0, hasWindow: model.context.hasSelection), id: \.self) { part in
                            capsulePart(part)
                        }
                    }
                }.buttonStyle(.plain).help(model.context.live ? "Live window context is on" : "Type a question").accessibilityLabel(model.context.live ? "Type a question. Live window context is on" : "Type a question")
            } else {
                Button(action: openCoach) {HStack(spacing:5){AudioMark(active: model.voice.listening || model.voice.speaking);if model.context.hasSelection{Image(systemName:model.context.live ? "record.circle.fill" : "macwindow").font(.system(size:10)).foregroundStyle(Theme.accent)}}}.buttonStyle(.plain).help(model.context.live ? "Live window context is on" : "Open assistant").accessibilityLabel(model.context.live ? "Open assistant. Live window context is on" : "Open assistant")
                Button(action: openCoach) {
                    HStack(spacing: 12) {
                        if let chat=model.active,chat.duration>0 { Text(chat.timerText).font(.system(size:13,weight:.semibold,design:.monospaced)).monospacedDigit() }
                        Text(model.active?.title == "New chat" ? "Vale" : model.active?.title ?? "Vale").font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: model.active?.duration == 0 ? (model.context.hasSelection ? 150 : 185) : 118, alignment: .leading)
                    }
                }.buttonStyle(.plain).help("Type a question")
            }
            Spacer(minLength: 0)
            if CapsuleMic.shows(coachOpen: model.coachOpen) {
                IconButton(symbol: model.voice.listening ? "mic.fill" : "mic", label: model.voice.listening ? "Finish speaking" : (model.voice.speaking || model.busy ? "Interrupt and talk" : "Talk"), tint: model.voice.listening ? Theme.accent : (CapsuleMic.idleIsQuiet(listening: model.voice.listening, speaking: model.voice.speaking, busy: model.busy) ? Theme.muted : Theme.ink)) { model.toggleVoice() }.disabled(model.paused || model.active == nil)
            }
            if !CapsulePause.inTheMenu {
                Button { model.togglePause() } label: { Label(CapsulePause.title(paused: model.paused), systemImage: model.paused ? "play.fill" : "pause.fill").font(.system(size: 12, weight: .medium)) }.buttonStyle(QuietButton(filled: true)).disabled(model.active == nil)
            }
            Menu {
                Button("Open coach", action: openCoach)
                Button("Chat history") { model.showLibrary?() }
                if CapsulePause.inTheMenu { Button(CapsulePause.title(paused: model.paused)) { model.togglePause() }.disabled(model.active == nil) }
                if model.active != nil { Button("Close chat") { model.complete() } }
                Divider()
                Button("Settings…") { model.showCoach?(); model.openSettingsInCoach() }
                Button("Quit Vale") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "ellipsis").font(.system(size: 15)).frame(width: 20, height: 28) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More options")
        }.padding(.horizontal, 20).frame(height: 62).modifier(GlassSurface(radius: 20))
    }

    private var faceTitle: String {
        if model.voice.speaking { return CapsuleSpeech.label(title: model.active?.title, busy: model.busy, speaking: true) }
        if model.busy { return CapsuleWait.label(title: model.active?.title, busy: true) }
        if let failure = CapsuleFailure.text(hasError: model.error != nil) { return failure }
        if CapsuleLabel.showsDraft(model.draft) { return CapsuleLabel.text(draft: model.draft, title: model.active?.title) }
        if CapsuleAnswer.title(coachOpen: model.coachOpen, chatTitle: model.active?.title, lastRole: model.active?.messages.last?.role) == CapsuleAnswer.ready { return CapsuleAnswer.ready }
        return CapsuleName.shown(title: model.active?.title ?? "New chat", hasMessages: model.active?.messages.isEmpty == false)
    }

    @ViewBuilder private func capsulePart(_ part: String) -> some View {
        switch part {
        case "name":
            ViewThatFits(in: .horizontal) {
                ForEach(Array(CapsuleTitle.candidates(faceTitle).enumerated()), id: \.offset) { _, name in
                    Text(name).lineLimit(1)
                }
            }
            .font(.system(size: CapsuleTitle.size, weight: CapsuleTitle.usesSemibold ? .semibold : .medium))
            .foregroundStyle(faceTitle == CapsuleAnswer.ready ? Theme.accent : (model.error != nil && !model.voice.speaking && !model.busy ? Color.orange : Theme.ink))
            .frame(maxWidth: model.active?.duration == 0 ? (model.context.hasSelection ? 150 : 185) : 118, alignment: .leading)
        case "timer":
            Text(model.active?.timerText ?? "").font(.system(size: 13, weight: .semibold, design: .monospaced)).monospacedDigit()
        case "bars":
            AudioMark(active: model.voice.listening || model.voice.speaking)
        default:
            Image(systemName: model.context.live ? "record.circle.fill" : "macwindow").font(.system(size: 10)).foregroundStyle(Theme.accent)
        }
    }
}

struct CoachView: View {
    @ObservedObject var model: AppModel
    var close: () -> Void
    @State private var walkthrough = false
    @State private var confirmGuide = false
    @State private var composerHeight: CGFloat = 61
    private var sendReady: Bool { model.hasInput && PausedTyping.allowsQuestion(paused: model.paused) && model.active != nil && !model.importing }
    private var sendControl: some View {
        Button {
            if model.busy { model.stopIfSeparate() }
            else { model.commitComposer?(); model.send() }
        } label: {
            Image(systemName: model.busy ? "stop.fill" : "arrow.up").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.busy || sendReady ? Color(red: 0.11, green: 0.14, blue: 0.22) : Theme.ink.opacity(0.45))
                .frame(width: 30, height: 30).background(model.busy || sendReady ? Theme.accent : Color.white.opacity(0.06)).clipShape(Circle())
        }.buttonStyle(.plain).disabled(!model.busy && !sendReady).help(model.busy ? "Stop response" : "Send message (Return)").accessibilityLabel(model.busy ? "Stop response" : "Send message")
    }
    private var voiceTools: some View {
        Group {
            if model.voice.speaking { IconButton(symbol: "stop.fill", label: "Stop playback", tint: Theme.accent) { model.stopResponse() } }
            IconButton(symbol: model.voice.listening ? "mic.fill" : "mic", label: model.voice.listening ? "Finish speaking" : (model.voice.speaking || model.busy ? "Interrupt and talk" : "Talk"), tint: model.voice.listening ? Theme.accent : Theme.muted) { model.toggleVoice() }.disabled(model.paused || model.active == nil)
        }
    }
    private var pendingFiles: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) { ForEach(model.pendingFiles) { record in FileChip(record: record, among: model.pendingFiles, model: model, removable: SentFile.canRemove(id: record.id, session: model.active)) } }
        }.scrollIndicators(.hidden).stayInTheCoach().fixedSize(horizontal: false, vertical: true)
    }
    var body: some View {
        let showSendHint = sendReady && !model.busy && !model.voice.listening && !model.voice.speaking && !model.voice.starting && !model.conversation
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                LogoMark(); Text(CoachHeading.title(for: model.active?.title)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer()
                if !ModePlace.inTheMenu {
                    Menu {
                        Button(ModePlace.assistantTitle) { model.setMode(.assistant) }
                        Button(ModePlace.learnTitle) { model.setMode(.learn) }
                    } label: { Text(model.active?.mode.label ?? ModePlace.assistantTitle).font(.system(size: 11)).foregroundStyle(Theme.muted) }.menuStyle(.borderlessButton).fixedSize().help("Choose Assistant or Learn with hints")
                }
                IconButton(symbol: HistoryMark.symbol, label: HistoryMark.label) { model.showHistory() }
                Menu {
                    if ModePlace.inTheMenu {
                        Button { model.setMode(.assistant) } label: { if (model.active?.mode ?? .assistant) == .assistant { Label(ModePlace.assistantTitle, systemImage: "checkmark") } else { Text(ModePlace.assistantTitle) } }
                        Button { model.setMode(.learn) } label: { if model.active?.mode == .learn { Label(ModePlace.learnTitle, systemImage: "checkmark") } else { Text(ModePlace.learnTitle) } }
                        Divider()
                    }
                    Toggle("Read typed replies aloud", isOn: $model.readAloud)
                    Button("New chat") {model.newSession()}
                    Button("Point it out") {model.pointItOut()}.disabled(!PointControl.enabled(waiting: model.busy))
                    if GuideControl.inTheMenu {
                        Button(GuideControl.title) {
                            if GuideStart.needsConfirmation(draft: model.draft, attachmentCount: model.pendingFiles.count) { confirmGuide = true } else { model.startGuide() }
                        }.disabled(model.busy || model.paused)
                    }
                    if model.active?.mode == .learn { Button("Show a full walkthrough…") { walkthrough = true }.disabled(model.active?.messages.isEmpty != false || model.busy) }
                    Menu("Focus timer") {Button("30 minutes"){model.setFocus(minutes:30)};Button("60 minutes"){model.setFocus(minutes:60)};Button("No timer"){model.setFocus(minutes:0)}}
                    Button("Close chat") { model.complete() }.disabled(model.active == nil)
                    Divider(); Button("Settings…") { model.openSettingsInCoach() }
                } label: { Image(systemName: "ellipsis").font(.system(size: 14)).frame(width: 24, height: 30) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                IconButton(symbol:model.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",label:model.expanded ? "Compact assistant" : "Expand assistant"){model.expandCoach?()}
                IconButton(symbol: CoachDismiss.symbol, label: CoachDismiss.label, action: close)
            }.padding(.horizontal, 18).padding(.top, 15).padding(.bottom, 11)
            if !ShareRow.afterTheComposer { ContextStrip(model:model) }
            if let warning = ShortcutNotice.text(model.shortcutWarning) {
                Text(warning).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).padding(11).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 18).padding(.top, 8)
            }
            if model.active?.showsEarlierContextNotice == true {
                HStack(alignment:.top,spacing:7){Image(systemName:"clock.arrow.circlepath");Text("Using recent messages only. Earlier context stays in History.");Spacer(minLength:0);Button("History"){model.showLibrary?()}.buttonStyle(.plain).foregroundStyle(Theme.accent)}.font(.system(size:10)).foregroundStyle(Theme.muted).padding(.horizontal,20).padding(.top,10)
            }
            if let guide=model.active?.guide, !model.settingsInCoach {GuideCard(model:model,guide:guide)}
            if model.settingsInCoach {
                HStack {
                    Button("Back to chat") { model.settingsInCoach = false }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent).accessibilityLabel("Back to chat")
                    Spacer()
                }.padding(.horizontal, 18).padding(.bottom, 4)
                SettingsView(model: model, embeddedInCoach: true).frame(maxHeight: .infinity)
            } else {
            GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let session = model.active {
                            if session.messages.isEmpty, !EmptyCoach.sitsWithComposer(messageCount: session.messages.count) { EmptyGreeting(model: model, session: session) }
                            ForEach(session.messages) { message in CoachMessage(model: model, session: session, message: message).id(message.id) }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Ready when you are.").font(.system(size: 23, weight: .medium)).tracking(-0.5)
                                Button("New chat") { model.prepareChat() }.buttonStyle(QuietButton(filled: true))
                            }.padding(.top, 24)
                        }
                        if model.busy, ReplyWait.inTheThread { HStack(spacing: 8) { Text(ReplyWait.speaker).font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Theme.muted); ProgressView().controlSize(.mini); Text("Thinking…").font(.system(size: 12)).foregroundStyle(Theme.muted) }.padding(.vertical, 5).id("thinking") }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 18).padding(.bottom, 12).frame(maxWidth: .infinity, minHeight: ThreadSeat.pins(model.active?.messages.count ?? 0) ? geometry.size.height : nil, alignment: ThreadSeat.pins(model.active?.messages.count ?? 0) ? .bottomLeading : .topLeading)
                }.scrollIndicators(.automatic)
                .onChange(of: model.active?.messages.count) { revealLatest(proxy) }
                .onChange(of: model.busy) { revealLatest(proxy) }
                .onChange(of: model.activeID) { revealLatest(proxy) }
            }
            }.frame(minHeight: ComposerSeat.staysOnScreen ? 0 : nil, maxHeight: .infinity)
            if let session = model.active, EmptyCoach.sitsWithComposer(messageCount: session.messages.count) { EmptyGreeting(model: model, session: session) }
            }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) { Text(error).font(.system(size: 11)).foregroundStyle(Color(red: 0.96, green: 0.77, blue: 0.49)); Spacer(minLength: 0); Button { model.error = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).accessibilityLabel("Dismiss message") }
                    HStack(spacing: 14) {
                        if model.errorOffersSettings { Button("Open Settings") { model.openSettingsInCoach() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent) }
                        if model.context.hasSelection { Button("Change window") { model.context.choose() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent) }
                    }
                }.padding(11).background(Color.orange.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 18).padding(.bottom, 10)
            }
            if model.canRetry, RetryOffer.shows(waiting: model.busy, lastRoleIsUser: model.active?.messages.last?.role == "user") {
                HStack { Button("Retry message") { model.retry() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent); Spacer() }.padding(.horizontal, 20).padding(.bottom, 8)
            }
            if model.paused, model.active != nil {
                HStack { Text("Paused · mic and sharing off").font(.system(size: 11)).foregroundStyle(Theme.muted); Spacer(); Button("Resume") { model.togglePause() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.accent) }.padding(.horizontal, 20).padding(.bottom, 10)
            }
            if model.active?.mode == .learn, !model.settingsInCoach { HStack(spacing: 9) {
                Button { model.nextHint() } label: { Label("Hint", systemImage: "lightbulb").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
                Button { model.pointItOut() } label: { Label("Point it out", systemImage: "cursorarrow.rays").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
            }.disabled(model.busy || model.paused || model.active == nil).padding(.horizontal, 18).padding(.bottom, 10) }
            if !UnsentFilePlace.withTheDraft, !model.pendingFiles.isEmpty { pendingFiles.padding(.horizontal, 18).padding(.bottom, 10) }
            VStack(spacing: 3) {
                if UnsentFilePlace.withTheDraft, !model.pendingFiles.isEmpty { pendingFiles }
                HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if FieldPrompt.showsIdle(model.draft) { Text(WaitingField.shown(waiting: model.busy)).font(.system(size: 15, weight: ComposerPrompt.usesMediumWeight ? .medium : .regular)).foregroundStyle(Theme.muted.opacity(ComposerPrompt.opacity)).padding(.top, ComposerPrompt.topInset).padding(.leading, ComposerPrompt.leadingInset).allowsHitTesting(false) }
                    DraftEditor(text: Binding(get:{model.draft},set:{model.editDraft($0)}), focusToken: model.composerFocus, submit: { if ComposerReturn.sends(whileWaiting: model.busy) { model.send() } }, cancel: { model.stopInteraction() }, pasteFiles: { model.importDroppedFiles($0) }, pasteImage: { model.pasteImage($0) }, pastePDF: { model.pastePDF($0) }, installCommit: { model.commitComposer = $0 }, onMeasuredHeight: { measured in
                        let next = CGFloat(ComposerHeight.clamped(Double(measured)))
                        if abs(composerHeight - next) > 0.5 { composerHeight = next }
                    }).frame(height: composerHeight)
                }.help("Return sends. Shift–Return or Option–Return adds a line.")
                if SendPlacement.onTheTypedLine { sendControl }
                }
                HStack(spacing: ComposerRows.spacing) {
                    Button { model.attachFiles() } label: { Label(AttachControl.title, systemImage: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 8).padding(.vertical, 6) }.buttonStyle(.plain).disabled(model.importing).help("Attach files").accessibilityLabel("Attach files")
                    IconButton(symbol:"globe",label:WebSearchLabel.title(enabled: model.active?.webEnabled == true),tint:model.active?.webEnabled == true ? Theme.accent : Theme.muted){model.setWeb(!(model.active?.webEnabled ?? false))}.disabled(!WebToggle.changes(waiting: model.busy))
                    if !GuideControl.inTheMenu {
                    IconButton(symbol:"list.number",label:GuideControl.title){
                        if GuideStart.needsConfirmation(draft: model.draft, attachmentCount: model.pendingFiles.count) { confirmGuide = true } else { model.startGuide() }
                    }.disabled(model.busy || model.paused)
                    }
                    if MicPlacement.withTheTools { voiceTools }
                    Spacer()
                    if !MicPlacement.withTheTools { voiceTools }
                    if !SendPlacement.onTheTypedLine { sendControl }
                }
            }.padding(9).background(.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.8)).padding(.horizontal, 18)
            HStack {
                Text(model.status).font(.system(size: 11, weight: .medium)).foregroundStyle(model.voice.listening || showSendHint ? Theme.accent : Theme.muted)
                Spacer()
                Button { model.setConversation(!model.conversation) } label: { Label(ConversationControl.title(on: model.conversation), systemImage: model.conversation ? "waveform.circle.fill" : "waveform.circle") }.buttonStyle(QuietButton(filled: model.conversation)).foregroundStyle(model.conversation ? Theme.accent : Theme.muted).disabled(model.paused).help("Opt in to hands-free turn-taking; tap mic or press Escape to interrupt")
            }.padding(.horizontal, 21).padding(.top, 7).padding(.bottom, 8)
            if ShareRow.afterTheComposer, !model.settingsInCoach { ContextStrip(model: model).padding(.bottom, 12) }
        }.modifier(GlassSurface(radius: 20))
            .dropDestination(for: URL.self) { urls, _ in
                if let links = DroppedLink.text(from: urls) {
                    if model.active == nil { model.prepareChat() }
                    model.editDraft(model.draft.isEmpty ? links : model.draft + "\n" + links)
                }
                let files = FieldDrop.attaches(urls)
                if !files.isEmpty { model.importDroppedFiles(files) }
                return !files.isEmpty || DroppedLink.text(from: urls) != nil
            }
            .environment(\.openURL, OpenURLAction { url in AnswerLink.canOpen(url) ? .systemAction : .discarded })
            .alert("Show the walkthrough?", isPresented: $walkthrough) {
                Button("Keep thinking", role: .cancel) {}
                Button("Show walkthrough") { model.send("Please give me the full walkthrough now, explaining why each step works.", reveal: true) }
            } message: { Text("This will reveal the method. Your current hints stay in the conversation.") }
            .alert("Start a step-by-step guide?", isPresented: $confirmGuide) {
                Button("Keep writing", role: .cancel) {}
                Button("Start guide") { model.startGuide() }
            } message: { Text("This sends what you have typed and clears the composer.") }
    }

    private func revealLatest(_ proxy: ScrollViewProxy) {
        if model.busy, !QuestionScroll.opensAtTheStart(role: model.active?.messages.last?.role) { proxy.scrollTo("thinking", anchor: .bottom) }
        else if QuestionScroll.opensAtTheStart(role: model.active?.messages.last?.role) || TranscriptReveal.showsStartOfNewestMessage, let id = model.active?.messages.last?.id { proxy.scrollTo(id, anchor: .top) }
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
            Text(message.role == "user" ? "YOU" : ReplySpeaker.name).font(.system(size: 11, weight: .medium)).tracking(0.4).foregroundStyle(Theme.muted)
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
        VStack(alignment: .leading, spacing: EmptyCoach.blockSpacing) {
            Text(session.mode == .learn ? "ONE HINT AT A TIME" : "HERE WHEN YOU NEED A HAND").font(.system(size: EmptyCoach.kickerSize, weight: .medium)).tracking(0.4).foregroundStyle(Theme.muted)
            Text(session.mode == .learn ? "What are we\nworking through?" : "How can I help?").font(.system(size: 24, weight: .medium)).tracking(-0.55).lineSpacing(1)
            Text(session.mode == .learn ? "Think it through with a little guidance." : OpeningLine.assistant).font(.system(size: EmptyCoach.bodySize)).foregroundStyle(Theme.muted).lineSpacing(3)
            if EmptyThread.showsPlace { Text(EmptyThread.line).font(.system(size: 12)).foregroundStyle(Theme.muted) }
            if CodexNotice.shows(executableKnown: model.provider.executable != nil, lookupFinished: model.provider.lookupFinished) { CodexSignInCard(model: model) }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CodexSignInCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let notice = CodexSignInNotice.beforeFirstSend(executableFound: model.provider.executable != nil)
        VStack(alignment: .leading, spacing: 8) {
            Text(notice.title).font(.system(size: 13, weight: .semibold))
            Text(notice.detail).font(.system(size: 12)).foregroundStyle(Theme.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Button("Settings") { model.openSettingsInCoach() }.buttonStyle(QuietButton())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 0.8))
        .accessibilityElement(children: .contain)
    }
}
