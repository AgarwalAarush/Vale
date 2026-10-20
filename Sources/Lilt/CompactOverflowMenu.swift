import SwiftUI
import LiltCore

struct CompactOverflowMenu: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Menu {
            Button("New chat", systemImage: "square.and.pencil") { model.newSession(); model.expandCompanion() }
            Button("Chat history", systemImage: "clock.arrow.circlepath") { model.showHistory() }
            if model.active?.messages.isEmpty == false {
                Button(model.companionShowsEarlierMessages ? "Show latest reply" : "Show earlier messages", systemImage: "text.bubble") {
                    model.companionShowsEarlierMessages.toggle(); model.expandCompanion()
                }
            }
            Divider()
            Menu("Chat mode") {
                Button { model.setMode(.assistant) } label: { Label("Assistant", systemImage: model.active?.mode == .assistant ? "checkmark" : "bubble.left") }
                Button { model.setMode(.learn); model.expandCompanion() } label: { Label("Learn with hints", systemImage: model.active?.mode == .learn ? "checkmark" : "lightbulb") }
            }
            if model.active?.mode == .learn {
                Button("Start step-by-step guide…") { command("guide") }.disabled(model.busy || model.paused || !model.provider.account.permitsPlanUsage)
                Button("Show full walkthrough…") { command("walkthrough") }.disabled(model.busy || model.paused || !model.provider.account.permitsPlanUsage)
            }
            Button("Notes", systemImage: "note.text") { model.showInspector(.notes) }
            Button("Files", systemImage: "paperclip") { model.showInspector(.files) }
            Toggle("Web search", isOn: Binding(get: { model.active?.webEnabled == true }, set: { model.setWeb($0) })).disabled(!WebToggle.changes(waiting: model.busy))
            Divider()
            Button("Talk", systemImage: "mic") { model.expandCompanion(); model.toggleVoice() }.disabled(model.paused || !model.provider.account.permitsPlanUsage)
            Toggle("Conversation", isOn: Binding(get: { model.conversation }, set: { model.expandCompanion(); model.setConversation($0) })).disabled(model.paused || !model.provider.account.permitsPlanUsage)
            Toggle("Read typed replies aloud", isOn: $model.readAloud)
            Menu("Focus timer") {
                Button("30 minutes") { model.setFocus(minutes: 30) }
                Button("60 minutes") { model.setFocus(minutes: 60) }
                Button("No timer") { model.setFocus(minutes: 0) }
                if let chat = model.active, chat.duration > 0 { Text("\(chat.timerText) remaining") }
            }
            Divider()
            Button("Rename chat…") { command("rename") }
            Button("Export chat…") { if let chat = model.active { model.export(chat) } }
            Button("Forget chat…", role: .destructive) { command("forget") }
            Button(model.paused ? "Resume chat" : "Pause chat") { model.togglePause() }
            Button("Close chat") { model.complete() }
            Divider()
            Button("Settings…", systemImage: "gearshape") { model.openSettings() }
            Button("Check for Updates…") { model.updates.check() }.disabled(!model.updates.canCheck)
        } label: {
            Label("More", systemImage: "ellipsis").labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium)).frame(width: 25, height: 28)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("More Vale actions").help("History, Learn, voice, files and settings")
    }
    private func command(_ action: String) {
        model.commitComposer?()
        NotificationCenter.default.post(name: NativeWorkspaceToolbar.command, object: model, userInfo: ["action": action])
    }
}
