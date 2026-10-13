import SwiftUI
import LiltCore

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var topic = ""
    @State private var minutes = 30
    @State private var deleteID: UUID?
    var body: some View {
        Group {
            if model.onboarding { WelcomeView(model: model) }
            else {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) { LogoMark(size: 26); Text("Lilt").font(.system(size: 18, weight: .semibold)).tracking(-0.5) }.padding(.horizontal, 22).padding(.top, 35).padding(.bottom, 32)
                        Button { model.selectedID = nil; model.settings = false } label: { Label("Library", systemImage: "rectangle.stack").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10).background(model.selectedID == nil && !model.settings ? Color.white.opacity(0.065) : .clear).clipShape(RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).padding(.horizontal, 12)
                        HStack { Text("SESSIONS").font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(Theme.muted); Spacer(); Button { model.selectedID = nil; model.settings = false } label: { Image(systemName: "plus").font(.system(size: 11)) }.buttonStyle(.plain).help("New session") }.padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 12)
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(model.sessions) { session in
                                    Button { model.selectedID = session.id; model.settings = false } label: {
                                        HStack(spacing: 9) { Image(systemName: session.completed ? "checkmark.circle" : "bubble.left").font(.system(size: 12)).foregroundStyle(Theme.muted); Text(session.title).font(.system(size: 12)).lineLimit(1); Spacer(minLength: 0) }.padding(.horizontal, 12).padding(.vertical, 10).background(model.selectedID == session.id && !model.settings ? .white.opacity(0.065) : .clear).clipShape(RoundedRectangle(cornerRadius: 8))
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.horizontal, 12)
                        }.scrollIndicators(.hidden)
                        Spacer(minLength: 15)
                        Button { model.settings = true } label: { Label("Settings", systemImage: "slider.horizontal.3").font(.system(size: 12)).foregroundStyle(Theme.muted) }.buttonStyle(.plain).padding(24)
                    }.frame(width: 194).background(Color.black.opacity(0.12))
                    Rectangle().fill(Theme.line).frame(width: 1)
                    Group {
                        if model.settings { SettingsView(model: model) }
                        else if let session = model.selected { SessionDetail(model: model, session: session, deleteAction: { deleteID = session.id }) }
                        else { home }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.foregroundStyle(Theme.ink).background(Theme.background).preferredColorScheme(.dark)
        .alert("Forget this session?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("Cancel", role: .cancel) { deleteID = nil }
            Button("Forget session", role: .destructive) { if let id = deleteID { model.delete(id) }; deleteID = nil }
        } message: { Text("The conversation and takeaway will be removed from this Mac.") }
    }
    var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your next good question.").font(.system(size: 29, weight: .medium)).tracking(-0.8).padding(.bottom, 10)
                Text("A little help with what you’re learning.").font(.system(size: 14)).foregroundStyle(Theme.muted).padding(.bottom, 30)
                HStack(spacing: 12) {
                    TextField("LeetCode, a paper, a new idea…", text: $topic).textFieldStyle(.plain).font(.system(size: 15)).onSubmit(start)
                    Button(action: start) { Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .semibold)).frame(width: 34, height: 34).background(Theme.accent.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain).help("Start learning").accessibilityLabel("Start learning")
                }.padding(13).background(.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.12), lineWidth: 0.8))
                HStack { Text("Session length").font(.system(size: 11)).foregroundStyle(Theme.muted); Menu { ForEach([15,30,45,60], id: \.self) { value in Button("\(value) min") { minutes = value } } } label: { HStack(spacing: 7) { Text("\(minutes) min"); Image(systemName: "chevron.down").font(.system(size: 8)) }.font(.system(size: 11)).padding(.horizontal, 9).padding(.vertical, 6).background(.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 6)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(); Spacer() }.padding(.top, 10).padding(.bottom, 36)
                if model.sessions.isEmpty {
                    Divider().overlay(Theme.line)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Start with what’s in front of you.").font(.system(size: 17, weight: .medium))
                        Text("Type a question, talk it through, or choose a window for context. Your sessions will live here.").font(.system(size: 13)).lineSpacing(4).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 24)
                } else {
                    Text("RECENT").font(.system(size: 10, weight: .medium)).tracking(1.2).foregroundStyle(Theme.muted).padding(.bottom, 15)
                    ForEach(model.sessions.prefix(7)) { session in
                        Button { model.selectedID = session.id } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(session.title).font(.system(size: 15, weight: .medium))
                                    Text(session.takeaway.isEmpty ? (session.messages.last?.text ?? "Ready to pick up again.") : session.takeaway).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer(minLength: 20)
                                Text(session.updated, style: .date).font(.system(size: 11)).foregroundStyle(Theme.muted)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.muted)
                            }.padding(.vertical, 17)
                        }.buttonStyle(.plain)
                        Divider().overlay(Theme.line)
                    }
                }
                if let error = model.error { Text(error).font(.system(size: 12)).foregroundStyle(.orange.opacity(0.9)).padding(.top, 20) }
            }.padding(.horizontal, 43).padding(.top, 61).padding(.bottom, 40).frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.hidden)
    }
    func start() { model.newSession(title: topic.isEmpty ? "Learning session" : topic, minutes: minutes); topic = "" }
}

