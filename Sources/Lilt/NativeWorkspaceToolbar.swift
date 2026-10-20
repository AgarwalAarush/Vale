import AppKit
import Combine
import LiltCore

/// Retains the native app/menu commands without attaching workspace chrome.
/// The companion exposes these same actions from its compact overflow.
@MainActor final class NativeWorkspaceToolbar: NSObject, NSMenuDelegate, NSUserInterfaceValidations {
    static let command = Notification.Name("ValeWorkspaceCommand")
    private weak var window: NSWindow?
    private let model: AppModel
    private var observations: [AnyCancellable] = []
    init(window: NSWindow, model: AppModel) {
        self.window = window; self.model = model
        super.init()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).sink { [weak self] _ in self?.refresh() }.store(in: &observations)
        refresh()
    }
    private var hasActivity: Bool { model.busy || model.context.hasSelection || model.voice.starting || model.voice.listening || model.voice.speaking || model.conversation }
    private var dialogOpen: Bool { window?.attachedSheet != nil || NSApp.modalWindow != nil || NSApp.windows.contains { $0.isVisible && ($0.isSheet || $0.attachedSheet != nil) } }
    private func refresh() {
        let appearance = UserDefaults.standard.string(forKey: "valeAppearance") ?? "system"
        window?.appearance = appearance == "light" ? NSAppearance(named: .aqua) : appearance == "dark" ? NSAppearance(named: .darkAqua) : nil
        window?.setAccessibilityTitle("Vale companion")
    }
    func toggleSidebar() {
        guard !dialogOpen else { return }
        if model.compactHistoryVisible { model.backToChat() } else { model.showHistory() }
    }
    func toggleDetails() {
        guard !dialogOpen, model.active != nil else { return }
        if model.inspector == nil { model.showInspector(.notes) } else { model.backToChat() }
    }
    func chatMenu() -> NSMenu { makeMenu(title: "Chat") }
    private func makeMenu(title: String) -> NSMenu {
        let menu = NSMenu(title: title); menu.delegate = self; populate(menu); return menu
    }
    func menuNeedsUpdate(_ menu: NSMenu) { populate(menu) }
    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu.title == "Chat mode" {
            add("Assistant", command: "assistant", to: menu, checked: model.active?.mode == .assistant)
            add("Learn with hints", command: "learn", to: menu, checked: model.active?.mode == .learn)
            return
        }
        add("Notes", command: "notes", to: menu); add("Files", command: "files", to: menu)
        menu.addItem(.separator())
        let mode = NSMenuItem(title: "Chat mode", action: nil, keyEquivalent: ""); mode.submenu = makeMenu(title: "Chat mode"); menu.addItem(mode)
        add("Read typed replies aloud", command: "readAloud", to: menu, checked: model.readAloud)
        if model.active?.mode == .learn {
            add("Start step-by-step guide…", command: "guide", to: menu)
            add("Show full walkthrough…", command: "walkthrough", to: menu)
        }
        let timer = NSMenuItem(title: "Focus timer", action: nil, keyEquivalent: ""); let choices = NSMenu(title: "Focus timer")
        for (title, value) in [("30 minutes", "timer30"), ("60 minutes", "timer60"), ("No timer", "timer0")] { add(title, command: value, to: choices) }
        timer.submenu = choices; menu.addItem(timer)
        if let chat = model.active, chat.duration > 0 {
            let remaining = NSMenuItem(title: "\(chat.timerText) remaining", action: nil, keyEquivalent: ""); remaining.isEnabled = false; menu.addItem(remaining)
        }
        menu.addItem(.separator())
        add("Rename chat…", command: "rename", to: menu); add("Export chat…", command: "export", to: menu)
        add("Forget chat…", command: "forget", to: menu)
        menu.addItem(.separator())
        add(model.paused ? "Resume chat" : "Pause chat", command: "pause", to: menu)
        add("Close chat", command: "close", to: menu)
        add("Stop response, voice and sharing", command: "stop", to: menu)
    }
    private func add(_ title: String, command: String, to menu: NSMenu, checked: Bool = false) {
        let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = command; item.state = checked ? .on : .off; menu.addItem(item)
    }
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard !dialogOpen else { return false }
        guard let menuItem = item as? NSMenuItem, let command = menuItem.representedObject as? String else { return true }
        if command == "stop" { return hasActivity }
        guard let chat = model.active else { return false }
        if command == "guide" { return !model.busy && !model.paused && model.provider.account.permitsPlanUsage }
        if command == "walkthrough" { return !chat.messages.isEmpty && !model.busy && !model.paused && model.provider.account.permitsPlanUsage }
        return true
    }
    @objc private func run(_ sender: NSMenuItem) {
        guard !dialogOpen, let command = sender.representedObject as? String else { return }
        switch command {
        case "notes": model.showInspector(.notes)
        case "files": model.showInspector(.files)
        case "assistant": model.setMode(.assistant)
        case "learn": model.setMode(.learn)
        case "readAloud": model.readAloud.toggle()
        case "timer30": model.setFocus(minutes: 30)
        case "timer60": model.setFocus(minutes: 60)
        case "timer0": model.setFocus(minutes: 0)
        case "export": if let chat = model.active { model.export(chat) }
        case "pause": model.togglePause()
        case "close": model.complete()
        case "stop": model.stopInteraction()
        case "rename", "forget", "guide", "walkthrough":
            model.commitComposer?(); NotificationCenter.default.post(name: Self.command, object: model, userInfo: ["action": command])
        default: break
        }
    }
}
