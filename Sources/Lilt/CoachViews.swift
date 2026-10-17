import SwiftUI
import LiltCore

struct CapsuleView: View {
    @ObservedObject var model: AppModel
    var openCoach: () -> Void
    var body: some View {
        HStack(spacing: 15) {
            Button(action: openCoach) {HStack(spacing:5){AudioMark(active: model.voice.listening || model.voice.speaking);if model.context.hasSelection{Image(systemName:model.context.live ? "record.circle.fill" : "macwindow").font(.system(size:10)).foregroundStyle(Theme.accent)}}}.buttonStyle(.plain).help(model.context.live ? "Live window context is on" : "Open assistant").accessibilityLabel(model.context.live ? "Open assistant. Live window context is on" : "Open assistant")
            Button(action: openCoach) {
                HStack(spacing: 12) {
                    if let chat=model.active,chat.duration>0 { Text(chat.timerText).font(.system(size:13,weight:.semibold,design:.monospaced)).monospacedDigit() }
                    Text(model.active?.title == "New chat" ? "Vale" : model.active?.title ?? "Vale").font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: model.active?.duration == 0 ? (model.context.hasSelection ? 150 : 185) : 118, alignment: .leading)
                }
            }.buttonStyle(.plain).help("Type a question")
            Spacer(minLength: 0)
            IconButton(symbol: model.voice.listening ? "mic.fill" : "mic", label: model.voice.listening ? "Finish speaking" : (model.voice.speaking || model.busy ? "Interrupt and talk" : "Talk"), tint: model.voice.listening ? Theme.accent : Theme.ink) { model.toggleVoice() }.disabled(model.paused || model.active == nil)
            Button { model.togglePause() } label: { Label(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill").font(.system(size: 12, weight: .medium)) }.buttonStyle(QuietButton(filled: true)).disabled(model.active == nil)
            Menu {
                Button("Open coach", action: openCoach)
                Button("Chat history") { model.showLibrary?() }
                if model.active != nil { Button("Close chat") { model.complete() } }
                Divider()
                Button("Settings…") { model.settings = true; model.showLibrary?() }
                Button("Quit Vale") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "ellipsis").font(.system(size: 15)).frame(width: 20, height: 28) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More options")
        }.padding(.horizontal, 20).frame(height: 62).modifier(GlassSurface(radius: 20))
    }
}

struct CoachView: View {
    @ObservedObject var model: AppModel
    var close: () -> Void
    @State private var walkthrough = false
    private var voiceTools: some View {
        Group {
            if model.voice.speaking { IconButton(symbol: "stop.fill", label: "Stop playback", tint: Theme.accent) { model.stopResponse() } }
            IconButton(symbol: model.voice.listening ? "mic.fill" : "mic", label: model.voice.listening ? "Finish speaking" : (model.voice.speaking || model.busy ? "Interrupt and talk" : "Talk"), tint: model.voice.listening ? Theme.accent : Theme.muted) { model.toggleVoice() }.disabled(model.paused || model.active == nil)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                LogoMark(); Text("Vale").font(.system(size: 15, weight: .semibold))
                Spacer()
                Menu {
                    Button("Assistant") {model.setMode(.assistant)}
                    Button("Learn with hints") {model.setMode(.learn)}
                } label: {Text(model.active?.mode.label ?? "Ask").font(.system(size:11)).foregroundStyle(Theme.muted)}.menuStyle(.borderlessButton).fixedSize().help("Choose assistant or learning mode")
                IconButton(symbol: "rectangle.stack", label: "Chat history") { model.showLibrary?() }
                Menu {
                    Toggle("Read typed replies aloud", isOn: $model.readAloud)
                    Button("New chat") {model.newSession()}
                    Button("Point it out") {model.pointItOut()}.disabled(!model.context.hasSelection || model.busy)
                    if model.active?.mode == .learn { Button("Show a full walkthrough…") { walkthrough = true }.disabled(model.active?.messages.isEmpty != false || model.busy) }
                    Menu("Focus timer") {Button("30 minutes"){model.setFocus(minutes:30)};Button("60 minutes"){model.setFocus(minutes:60)};Button("No timer"){model.setFocus(minutes:0)}}
                    Button("Close chat") { model.complete() }.disabled(model.active == nil)
                    Divider(); Button("Settings…") { model.settings = true; model.showLibrary?() }
                } label: { Image(systemName: "ellipsis").font(.system(size: 14)).frame(width: 24, height: 30) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                IconButton(symbol:model.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",label:model.expanded ? "Compact assistant" : "Expand assistant"){model.expandCoach?()}
                IconButton(symbol: "xmark", label: "Collapse coach", action: close)
            }.padding(.horizontal, 18).padding(.top, 15).padding(.bottom, 11)
            ContextStrip(model:model)
            if let warning=model.shortcutWarning{Text(warning).font(.system(size:10)).foregroundStyle(.orange).padding(.horizontal,20).padding(.top,8)}
            if model.active?.contextLimited == true{
                HStack(alignment:.top,spacing:7){Image(systemName:"clock.arrow.circlepath");Text("Using recent messages only. Earlier context stays in History.");Spacer(minLength:0);Button("History"){model.showLibrary?()}.buttonStyle(.plain).foregroundStyle(Theme.accent)}.font(.system(size:10)).foregroundStyle(Theme.muted).padding(.horizontal,20).padding(.top,10)
            }
            if let guide=model.active?.guide{GuideCard(model:model,guide:guide)}
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let session = model.active {
                            if session.messages.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(session.mode == .learn ? "ONE HINT AT A TIME" : "HERE WHEN YOU NEED A HAND").font(.system(size: 9, weight: .medium)).tracking(1.1).foregroundStyle(Theme.muted)
                                    Text(session.mode == .learn ? "What are we\nworking through?" : "How can I help?").font(.system(size: 24, weight: .medium)).tracking(-0.55).lineSpacing(1)
                                    Text(session.mode == .learn ? "Think it through with a little guidance." : "Ask anything, drop a file, or share a window.").font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(3)
                                    if model.provider.executable == nil {
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("Codex isn’t available yet. Install the CLI and run codex login, or choose it in Settings.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
                                            Spacer(minLength: 0)
                                            Button("Settings") { model.openSettings() }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                                        }
                                    }
                                }.padding(.top, 16)
                            }
                            ForEach(session.messages) { message in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(message.role == "user" ? "YOU" : "LILT").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Theme.muted)
                                    Text(.init(message.text)).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    if !message.attachments.isEmpty {
                                        ScrollView(.horizontal) {HStack(spacing:7){ForEach(message.attachments){record in FileChip(record:record,model:model,removable:true)}}}.scrollIndicators(.hidden)
                                    }
                                    if message.highlightUnavailable{Label("Highlight unavailable · check your selected window",systemImage:"eye.slash").font(.system(size:10)).foregroundStyle(Theme.muted)}
                                    if message.screenChanged{
                                        HStack{Image(systemName:"arrow.clockwise");Text("Window changed during this answer");if message.id==model.active?.messages.last?.id{Button("Refresh"){model.refreshAnswer()}.buttonStyle(.plain).foregroundStyle(Theme.accent)}}.font(.system(size:10)).foregroundStyle(Theme.muted)
                                    }
                                    if message.role == "assistant" {
                                        HStack(spacing: 8) {
                                            IconButton(symbol: "speaker.wave.2", label: "Read this reply") { model.voice.speak(message.text) }
                                            IconButton(symbol: "doc.on.doc", label: "Copy reply") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) }
                                        }.padding(.leading, -7)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(message.role == "user" ? 12 : 0)
                                    .background(message.role == "user" ? Color.white.opacity(0.035) : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .id(message.id)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Ready when you are.").font(.system(size: 23, weight: .medium)).tracking(-0.5)
                                Button("New chat") { model.prepareChat() }.buttonStyle(QuietButton(filled: true))
                            }.padding(.top, 24)
                        }
                        if model.busy { HStack(spacing: 8) { ProgressView().controlSize(.mini); Text("Thinking…").font(.system(size: 12)).foregroundStyle(Theme.muted) }.padding(.vertical, 5).id("thinking") }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 20).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading)
                }.scrollIndicators(.hidden)
                .onChange(of: model.active?.messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: model.busy) { proxy.scrollTo("bottom", anchor: .bottom) }
            }.frame(maxHeight: .infinity)
            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) { Text(error).font(.system(size: 11)).foregroundStyle(Color(red: 0.96, green: 0.77, blue: 0.49)); Spacer(minLength: 0); Button { model.error = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).accessibilityLabel("Dismiss message") }
                    HStack(spacing: 14) {
                        if model.active?.messages.last?.role == "user" { Button("Retry message") { model.retry() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent) }
                        if model.errorOffersSettings { Button("Open Settings") { model.openSettings() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent) }
                        if model.context.hasSelection { Button("Change window") { model.context.choose() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent) }
                    }
                }.padding(11).background(Color.orange.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 18).padding(.bottom, 10)
            }
            if model.paused, model.active != nil {
                HStack { Text("Paused · mic and sharing off").font(.system(size: 11)).foregroundStyle(Theme.muted); Spacer(); Button("Resume") { model.togglePause() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.accent) }.padding(.horizontal, 20).padding(.bottom, 10)
            }
            if model.active?.mode == .learn { HStack(spacing: 9) {
                Button { model.nextHint() } label: { Label("Hint", systemImage: "lightbulb").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
                Button { model.pointItOut() } label: { Label("Point it out", systemImage: "cursorarrow.rays").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
            }.disabled(model.busy || model.paused || model.active == nil).padding(.horizontal, 18).padding(.bottom, 10) }
            if !model.pendingFiles.isEmpty {ScrollView(.horizontal){HStack(spacing:7){ForEach(model.pendingFiles){record in FileChip(record:record,model:model,removable:true)}}.padding(.horizontal,18)}.scrollIndicators(.hidden).padding(.bottom,10)}
            VStack(spacing: 3) {
                ZStack(alignment: .topLeading) {
                    if model.draft.isEmpty { Text("Ask quietly…").font(.system(size: 14)).foregroundStyle(Theme.muted.opacity(0.8)).padding(.top, 6).padding(.leading, 7).allowsHitTesting(false) }
                    DraftEditor(text: Binding(get:{model.draft},set:{model.editDraft($0)}), submit: { model.send() }, cancel: { model.stopInteraction() }, pasteFiles:{urls in Task{await model.importFiles(urls)}}, pasteImage:{model.pasteImage($0)}).frame(height: 61)
                }
                HStack {
                    IconButton(symbol: "plus", label: "Attach files") { model.attachFiles() }.disabled(model.importing)
                    IconButton(symbol:"globe",label:model.active?.webEnabled == true ? "Web search on" : "Enable web search",tint:model.active?.webEnabled == true ? Theme.accent : Theme.muted){model.setWeb(!(model.active?.webEnabled ?? false))}
                    IconButton(symbol:"list.number",label:"Start step-by-step help"){model.startGuide()}.disabled(model.busy || model.paused)
                    if MicPlacement.withTheTools { voiceTools }
                    Spacer()
                    if !MicPlacement.withTheTools { voiceTools }
                    Button { if model.busy { model.stopResponse() } else { model.send() } } label: {
                        Image(systemName: model.busy ? "stop.fill" : "arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).frame(width: 30, height: 30).background(Theme.accent.opacity(!model.hasInput && !model.busy ? 0.12 : 0.35)).clipShape(Circle())
                    }.buttonStyle(.plain).disabled(!model.busy && (!model.hasInput || model.paused || model.active == nil || model.importing)).help(model.busy ? "Stop response" : "Send message").accessibilityLabel(model.busy ? "Stop response" : "Send message")
                }
            }.padding(9).background(.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.8)).padding(.horizontal, 18)
            HStack {
                Text(model.status).font(.system(size: 10)).foregroundStyle(model.voice.listening ? Theme.accent : Theme.muted)
                Spacer()
                Button{model.setConversation(!model.conversation)}label:{Label(model.conversation ? "End conversation" : "Conversation",systemImage:model.conversation ? "waveform.circle.fill" : "waveform.circle").font(.system(size:10)).foregroundStyle(model.conversation ? Theme.accent : Theme.muted)}.buttonStyle(.plain).disabled(model.paused).help("Opt in to hands-free turn-taking; tap mic or press Escape to interrupt")
            }.padding(.horizontal, 21).padding(.top, 7).padding(.bottom, 14)
        }.modifier(GlassSurface(radius: 20))
            .dropDestination(for:URL.self){urls,_ in Task{await model.importFiles(urls)};return urls.contains(where:{$0.isFileURL})}
            .environment(\.openURL,OpenURLAction{url in ["https","http"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded})
            .alert("Show the walkthrough?", isPresented: $walkthrough) {
                Button("Keep thinking", role: .cancel) {}
                Button("Show walkthrough") { model.send("Please give me the full walkthrough now, explaining why each step works.", reveal: true) }
            } message: { Text("This will reveal the method. Your current hints stay in the conversation.") }
    }
}