struct WelcomeView: View {
    @ObservedObject var model: AppModel
    @State private var topic = "LeetCode"
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LogoMark(size: 38).padding(.bottom, 30)
            Text("A little help,\nright where you work.").font(.system(size: 34, weight: .medium)).tracking(-1).lineSpacing(2).padding(.bottom, 18)
            Text("Type a question or talk it through. Share a window when you want Lilt to see the context.").font(.system(size: 14)).foregroundStyle(Theme.muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true).padding(.bottom, 30)
            Text("WHAT ARE YOU LEARNING?").font(.system(size: 9, weight: .medium)).tracking(1.1).foregroundStyle(Theme.muted).padding(.bottom, 10)
            TextField("A topic or task", text: $topic).textFieldStyle(.plain).font(.system(size: 15)).padding(14).background(.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line)).onSubmit { model.newSession(title: topic) }
            HStack {
                Button("Start learning") { model.newSession(title: topic) }.buttonStyle(QuietButton(filled: true))
                Button("Explore library") { model.onboarding = false; UserDefaults.standard.set(true, forKey: "onboardingComplete") }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.leading, 12)
            }.padding(.top, 18)
            Text("Uses your Codex sign-in. No microphone or screen access until you choose it.").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(3).padding(.top, 32)
        }.frame(maxWidth: 410, alignment: .leading).frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}

struct SessionDetail: View {
    @ObservedObject var model: AppModel
    let session: LearningSession
    let deleteAction: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(session.title).font(.system(size: 27, weight: .medium)).tracking(-0.7)
                        Text("\(session.completed ? "Completed" : "In progress") · \(session.elapsed < 60 ? "<1 min" : "\(session.elapsed / 60) min") · \(session.messages.filter { $0.role == "user" }.count) \(session.messages.filter { $0.role == "user" }.count == 1 ? "question" : "questions")").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Menu {
                        Button("Export notes…") { model.export(session) }
                        Button("Forget session…", role: .destructive, action: deleteAction)
                    } label: { Image(systemName: "ellipsis").frame(width: 25, height: 25) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                Button(session.id == model.activeID ? "Return to session" : "Continue learning") { if session.id == model.activeID { model.showCoach?() } else { model.resume(session.id) } }.buttonStyle(QuietButton(filled: true))
                Divider().overlay(Theme.line)
                VStack(alignment: .leading, spacing: 10) {
                    Text("WHAT CLICKED?").font(.system(size: 10, weight: .medium)).tracking(1.1).foregroundStyle(Theme.muted)
                    TextEditor(text: Binding(get: { model.sessions.first { $0.id == session.id }?.takeaway ?? "" }, set: { model.setTakeaway($0, for: session.id) }))
                        .font(.system(size: 14)).scrollContentBackground(.hidden).frame(minHeight: 70).padding(9).background(.white.opacity(0.025)).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line)).accessibilityLabel("Your takeaway")
                    Text("Keep one idea in your own words. You can edit or forget it anytime.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                if !session.messages.isEmpty {
                    Divider().overlay(Theme.line)
                    ForEach(session.messages) { message in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(message.role == "user" ? "YOU" : "LILT").font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(Theme.muted)
                            Text(.init(message.text)).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.vertical, 5)
                    }
                }
            }.padding(.horizontal, 42).padding(.top, 54).padding(.bottom, 40)
        }.scrollIndicators(.hidden)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("model") private var modelName = ""
    @State private var connection = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Settings").font(.system(size: 28, weight: .medium)).tracking(-0.7)
                VStack(alignment: .leading, spacing: 12) {
                    Text("ChatGPT via Codex").font(.system(size: 16, weight: .medium))
                    Text(connection.isEmpty ? (model.provider.executable == nil ? "Codex wasn’t found on this Mac." : "Uses the sign-in saved by your Codex CLI.") : connection).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Button("Check connection") { checkConnection() }.buttonStyle(QuietButton())
                    Text("To sign in, run codex login in Terminal.").font(.system(size: 11)).foregroundStyle(Theme.muted).textSelection(.enabled)
                }
                Divider().overlay(Theme.line)
                Toggle("Read typed replies aloud", isOn: $model.readAloud).toggleStyle(.switch).font(.system(size: 13))
                Text("The microphone turns on only when you choose Talk. Spoken questions use Apple’s speech recognition; on-device recognition is used when available.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                Divider().overlay(Theme.line)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your context, your choice").font(.system(size: 16, weight: .medium))
                    Text("Only your messages and the window or image you explicitly share are sent to the tutor when you ask. A selected window includes whichever page is visible inside it.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                    Text("Sessions and takeaways stay in this Mac’s Lilt library. Lilt doesn’t save microphone recordings or screenshots in your library.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                }
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Codex executable").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        TextField("Auto-detect", text: $codexPath).textFieldStyle(.roundedBorder).font(.system(size: 12))
                        Text("Model").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        TextField("Codex default", text: $modelName).textFieldStyle(.roundedBorder).font(.system(size: 12))
                    }.padding(.top, 15)
                }.font(.system(size: 12))
                Text("Open coach anywhere: Control–Option–Space").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text("Lilt 1.0 · Built for focused learning").font(.system(size: 11)).foregroundStyle(Theme.muted.opacity(0.7))
            }.padding(.horizontal, 42).padding(.top, 54).padding(.bottom, 40)
        }.scrollIndicators(.hidden)
    }
    func checkConnection() {
        guard let path = model.provider.executable else { connection = "Codex wasn’t found. Choose its path below."; return }
        connection = "Checking…"
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = ["login", "status"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        process.terminationHandler = { process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async { connection = process.terminationStatus == 0 ? (text.contains("ChatGPT") ? "Signed in with ChatGPT." : "Codex is signed in.") : "Not signed in. Run codex login in Terminal." }
        }
        do { try process.run() } catch { connection = "Couldn’t launch Codex. Check the executable path." }
    }
}
