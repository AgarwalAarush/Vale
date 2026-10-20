import AppKit
import Combine
import LiltCore

/// AppKit owns the window chrome, item sizing, overflow and menu tracking.
/// Content never supplies a second toolbar or reserves titlebar space.
@MainActor final class NativeWorkspaceToolbar: NSObject, NSToolbarDelegate, NSMenuDelegate, NSUserInterfaceValidations {
    static let command = Notification.Name("ValeWorkspaceCommand")
    private enum Item {
        static let sidebar = NSToolbarItem.Identifier("vale.sidebar")
        static let newChat = NSToolbarItem.Identifier("vale.newChat")
        static let mode = NSToolbarItem.Identifier("vale.mode")
        static let details = NSToolbarItem.Identifier("vale.details")
        static let actions = NSToolbarItem.Identifier("vale.actions")
        static let stop = NSToolbarItem.Identifier("vale.stop")
        static let back = NSToolbarItem.Identifier("vale.back")
    }
    private weak var window: NSWindow?
    private let model: AppModel
    private let toolbar = NSToolbar(identifier: "vale.workspace.toolbar")
    private var observations: [AnyCancellable] = []
    private var refreshQueued = false
    private var lastAppliedAppearance: String?

    init(window: NSWindow, model: AppModel) {
        self.window = window; self.model = model
        super.init()
        toolbar.delegate = self; toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false; toolbar.autosavesConfiguration = false
        toolbar.allowsExtensionItems = false
        window.toolbarStyle = .unifiedCompact; window.toolbar = toolbar
        model.objectWillChange.sink { [weak self] in self?.queueRefresh() }.store(in: &observations)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).sink { [weak self] _ in self?.queueRefresh() }.store(in: &observations)
        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: window).sink { [weak self] _ in self?.queueRefresh() }.store(in: &observations)
        refresh()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.sidebar, Item.newChat, .flexibleSpace, Item.mode, Item.details, Item.actions]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [Item.stop, Item.back]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Item.sidebar: return button(identifier, label: "Chat history", symbol: "sidebar.left", action: #selector(sidebarAction))
        case Item.newChat: return button(identifier, label: "New chat", symbol: "square.and.pencil", action: #selector(newAction))
        case Item.details: return button(identifier, label: "Files and notes", symbol: "sidebar.right", action: #selector(detailsAction))
        case Item.back:
            let item = button(identifier, label: "Back to chat", symbol: "chevron.left", action: #selector(backAction))
            item.isNavigational = true; item.visibilityPriority = .high; return item
        case Item.stop:
            let item = button(identifier, label: "Stop", symbol: "stop.fill", action: #selector(stopAction))
            item.title = "Stop"; item.visibilityPriority = .high; return item
        case Item.mode:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = "Chat mode"; item.paletteLabel = "Chat mode"; item.title = "Assistant"
            item.menu = makeMenu(title: "Chat mode"); item.toolTip = "Chat mode"; item.visibilityPriority = .low
            return item
        case Item.actions:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = "Chat actions"; item.paletteLabel = "Chat actions"
            item.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Chat actions")
            item.showsIndicator = false; item.menu = chatMenu(); item.toolTip = "Chat actions"
            return item
        default: return nil
        }
    }
    private func button(_ identifier: NSToolbarItem.Identifier, label: String, symbol: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label; item.paletteLabel = label; item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self; item.action = action
        return item
    }
    private func queueRefresh() {
        guard !refreshQueued else { return }; refreshQueued = true
        DispatchQueue.main.async { [weak self] in self?.refreshQueued = false; self?.refresh() }
    }
    private var hasActivity: Bool { model.busy || model.context.hasSelection || model.voice.starting || model.voice.listening || model.voice.speaking || model.conversation }
    private var dialogOpen: Bool { window?.attachedSheet != nil || NSApp.modalWindow != nil || NSApp.windows.contains { $0.isVisible && ($0.isSheet || $0.attachedSheet != nil) } }
    private func refresh() {
        guard let window else { return }
        window.title = model.workspaceRoute == .settings ? "Settings" : model.compactHistoryVisible && (window.contentView?.bounds.width ?? 0) < WorkspaceLayout.sidebarThreshold ? "Chat history" : model.active?.title ?? "Vale"
        window.setAccessibilityTitle("\(window.title) — Vale")
        let appearance = UserDefaults.standard.string(forKey: "valeAppearance") ?? "system"
        if lastAppliedAppearance != appearance {
            lastAppliedAppearance = appearance
            window.appearance = appearance == "light" ? NSAppearance(named: .aqua) : appearance == "dark" ? NSAppearance(named: .darkAqua) : nil
        }
        setPresent(Item.stop, hasActivity, at: toolbar.items.count)
        let layout = WorkspaceLayout(width: window.contentView?.bounds.width ?? 0, sidebarVisible: model.sidebarVisible, historyOverlay: model.compactHistoryVisible, inspectorOpen: model.inspector != nil)
        setPresent(Item.back, model.workspaceRoute != .chat || !layout.chatVisible, at: 1)
        for item in toolbar.items {
            if item.itemIdentifier == Item.mode {
                item.title = model.active?.mode == .learn ? "Learn" : "Assistant"
                item.isEnabled = model.active != nil && !dialogOpen
            } else if item.itemIdentifier == Item.details || item.itemIdentifier == Item.actions {
                item.isEnabled = model.active != nil && !dialogOpen
            } else if item.itemIdentifier == Item.stop {
                item.toolTip = "Stop response, voice and window sharing (Escape)"; item.isEnabled = !dialogOpen
            }
        }
    }
    private func setPresent(_ identifier: NSToolbarItem.Identifier, _ present: Bool, at index: Int) {
        if let current = toolbar.items.firstIndex(where: { $0.itemIdentifier == identifier }) {
            if !present { toolbar.removeItem(at: current) }
        } else if present { toolbar.insertItem(withItemIdentifier: identifier, at: min(index, toolbar.items.count)) }
    }
    func toggleSidebar() {
        guard !dialogOpen else { return }; model.commitComposer?()
        if (window?.contentView?.bounds.width ?? 0) < WorkspaceLayout.sidebarThreshold {
            if model.compactHistoryVisible { model.backToChat() } else { model.showHistory() }
        } else { model.compactHistoryVisible = false; model.sidebarVisible.toggle() }
    }
    func toggleDetails() {
        guard !dialogOpen, model.active != nil else { return }
        if model.inspector == nil { model.showInspector(.notes) } else { model.closeInspector() }
    }
    @objc private func sidebarAction() { toggleSidebar() }
    @objc private func detailsAction() { toggleDetails() }
    @objc private func newAction() { guard !dialogOpen else { return }; model.newSession() }
    @objc private func backAction() { guard !dialogOpen else { return }; model.backToChat() }
    @objc private func stopAction() { guard !dialogOpen else { return }; model.stopInteraction() }

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
