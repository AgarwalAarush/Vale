import SwiftUI
import LiltCore

struct CapsuleView: View {
    @ObservedObject var model: AppModel
    var openCoach: () -> Void
    var close: () -> Void = {}
    var chromeless = false
    @State private var walkthrough = false
    @State private var confirmGuide = false
    var body: some View {
        HStack(spacing: 12) {
            if CapsuleFace.nameLeads {
                Button(action: openCoach) {
                    HStack(spacing: 12) {
                        ForEach(barParts, id: \.self) { part in
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
            if CapsuleMic.shows(coachOpen: model.companionExpanded) {
                IconButton(symbol: model.voice.listening ? "mic.fill" : "mic", label: model.voice.listening ? "Finish speaking" : (model.voice.speaking || model.busy ? "Interrupt and talk" : "Talk"), tint: model.voice.listening ? Theme.accent : (CapsuleMic.idleIsQuiet(listening: model.voice.listening, speaking: model.voice.speaking, busy: model.busy) ? Theme.muted : Theme.ink)) { model.toggleVoice() }.disabled(model.paused || model.active == nil)
            }
            if !CapsulePause.inTheMenu {
                Button { model.togglePause() } label: { Label(CapsulePause.title(paused: model.paused), systemImage: model.paused ? "play.fill" : "pause.fill").font(.system(size: 12, weight: .medium)) }.buttonStyle(QuietButton(filled: true)).disabled(model.active == nil)
            }
            Menu {
                if model.companionExpanded {
                    Button(model.expanded ? "Compact size" : "Larger size") { model.expandCoach?() }
                    Button("Hide") { close() }
                } else {
                    Button("Open", action: openCoach)
                }
                if ModePlace.inTheMenu {
                    Button(ModePlace.assistantTitle) { model.setMode(.assistant) }
                    Button(ModePlace.learnTitle) { model.setMode(.learn) }
                    Divider()
                }
                Toggle("Read typed replies aloud", isOn: $model.readAloud)
                Button("New chat") { model.newSession() }
                Button("Point it out") { model.pointItOut() }.disabled(!PointControl.enabled(waiting: model.busy))
                if GuideControl.inTheMenu {
                    Button(GuideControl.title) {
                        if GuideStart.needsConfirmation(draft: model.draft, attachmentCount: model.pendingFiles.count) { confirmGuide = true } else { model.startGuide() }
                    }.disabled(model.busy || model.paused)
                }
                if model.active?.mode == .learn { Button("Show a full walkthrough…") { walkthrough = true }.disabled(model.active?.messages.isEmpty != false || model.busy) }
                if FocusTimer.shows(mode: model.active?.mode ?? .assistant, running: (model.active?.duration ?? 0) > 0) {
                    Menu("Focus timer") { Button("30 minutes") { model.setFocus(minutes: 30) }; Button("60 minutes") { model.setFocus(minutes: 60) }; Button("No timer") { model.setFocus(minutes: 0) } }
                }
                Button("Chat history") { model.showLibrary?() }
                if CapsulePause.inTheMenu { Button(CapsulePause.title(paused: model.paused)) { model.togglePause() }.disabled(model.active == nil) }
                if model.active != nil { Button("Close chat") { model.complete() } }
                Divider()
                Button("Settings…") { model.showCoach?(); model.openSettingsInCoach() }
                Button("Quit Vale") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Theme.muted).frame(width: 20, height: 28) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More options")
        }.padding(.horizontal, 20).frame(height: 62).modifier(CapsuleChrome(enabled: !chromeless))
            .alert("Show the walkthrough?", isPresented: $walkthrough) {
                Button("Keep thinking", role: .cancel) {}
                Button("Show walkthrough") { model.send("Please give me the full walkthrough now, explaining why each step works.", reveal: true) }
            } message: { Text("This will reveal the method. Your current hints stay in the conversation.") }
            .alert("Start a step-by-step guide?", isPresented: $confirmGuide) {
                Button("Keep writing", role: .cancel) {}
                Button("Start guide") { model.startGuide() }
            } message: { Text("This sends what you have typed and clears the composer.") }
    }

    /// Idle bars stay on the compact bar. Once the thread is open they appear only while voice is in use.
    private var barParts: [String] {
        let parts = CapsuleFace.order(hasTimer: (model.active?.duration ?? 0) > 0, hasWindow: model.context.hasSelection)
        let voiceOn = model.voice.listening || model.voice.speaking
        guard model.companionExpanded, !voiceOn else { return parts }
        return parts.filter { $0 != "bars" }
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
            Image(systemName: model.context.live ? "record.circle.fill" : "macwindow").font(.system(size: 10)).foregroundStyle(model.context.live ? Theme.accent : Theme.muted)
        }
    }
}

private struct CapsuleChrome: ViewModifier {
    var enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.modifier(GlassSurface(radius: 20)) } else { content }
    }
}

struct CompanionView: View {
    @ObservedObject var model: AppModel
    var close: () -> Void
    var relayout: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            CapsuleView(model: model, openCoach: { model.coachOpen = true; relayout() }, close: close, chromeless: true)
            if model.companionExpanded {
                CoachView(model: model, close: close, hidesHeader: true)
            }
        }
        .modifier(GlassSurface(radius: model.companionExpanded ? 22 : 20))
        .dropDestination(for:URL.self){urls,_ in
            model.keepDroppedLinks(urls)
            let files=urls.filter(\.isFileURL)
            if !files.isEmpty { Task{await model.importFiles(files)} }
            return DroppedLink.text(from:urls) != nil || !files.isEmpty
        }
        .onChange(of: model.companionExpanded) { _ in relayout() }
        .onChange(of: model.expanded) { _ in relayout() }
        .onChange(of: model.pendingFiles.count) { _ in relayout() }
        .onChange(of: model.active?.messages.count) { _ in relayout() }
    }
}

