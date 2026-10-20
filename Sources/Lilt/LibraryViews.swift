import SwiftUI
import LiltCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("valeAppearance") private var appearance = "system"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Settings").font(.system(size: 26, weight: .regular)).tracking(-0.5)
                ChatGPTAccountSettings(account: model.provider.account)
                Divider().overlay(Theme.line)
                UpdateSettingsView(updates: model.updates)
                Divider().overlay(Theme.line)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Read typed replies aloud", isOn: $model.readAloud).toggleStyle(.switch).font(.system(size: 13))
                    Text("The microphone starts when you choose Talk or Conversation. Conversation listens again after each answer; Pause or Escape stops it. Apple’s on-device speech recognition is used when available.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                    VoiceSettings()
                }
                Divider().overlay(Theme.line)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your context, your choice").font(.system(size: 16, weight: .medium))
                    Text("Your messages, uploaded files, and the window you explicitly share are sent when you ask. Live refresh keeps only the latest selected-window preview in memory, every two seconds. Images are sent when you ask, not on every refresh. A selected window includes whichever page is visible inside it.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                    Text("Chats and uploaded files are retained locally. Forget removes a chat and its files. Captured screens and microphone recordings are not saved to chat history.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                }
                Divider().overlay(Theme.line)
                Picker("Appearance", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.font(.system(size: 13))
                Text("Open Vale anywhere: Control–Option–Space").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text("Vale\((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { " \($0)" } ?? "") · Your companion, wherever you work").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }.padding(32).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
        }.scrollIndicators(.automatic).background(Theme.background)
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
            Toggle("Download updates automatically", isOn: Binding(get: { updates.automaticallyDownloads }, set: { updates.setAutomaticDownloads($0) })).toggleStyle(.switch).disabled(!updates.isConfigured || !updates.automaticallyChecks)
            Text(updates.isConfigured && !updates.automaticallyChecks ? "Enable automatic checks to change automatic downloads." : "Downloaded updates normally install when Vale quits.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            if let date = updates.lastCheckDate { Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 12)).foregroundStyle(Theme.muted) }
            Button("Check for Updates…") { updates.check() }.buttonStyle(QuietButton()).disabled(!updates.canCheck)
        }.font(.system(size: 13)).accessibilityElement(children: .contain)
    }
}
