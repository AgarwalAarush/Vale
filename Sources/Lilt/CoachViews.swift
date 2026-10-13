import SwiftUI
import LiltCore

struct CapsuleView: View {
    @ObservedObject var model: AppModel
    var openCoach: () -> Void
    var body: some View {
        HStack(spacing: 15) {
            Button(action: openCoach) { AudioMark(active: model.voice.listening || model.voice.speaking) }.buttonStyle(.plain).help("Open coach")
            Button(action: openCoach) {
                HStack(spacing: 12) {
                    Text(model.active?.timerText ?? "30:00").font(.system(size: 13, weight: .semibold, design: .monospaced)).monospacedDigit()
                    Text(model.active?.title ?? "Lilt").font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: 118, alignment: .leading)
                }
            }.buttonStyle(.plain).help("Type a question")
            Spacer(minLength: 0)
            IconButton(symbol: model.voice.listening ? "mic.fill" : "mic", label: model.voice.listening ? "Finish speaking" : "Talk", tint: model.voice.listening ? Theme.accent : Theme.ink) { model.toggleVoice() }.disabled(model.paused || model.active == nil)
            Button { model.togglePause() } label: { Label(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill").font(.system(size: 12, weight: .medium)) }.buttonStyle(QuietButton(filled: true)).disabled(model.active == nil)
            Menu {
                Button("Open coach", action: openCoach)
                Button("Session library") { model.showLibrary?() }
                if model.active != nil { Button("Complete session") { model.complete() } }
                Divider()
                Button("Settings…") { model.settings = true; model.showLibrary?() }
                Button("Quit Lilt") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "ellipsis").font(.system(size: 15)).frame(width: 20, height: 28) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More options")
        }.padding(.horizontal, 20).frame(height: 62).modifier(GlassSurface(radius: 20))
    }
}

struct CoachView: View {
    @ObservedObject var model: AppModel
    var close: () -> Void
    @State private var walkthrough = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                LogoMark(); Text("Lilt").font(.system(size: 15, weight: .semibold))
                Spacer()
                IconButton(symbol: "rectangle.stack", label: "Session library") { model.showLibrary?() }
                Menu {
                    Toggle("Read typed replies aloud", isOn: $model.readAloud)
                    Button("Show a full walkthrough…") { walkthrough = true }.disabled(model.active?.messages.isEmpty != false || model.busy)
                    Button("Complete session") { model.complete() }.disabled(model.active == nil)
                    Divider(); Button("Settings…") { model.settings = true; model.showLibrary?() }
                } label: { Image(systemName: "ellipsis").font(.system(size: 14)).frame(width: 24, height: 30) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                IconButton(symbol: "xmark", label: "Collapse coach", action: close)
            }.padding(.horizontal, 18).padding(.top, 15).padding(.bottom, 11)
            HStack(spacing: 8) {
                Image(systemName: model.attachment != nil ? "photo" : "macwindow").font(.system(size: 12)).foregroundStyle(Theme.muted)
                if let context = model.contextName {
                    Button { model.previewContext() } label: { Text(context).lineLimit(1).font(.system(size: 11)).foregroundStyle(Theme.muted) }.buttonStyle(.plain).help("Preview shared context")
                    Spacer(minLength: 4)
                    Button("Stop sharing") { model.stopSharing() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
                } else {
                    Button("Share a window") { model.context.choose() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.muted).disabled(model.paused)
                    Spacer()
                    Text("Optional").font(.system(size: 10)).foregroundStyle(Theme.muted.opacity(0.65))
                }
            }.padding(.horizontal, 13).padding(.vertical, 10).background(.white.opacity(0.025)).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 18)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let session = model.active {
                            if session.messages.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("ONE HINT AT A TIME").font(.system(size: 9, weight: .medium)).tracking(1.1).foregroundStyle(Theme.muted)
                                    Text("What are we\nworking through?").font(.system(size: 24, weight: .medium)).tracking(-0.55).lineSpacing(1)
                                    Text("Ask a question, or share a window for context.").font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(3)
                                }.padding(.top, 16)
                            }
                            ForEach(session.messages) { message in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(message.role == "user" ? "YOU" : "LILT").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Theme.muted)
                                    Text(.init(message.text)).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
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
                                Button("Start a session") { model.showLibrary?() }.buttonStyle(QuietButton(filled: true))
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
                    HStack(alignment: .top, spacing: 8) { Text(error).font(.system(size: 11)).foregroundStyle(Color(red: 0.96, green: 0.77, blue: 0.49)); Spacer(minLength: 0); Button { model.error = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain) }
                    HStack(spacing: 14) {
                        if model.active?.messages.last?.role == "user" { Button("Retry question") { model.retry() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent) }
                        if model.context.filter != nil { Button("Change window") { model.context.choose() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent) }
                    }
                }.padding(11).background(Color.orange.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 18).padding(.bottom, 10)
            }
            if model.paused, model.active != nil {
                HStack { Text("Paused · mic and sharing off").font(.system(size: 11)).foregroundStyle(Theme.muted); Spacer(); Button("Resume") { model.togglePause() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.accent) }.padding(.horizontal, 20).padding(.bottom, 10)
            }
            HStack(spacing: 9) {
                Button { model.nextHint() } label: { Label("Hint", systemImage: "lightbulb").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
                Button { model.pointItOut() } label: { Label("Point it out", systemImage: "cursorarrow.rays").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
            }.disabled(model.busy || model.paused || model.active == nil).padding(.horizontal, 18).padding(.bottom, 10)
            VStack(spacing: 3) {
                ZStack(alignment: .topLeading) {
                    if model.draft.isEmpty { Text("Ask quietly…").font(.system(size: 14)).foregroundStyle(Theme.muted.opacity(0.8)).padding(.top, 6).padding(.leading, 7).allowsHitTesting(false) }
                    DraftEditor(text: $model.draft, submit: { model.send() }, cancel: { model.cancel(); model.voice.stop() }).frame(height: 61)
                }
                HStack {
                    IconButton(symbol: "plus", label: "Attach an image") { model.attachImage() }.disabled(model.paused)
                    Spacer()
                    if model.voice.speaking { IconButton(symbol: "stop.fill", label: "Stop playback", tint: Theme.accent) { model.voice.stopSpeaking() } }
                    IconButton(symbol: model.voice.listening ? "mic.fill" : "mic", label: model.voice.listening ? "Finish speaking" : "Talk", tint: model.voice.listening ? Theme.accent : Theme.muted) { model.toggleVoice() }.disabled(model.paused || model.active == nil)
                    Button { if model.busy { model.cancel() } else { model.send() } } label: {
                        Image(systemName: model.busy ? "stop.fill" : "arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).frame(width: 30, height: 30).background(Theme.accent.opacity(model.draft.isEmpty && !model.busy ? 0.12 : 0.35)).clipShape(Circle())
                    }.buttonStyle(.plain).disabled(!model.busy && (model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.paused || model.active == nil)).help(model.busy ? "Stop response" : "Send question").accessibilityLabel(model.busy ? "Stop response" : "Send question")
                }
            }.padding(9).background(.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.8)).padding(.horizontal, 18)
            HStack {
                Text(model.status).font(.system(size: 10)).foregroundStyle(model.voice.listening ? Theme.accent : Theme.muted)
                Spacer()
                Text("⌃⌥Space").font(.system(size: 10)).foregroundStyle(Theme.muted.opacity(0.75)).help("Open the coach from anywhere")
            }.padding(.horizontal, 21).padding(.top, 7).padding(.bottom, 14)
        }.modifier(GlassSurface(radius: 20))
            .alert("Show the walkthrough?", isPresented: $walkthrough) {
                Button("Keep thinking", role: .cancel) {}
                Button("Show walkthrough") { model.send("Please give me the full walkthrough now, explaining why each step works.", reveal: true) }
            } message: { Text("This will reveal the method. Your current hints stay in the conversation.") }
    }
}