struct CoachView: View {
    @ObservedObject var model: AppModel
    var close: () -> Void
    var hidesHeader = false
    @State private var walkthrough = false
    @State private var confirmGuide = false
    @State private var copiedReply: UUID?
    @State private var composerHeight: CGFloat = CGFloat(ComposerHeight.minimum)
    var body: some View {
        let sendReady = model.hasInput && !model.paused && model.active != nil && !model.importing
        let showSendHint = sendReady && !model.busy && !model.voice.listening && !model.voice.speaking && !model.voice.starting && !model.conversation
        VStack(spacing: 0) {
            if !hidesHeader { HStack(spacing: 10) {
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
                    if FocusTimer.shows(mode: model.active?.mode ?? .assistant, running: (model.active?.duration ?? 0) > 0) { Menu("Focus timer") {Button("30 minutes"){model.setFocus(minutes:30)};Button("60 minutes"){model.setFocus(minutes:60)};Button("No timer"){model.setFocus(minutes:0)}} }
                    Button("Close chat") { model.complete() }.disabled(model.active == nil)
                    Divider(); Button("Settings…") { model.openSettingsInCoach() }
                } label: { Image(systemName: "ellipsis").font(.system(size: 14)).frame(width: 24, height: 30) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                IconButton(symbol:model.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",label:model.expanded ? "Compact assistant" : "Expand assistant"){model.expandCoach?()}
                IconButton(symbol: CoachDismiss.symbol, label: CoachDismiss.label, action: close)
            }.padding(.horizontal, 18).padding(.top, 15).padding(.bottom, 11) }
            if !ShareRow.afterTheComposer { ContextStrip(model:model) }
            if let warning=model.shortcutWarning{Text(warning).font(.system(size:11)).foregroundStyle(Theme.muted).padding(.horizontal,18).padding(.top,8)}
            if model.active?.showsEarlierContextNotice == true {
                HStack(alignment:.firstTextBaseline,spacing:8){Text("Using recent messages only. Earlier context stays in History.");Spacer(minLength:0);Button("History"){model.showLibrary?()}.buttonStyle(.plain)}.font(.system(size:11)).foregroundStyle(Theme.muted).padding(.horizontal,18).padding(.top,8)
            }
            if let guide=model.active?.guide, !model.settingsInCoach {GuideCard(model:model,guide:guide)}
            if model.settingsInCoach {
                HStack {
                    Button("Back to chat") { model.settingsInCoach = false }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent).accessibilityLabel("Back to chat")
                    Spacer()
                }.padding(.horizontal, 18).padding(.bottom, 4)
                SettingsView(model: model, embeddedInCoach: true).frame(maxHeight: .infinity)
            } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let session = model.active {
                            if session.messages.isEmpty, !EmptyCoach.sitsWithComposer(messageCount: session.messages.count) { EmptyGreeting(model: model, session: session) }
                            ForEach(session.messages) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        if ReplySpeaker.showsMark(for: message.role) { Image(systemName: "sparkle").font(.system(size: 7)).foregroundStyle(Theme.muted.opacity(0.55)) }
                                        Text(message.role == "user" ? "YOU" : ReplySpeaker.name).font(.system(size: 10)).foregroundStyle(Theme.muted)
                                        if ReplyClock.shows(on: message.role) { Text(ReplyClock.label(for: message.date, now: Date())).font(.system(size: 10)).foregroundStyle(Theme.muted) }
                                    }
                                    if !message.text.isEmpty { MessageText(message: message).font(.system(size: 15)).lineSpacing(2).tint(Theme.accent).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                                    ForEach(message.attachments.filter(SentPicture.shows)) { record in
                                        if let image = model.fileStore?.image(for: record) {
                                            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: SentPicture.maxHeight, alignment: .leading)
                                        }
                                    }
                                    if StoppedReply.shows(role: message.role, stopped: message.replyStopped) { Text(StoppedReply.label).font(.system(size: 10)).foregroundStyle(Theme.muted) }
                                    if FailedAnswer.shows(failed: message.answerFailed, waiting: model.busy && message.id == session.messages.last?.id) { Text(FailedAnswer.label).font(.system(size: 10)).foregroundStyle(Theme.muted) }
                                    if !message.attachments.isEmpty {
                                        let row = HStack(spacing:7){ForEach(message.attachments){record in FileChip(record:record,among:message.attachments,model:model,removable:SentFile.canRemove(id:record.id,session:model.active))}}
                                        if FileScroll.usesScroll(fileCount: message.attachments.count) { ScrollView(.horizontal) { row }.scrollIndicators(.hidden) } else { row }
                                    }
                                    if message.highlightUnavailable{Text("Highlight unavailable · check your selected window").font(.system(size:10)).foregroundStyle(Theme.muted)}
                                    if message.screenChanged{
                                        HStack(spacing: 8){Text("Window changed during this answer");if message.id==model.active?.messages.last?.id{Button("Refresh"){model.refreshAnswer()}.buttonStyle(.plain)}}.font(.system(size:11)).foregroundStyle(Theme.muted)
                                    }
                                    if message.role == "assistant" {
                                        let reading = ReplyPlayback.reading(message: message.text, spoken: model.voice.spokenText, speaking: model.voice.speaking)
                                        HStack(spacing: 10) {
                                            Button(ReplyPlayback.label(reading: reading)) {
                                                if reading { model.voice.stopSpeaking() } else { model.voice.speak(SpokenReply.text(from: message.text)) }
                                            }.buttonStyle(.plain).foregroundStyle(reading ? Theme.accent : Theme.muted)
                                            Button(copiedReply == message.id ? "Copied" : ReplyActions.copy) {
                                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(ReplyCopy.text(from: message.text), forType: .string)
                                                let id = message.id; copiedReply = id
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copiedReply == id { copiedReply = nil } }
                                            }.buttonStyle(.plain).foregroundStyle(copiedReply == message.id ? Theme.accent : Theme.muted)
                                        }.font(.system(size: 11))
                                    }
                                }.frame(maxWidth: .infinity, alignment: SpeakerTurn.trails(message.role) ? .trailing : .leading)
                                    .padding(.leading, SpeakerTurn.trails(message.role) ? SpeakerTurn.leadingClearance : (ReplyTurn.ruled(message.role) ? ReplyTurn.inset : 0))
                                    .background(.clear)
                                    .overlay(alignment: .leading) { if ReplyTurn.ruled(message.role) { RoundedRectangle(cornerRadius: 1.5).fill(Theme.line).frame(width: ReplyTurn.ruleWidth) } }
                                    .replyClip(message.role)
                                    .id(message.id)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Ready when you are.").font(.system(size: EmptyCoach.bodySize)).foregroundStyle(Theme.muted)
                                Button("New chat") { model.prepareChat() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
                            }.padding(.top, 8)
                        }
                        if model.busy, ReplyWait.inTheThread { HStack(spacing: 8) { Text(ReplyWait.speaker).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted); ProgressView().controlSize(.mini); Text("Thinking…").font(.system(size: 11)).foregroundStyle(Theme.muted) }.padding(.vertical, 2).id("thinking") }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 18).padding(.bottom, 6).frame(maxWidth: .infinity, alignment: .leading)
                }.scrollIndicators(.hidden)
                .onChange(of: model.active?.messages.count) { scrollThread(proxy) }
                .onChange(of: model.busy) { scrollThread(proxy) }
            }.frame(maxHeight: .infinity)
            if let session = model.active, EmptyCoach.sitsWithComposer(messageCount: session.messages.count) { EmptyGreeting(model: model, session: session) }
            }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) { Text(error).font(.system(size: 12)).foregroundStyle(Theme.ink); Spacer(minLength: 0); Button { model.error = nil } label: { Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(Theme.muted) }.buttonStyle(.plain).accessibilityLabel("Dismiss message") }
                    HStack(spacing: 14) {
                        if model.errorOffersSettings { Button("Open Settings") { model.openSettingsInCoach() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent) }
                        if model.context.hasSelection { Button("Change window") { model.context.choose() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent) }
                    }
                }.padding(.horizontal, 18).padding(.bottom, 8)
            }
            if ReplyRetry.isAvailable(busy: model.busy, hasFailedQuestion: model.hasFailedQuestion, lastRole: model.active?.messages.last?.role) {
                HStack { Button("Retry message") { model.retry() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent); Spacer(minLength: 0) }.padding(.horizontal, 18).padding(.bottom, 8)
            }
            if model.paused, model.active != nil {
                HStack { Text("Paused · mic and sharing off").font(.system(size: 11)).foregroundStyle(Theme.muted); Spacer(); Button("Resume") { model.togglePause() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.accent) }.padding(.horizontal, 18).padding(.bottom, 6)
            }
            if model.active?.mode == .learn, !model.settingsInCoach { HStack(spacing: 10) {
                Button("Hint") { model.nextHint() }.buttonStyle(.plain)
                Button("Point it out") { model.pointItOut() }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }.font(.system(size: 12)).foregroundStyle(Theme.muted).disabled(model.busy || model.paused || model.active == nil).padding(.horizontal, 18).padding(.bottom, 6) }
            if !model.pendingFiles.isEmpty {
                let row = HStack(spacing:7){ForEach(model.pendingFiles){record in FileChip(record:record,among:model.pendingFiles,model:model,removable:SentFile.canRemove(id:record.id,session:model.active))}}.padding(.horizontal,18)
                if FileScroll.usesScroll(fileCount: model.pendingFiles.count) { ScrollView(.horizontal){ row }.scrollIndicators(.hidden).stayInTheCoach().padding(.bottom,10) } else { row.stayInTheCoach().padding(.bottom,10) }
            }
            VStack(alignment: .leading, spacing: ComposerRows.spacing) {
                HStack(alignment: .bottom, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        if model.draft.isEmpty { Text(WaitingField.shown(waiting: model.busy)).font(.system(size: 15, weight: ComposerPrompt.usesMediumWeight ? .medium : .regular)).foregroundStyle(Theme.muted.opacity(ComposerPrompt.opacity)).padding(.top, ComposerPrompt.topInset).padding(.leading, ComposerPrompt.leadingInset).allowsHitTesting(false) }
                        DraftEditor(text: Binding(get:{model.draft},set:{model.editDraft($0)}), submit: { commitComposerMarkedText(); if ComposerReturn.sends(whileWaiting: model.busy) { model.send() } }, cancel: { model.stopInteraction() }, pasteFiles:{urls in Task{await model.importFiles(urls)}}, pasteImage:{model.pasteImage($0)}, onMeasuredHeight: { measured in let next = CGFloat(ComposerHeight.clamped(Double(measured))); if composerHeight != next { composerHeight = next } }).frame(height: composerHeight)
                    }.frame(maxWidth: .infinity, alignment: .leading).help("Return sends. Shift–Return adds a line.")
                    Button {
                        if model.busy {
                            if SendGesture.stops(elapsed: Date().timeIntervalSince(model.sentAt)) { model.stopResponse() }
                        } else { commitComposerMarkedText(); model.send() }
                    } label: {
                        let filled = SendMark.filled(hasInput: model.hasInput, busy: model.busy, hasChat: model.active != nil, importing: model.importing)
                        Image(systemName: model.busy ? "stop.fill" : "arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(filled ? Color.black.opacity(0.82) : Theme.muted).frame(width: 30, height: 30).background(Theme.accent.opacity(filled ? 1 : 0.12)).clipShape(Circle())
                    }.buttonStyle(.plain).disabled(!model.busy && (!model.hasInput || !PausedTyping.allowsQuestion(paused: model.paused) || model.active == nil || model.importing)).help(model.busy ? "Stop response" : "Send message").accessibilityLabel(model.busy ? "Stop response" : "Send message")
                }
                HStack(spacing: ComposerRows.spacing) {
                    IconButton(symbol: "plus", label: AttachControl.title, compact: true, quiet: true) { model.attachFiles() }.disabled(model.importing)
                    IconButton(symbol:"globe",label:WebSearchLabel.title(enabled: model.active?.webEnabled == true),tint:model.active?.webEnabled == true ? Theme.accent : Theme.muted, compact: true, quiet: true){model.setWeb(!(model.active?.webEnabled ?? false))}.disabled(!WebToggle.changes(waiting: model.busy))
                    if !GuideControl.inTheMenu {
                    IconButton(symbol:"list.number",label:GuideControl.title, compact: true){
                        if GuideStart.needsConfirmation(draft: model.draft, attachmentCount: model.pendingFiles.count) { confirmGuide = true } else { model.startGuide() }
                    }.disabled(model.busy || model.paused)
                    }
                    Spacer()
                    Button{model.setConversation(!model.conversation)}label:{Text(ConversationControl.title(on: model.conversation)).font(.system(size:11)).foregroundStyle(model.conversation ? Theme.accent : Theme.muted)}.buttonStyle(.plain).disabled(model.paused).help("Opt in to hands-free turn-taking; tap mic or press Escape to interrupt")
                    if model.voice.speaking { IconButton(symbol: "stop.fill", label: "Stop playback", tint: Theme.accent, compact: true, quiet: true) { model.stopResponse() } }
                    IconButton(symbol: model.voice.listening ? "mic.fill" : "mic", label: model.voice.listening ? "Finish speaking" : (model.voice.speaking || model.busy ? "Interrupt and talk" : "Talk"), tint: model.voice.listening ? Theme.accent : Theme.muted, compact: true) { model.toggleVoice() }.disabled(model.paused || model.active == nil)
                }
            }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 4)
            let idle = !model.paused && !model.importing && !model.voice.starting && !model.voice.listening && !model.busy && !model.voice.speaking && !model.conversation && model.active?.webEnabled != true
            if !idle { Text(model.status).font(.system(size: 11)).foregroundStyle(model.voice.listening ? Theme.accent : Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.bottom, 6) }
            if ShareRow.afterTheComposer, !model.settingsInCoach { ContextStrip(model: model).padding(.bottom, 12) }
        }.modifier(CapsuleChrome(enabled: !hidesHeader))
            .environment(\.openURL,OpenURLAction{url in AnswerLink.canOpen(url) ? .systemAction : .discarded})
            .alert("Show the walkthrough?", isPresented: $walkthrough) {
                Button("Keep thinking", role: .cancel) {}
                Button("Show walkthrough") { model.send("Please give me the full walkthrough now, explaining why each step works.", reveal: true) }
            } message: { Text("This will reveal the method. Your current hints stay in the conversation.") }
            .alert("Start a step-by-step guide?", isPresented: $confirmGuide) {
                Button("Keep writing", role: .cancel) {}
                Button("Start guide") { model.startGuide() }
            } message: { Text("This sends what you have typed and clears the composer.") }
    }

    private func scrollThread(_ proxy: ScrollViewProxy) {
        let last = model.active?.messages.last
        if QuestionScroll.opensAtTheStart(role: last?.role, text: last?.text ?? ""), let id = last?.id {
            proxy.scrollTo(id, anchor: .top)
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

struct MessageText: View {
    let message: Message
    var body: some View {
        if message.showsMarkdown {
            let prepared = ReadableLine.display(ReplyAddress.forDisplay(ReplyLines.forDisplay(message.text)))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(ReplyCode.segments(prepared).enumerated()), id: \.offset) { _, segment in
                    if segment.code {
                        Text(segment.text).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if needsLiteral(segment.text) {
                        Text(segment.text)
                    } else {
                        Text(.init(segment.text))
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
    func stayInTheCoach() -> some View { self }
}

struct EmptyGreeting: View {
    @ObservedObject var model: AppModel
    let session: LearningSession
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.mode == .learn ? "Think it through with a little guidance." : OpeningLine.assistant).font(.system(size: EmptyCoach.bodySize)).foregroundStyle(Theme.muted).lineSpacing(2)
            if EmptyThread.showsPlace { Text(EmptyThread.line).font(.system(size: EmptyCoach.kickerSize)).foregroundStyle(Theme.muted) }
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
            Text(notice.title).font(.system(size: 12)).foregroundStyle(Theme.ink)
            Text(notice.detail).font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Button("Settings") { model.openSettingsInCoach() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private extension View {
    @ViewBuilder func replyClip(_ role: String) -> some View {
        if ReplyControls.clips(role) { self.clipShape(RoundedRectangle(cornerRadius: 2)) } else { self }
    }
}
