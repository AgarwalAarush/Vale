import SwiftUI
import LiltCore

private final class SignInWait: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false
    func markTimedOut() { lock.lock(); timedOut = true; lock.unlock() }
    func didTimeOut() -> Bool { lock.lock(); defer { lock.unlock() }; return timedOut }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("model") private var modelName = ""
    @AppStorage("valeAppearance") private var appearance = "system"
    @State private var connection = ""
    @State private var signInToken = UUID()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Settings").font(.system(size: 26, weight: .regular)).tracking(-0.5)
                VStack(alignment: .leading, spacing: 12) {
                    Text("ChatGPT via Codex").font(.system(size: 16, weight: .medium))
                    Text(connection.isEmpty ? (model.provider.executable == nil ? "Codex wasn’t found in ~/.local/bin, Homebrew, the app bundle, or your PATH." : "Uses the sign-in saved by your Codex CLI.") : connection).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Button("Check connection") { checkConnection() }.buttonStyle(QuietButton())
                    Text("To sign in, run codex login in Terminal.").font(.system(size: 11)).foregroundStyle(Theme.muted).textSelection(.enabled)
                }
                Divider().overlay(Theme.line)
                UpdateSettingsView(updates: model.updates)
                Divider().overlay(Theme.line)
                Toggle("Read typed replies aloud", isOn: $model.readAloud).toggleStyle(.switch).font(.system(size: 13))
                Text("The microphone starts when you choose Talk or Conversation. Conversation listens again after each answer; Pause or Escape stops it. Apple’s on-device speech recognition is used when available.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                VoiceSettings()
                Divider().overlay(Theme.line)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your context, your choice").font(.system(size: 16, weight: .medium))
                    Text("Your messages, uploaded files, and the window you explicitly share are sent when you ask. Live refresh keeps only the latest selected-window preview in memory, every two seconds. Images are sent when you ask, not on every refresh. A selected window includes whichever page is visible inside it.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                    Text("Chats and uploaded files are retained locally. Forget removes a chat and its files. Captured screens and microphone recordings are not saved to chat history.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                }
                Divider().overlay(Theme.line)
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Codex executable").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        TextField("Auto-detect", text: $codexPath).font(.system(size: 12)).modifier(QuietField())
                        Text("Model").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        TextField("Codex default", text: $modelName).font(.system(size: 12)).modifier(QuietField())
                    }.padding(.top, 15)
                }.font(.system(size: 12))
                Picker("Appearance", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.font(.system(size: 13))
                Text("Open Vale anywhere: Control–Option–Space").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text("Vale\((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { " \($0)" } ?? "") · Your companion, wherever you work").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }.padding(32).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
        }.scrollIndicators(.automatic).background(Theme.background)
    }
    func checkConnection() {
        guard let path = model.provider.executable else { connection = "Codex wasn’t found. Choose its path below."; return }
        connection = "Checking…"
        let token = UUID(); signInToken = token
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = ["login", "status"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        let wait = SignInWait()
        process.terminationHandler = { process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); let text = String(data: data, encoding: .utf8) ?? ""
            let message = SignInCheck.result(status: process.terminationStatus, output: text, timedOut: wait.didTimeOut())
            DispatchQueue.main.async { if signInToken == token { connection = message } }
        }
        do { try process.run() } catch { connection = "Couldn’t launch Codex. Check the executable path."; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + SignInCheck.limit) {
            guard signInToken == token, process.isRunning else { return }
            wait.markTimedOut()
            connection = SignInCheck.result(status: 0, output: "", timedOut: true)
            process.terminate()
        }
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var updates: UpdateController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Updates").font(.system(size: 16, weight: .medium))
                Spacer()
                Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Text(updates.status).font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Toggle("Automatically check for updates", isOn: Binding(get: { updates.automaticallyChecks }, set: { updates.setAutomaticChecks($0) })).toggleStyle(.switch).disabled(!updates.isConfigured)
            Toggle("Download updates automatically", isOn: Binding(get: { updates.automaticallyDownloads }, set: { updates.setAutomaticDownloads($0) })).toggleStyle(.switch).disabled(!updates.isConfigured)
            Text("Installation and restart stay under your control.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            if let date = updates.lastCheckDate { Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 12)).foregroundStyle(Theme.muted) }
            Button("Check for Updates…") { updates.check() }.buttonStyle(QuietButton()).disabled(!updates.canCheck)
        }.font(.system(size: 13)).accessibilityElement(children: .contain)
    }
}
