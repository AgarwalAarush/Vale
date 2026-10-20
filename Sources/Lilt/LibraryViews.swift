import SwiftUI
import LiltCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("valeAppearance") private var appearance = "system"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ChatGPTAccountSettings(account: model.provider.account)
                Divider()
                UpdateSettingsView(updates: model.updates)
                Divider()
                CurrentWorkContextSettings(context: model.workContext)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.pickerStyle(.segmented)
                    Toggle("Read typed replies aloud", isOn: $model.readAloud).toggleStyle(.switch)
                    VoiceSettings()
                    DisclosureGroup("Privacy") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("With Context on and access allowed, your current display and text selected in your working app are included when you ask. Vale is excluded from screenshots. Sharing a specific window replaces the display screenshot. Some apps don’t expose selected text.")
                            Text("Chats and attached files stay on this Mac. Forget removes a chat and its files. Automatic screen captures, selected text and microphone recordings aren’t saved to chat history. Live keeps one selected-window preview locally; refreshes aren’t sent until you ask.")
                            Text("Dictation (⌃⌥D) and Conversation start only when you choose them. Conversation listens again after each answer. Hide, Pause or Escape stops voice and local capture. On-device speech recognition is used when available.")
                        }.font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
                            .padding(.top, 8).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Vale " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                    Spacer(minLength: 8)
                    Text("⌃⌥Space show/hide · ⌃⌥D dictate")
                        .accessibilityLabel("Control–Option–Space to show or hide Vale. Control–Option–D to dictate.")
                }
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }.font(.system(size: 13)).controlSize(.small)
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.automatic).scrollContentBackground(.hidden)
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var updates: UpdateController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Updates").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Check now") { updates.check() }.buttonStyle(.bordered).controlSize(.small)
                    .disabled(!updates.canCheck).accessibilityLabel("Check for updates")
            }
            Toggle("Check automatically", isOn: Binding(get: { updates.automaticallyChecks }, set: { updates.setAutomaticChecks($0) }))
                .toggleStyle(.switch).disabled(!updates.isConfigured)
                .accessibilityLabel("Automatically check for updates")
            Toggle("Download automatically", isOn: Binding(get: { updates.automaticallyDownloads }, set: { updates.setAutomaticDownloads($0) }))
                .toggleStyle(.switch).disabled(!updates.isConfigured || !updates.automaticallyChecks)
                .accessibilityLabel("Download updates automatically")
                .help(updates.automaticallyChecks ? "Downloaded updates install when Vale quits." : "Enable automatic checks to change downloads.")
            Text(updates.status).font(.system(size: 12)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let date = updates.lastCheckDate {
                Text("Checked \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }.font(.system(size: 13)).controlSize(.small).accessibilityElement(children: .contain)
    }
}
