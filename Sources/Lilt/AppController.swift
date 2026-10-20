import AppKit
import SwiftUI
import Carbon
import LiltCore

@MainActor final class AppController: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate {
    enum CompanionCommand: UInt32, CaseIterable {
        case toggleVisibility = 1
        case toggleDictation = 2
    }
    var model: AppModel!
    var workspace: NSWindow!
    var statusItem: NSStatusItem!
    var annotation: NSWindow?
    private var annotationTimer: Timer?
    private var hotKeys: [CompanionCommand: EventHotKeyRef] = [:]
    private var hotHandler: EventHandlerRef?
    private var monitor: Any?
    private var statusMenu: NSMenu?
    private var showingStatusMenu = false
    private var testing = false
    private var workspaceToolbar: NativeWorkspaceToolbar?
    private var previousApplication: NSRunningApplication?
    private var preparingInputRoute = false
    private var presentingInitially = false
    /// AppKit can dispatch menu key equivalents even when a local monitor yields
    /// to a sheet. Share this boundary with validation, actions and focus retries.
    private var nativeDialogOpen: Bool {
        workspace?.attachedSheet != nil || NSApp.modalWindow != nil || NSApp.keyWindow?.isSheet == true ||
        NSApp.windows.contains { $0.isVisible && ($0.isSheet || $0.attachedSheet != nil) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let releaseCheck = ReleaseFeedAcceptanceContext.read()
        if CommandLine.arguments.contains("--verify-release-feed"), releaseCheck == nil { exit(2) }
        testing = CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") || releaseCheck != nil
        let directory = testing ? URL(fileURLWithPath: CommandLine.arguments.last!).appendingPathComponent("test-library") : nil
        model = AppModel(dataDirectory: directory)
        setupWorkspace(); setupMenu()
        if !testing { registerHotKeys() }
        model.showWorkspace = { [weak self] in self?.openWorkspace() }
        model.requestCompanionEscape = { [weak self] in self?.handleCompanionEscape() }
        model.hideOverlay = { [weak self] in self?.clearAnnotation() }
        model.showPoint = { [weak self] point, snapshot in self?.point(point, snapshot: snapshot) }
        model.contextReset = { [weak self] in
            guard let self else { return }
            self.model.contextPreview = nil
            if self.model.inspector == .context { self.model.closeInspector() }
        }
        model.filesRemoved = { [weak self] ids in
            guard let self, case .file(let id) = self.model.inspector, ids.contains(id) else { return }
            self.model.closeInspector()
        }
        model.showPreview = { [weak self] image in self?.model.contextPreview = image; self?.model.showInspector(.context) }
        model.showFile = { [weak self] record in self?.model.showInspector(.file(record.id)) }
        model.closePreview = { [weak self] in
            self?.model.contextPreview = nil
            if self?.model.inspector == .context { self?.model.closeInspector() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let dialog = self.nativeDialogOpen
            if event.keyCode == 53 {
                if EscapeKey.stopsSession(dialogOpen: dialog) { self.handleCompanionEscape(); return nil }
            }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            if dialog {
                if modifiers == .command, let key = event.charactersIgnoringModifiers, ["n", ","].contains(key) { return nil }
                return event
            }
            if modifiers == .command {
                switch event.charactersIgnoringModifiers {
                case ",": self.model.openSettings(); return nil
                case "n": self.model.newSession(); return nil
                default: break
                }
            }
            return event
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemSuspend), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemSuspend), name: NSWorkspace.screensDidSleepNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(systemSuspend), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        if let releaseCheck { Task { await runReleaseFeedAcceptance(releaseCheck) } }
        else if testing { Task { await runHarness() } }
        else { presentInitially() }
    }

    private func setupWorkspace() {
        let window = NativeWorkspaceWindow(model: model, rememberFrame: !testing)
        workspace = window; workspace.delegate = self; workspaceToolbar = window.chrome
        if !testing { bringWorkspaceOnScreen() }
    }
    private func bringWorkspaceOnScreen() {
        guard let panel = workspace as? NativeWorkspaceWindow else { return }
        let screens = NSScreen.screens
        let onScreen = screens.contains { $0.visibleFrame.intersects(panel.frame) }
        if !onScreen { panel.summon() }
        else { panel.applyCompanionLayout(animated: false) }
    }
    /// Automatic launch presents/focuses Ready while preparing identity only.
    /// Selection enters RAM on an explicit summon or question, never startup.
    func presentInitially() {
        presentingInitially = true
        defer { presentingInitially = false }
        model.prepareChat()
        openWorkspace()
    }
    func openWorkspace() {
        guard !nativeDialogOpen, !preparingInputRoute else { return }
        let screen = workspace.isVisible ? workspace.screen : pointerScreen
        model.workContext.prepareInvocation(screen: screen, readSelectedText: !presentingInitially)
        rememberPreviousApplication()
        if !workspace.isVisible { (workspace as? NativeWorkspaceWindow)?.summon(on: screen) }
        finishOpeningWorkspace()
    }
    /// Carbon and menu actions share one dispatcher. The global shortcuts have
    /// no local key-equivalent handler, so one key press executes one command.
    func performCompanionCommand(_ command: CompanionCommand) {
        guard canPerformCompanionCommand(command) else { return }
        switch command {
        case .toggleVisibility:
            if workspace.isVisible && workspace.isKeyWindow && NSApp.isActive { dismissCompanion() }
            else { showCompanionForInput() }
        case .toggleDictation:
            if !workspace.isVisible || !workspace.isKeyWindow || !NSApp.isActive || !model.chatSurfaceVisible {
                showCompanionForInput()
            } else if composerMayReceiveFocus {
                focusComposer(attemptsLeft: ComposerFocus.attempts)
            }
            model.commitComposer?()
            model.expandCompanion()
            model.toggleVoice()
        }
    }
    func canPerformCompanionCommand(_ command: CompanionCommand) -> Bool {
        guard !nativeDialogOpen else { return false }
        switch command {
        case .toggleVisibility: return true
        case .toggleDictation:
            return model.active != nil && !model.paused && model.provider.account.permitsPlanUsage
        }
    }
    private var pointerScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }
    private func showCompanionForInput() {
        let screen = pointerScreen
        // Sample the other app before either AppKit activation or route-driven
        // focus can transfer the foreground application to Vale.
        model.workContext.prepareInvocation(screen: screen)
        rememberPreviousApplication()
        if !model.chatSurfaceVisible {
            model.commitComposer?()
            preparingInputRoute = true
            model.backToChat()
            preparingInputRoute = false
        }
        (workspace as? NativeWorkspaceWindow)?.summon(on: screen)
        finishOpeningWorkspace()
    }
    private func finishOpeningWorkspace() {
        bringWorkspaceOnScreen(); model.workspaceOpen = true
        if workspace.isMiniaturized { workspace.deminiaturize(nil) }
        workspace.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if composerMayReceiveFocus { focusComposer(attemptsLeft: ComposerFocus.attempts) }
        else { workspace.makeFirstResponder(nil) }
    }
    private func rememberPreviousApplication() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if previousApplication?.isTerminated == true || previousApplication?.processIdentifier == ownPID { previousApplication = nil }
        guard let frontmost = NSWorkspace.shared.frontmostApplication, !frontmost.isTerminated,
              frontmost.processIdentifier != ownPID else { return }
        previousApplication = frontmost
    }
    private func restorePreviousApplication() {
        guard let application = previousApplication, !application.isTerminated,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            previousApplication = nil; return
        }
        application.activate(options: [])
    }
    func handleCompanionEscape() {
        guard !nativeDialogOpen else { return }
        model.commitComposer?()
        if model.busy || model.voice.starting || model.voice.listening || model.voice.speaking || model.conversation || model.context.hasSelection {
            model.stopInteraction(); clearAnnotation(); return
        }
        if !model.chatSurfaceVisible { model.backToChat(); return }
        if model.companionExpanded { model.collapseCompanion(); restorePreviousApplication(); return }
        dismissCompanion()
    }
    private func dismissCompanion() {
        model.commitComposer?(); model.companionDidHide(); model.persist(); model.workspaceOpen = false
        clearAnnotation()
        workspace.orderOut(nil)
        restorePreviousApplication()
    }
    private var composerMayReceiveFocus: Bool {
        !nativeDialogOpen && workspace.isVisible && !workspace.isMiniaturized && model.chatSurfaceVisible
    }
    private func focusComposer(attemptsLeft: Int) {
        guard composerMayReceiveFocus, let root = workspace.contentView else { return }
        func editor(_ view: NSView) -> NSView? {
            if view.identifier?.rawValue == "lilt.composer" { return view }
            return view.subviews.lazy.compactMap { editor($0) }.first
        }
        if let input = editor(root) { workspace.makeFirstResponder(input); return }
        guard ComposerFocus.shouldRetry(found: false, attemptsLeft: attemptsLeft) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.focusComposer(attemptsLeft: attemptsLeft - 1) }
    }
    private func setupMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(title: "Vale"); appItem.submenu = appMenu
        let settings = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ","); settings.target = self; appMenu.addItem(settings)
        let updates=NSMenuItem(title:"Check for Updates…",action:#selector(menuUpdates),keyEquivalent:""); updates.target=self; appMenu.addItem(updates)
        appMenu.addItem(.separator())
        let appQuit = NSMenuItem(title: "Quit Vale", action: #selector(menuQuit), keyEquivalent: "q"); appQuit.target = self; appMenu.addItem(appQuit)
        let fileItem = NSMenuItem(); main.addItem(fileItem); let fileMenu = NSMenu(title: "File"); fileItem.submenu = fileMenu
        let newItem = NSMenuItem(title: "New chat", action: #selector(menuNew), keyEquivalent: "n"); newItem.target = self; fileMenu.addItem(newItem)
        // Carbon owns these key presses globally. Text legends make the same
        // shortcuts discoverable without adding a second menu key handler.
        let showItem = NSMenuItem(title: "Show or Hide Vale  ⌃⌥Space", action: #selector(menuWorkspace), keyEquivalent: ""); showItem.target = self; fileMenu.addItem(showItem)
        let dictateItem = NSMenuItem(title: "Dictate a Question  ⌃⌥D", action: #selector(menuDictation), keyEquivalent: ""); dictateItem.target = self; fileMenu.addItem(dictateItem)
        fileMenu.addItem(.separator())
        let attachItem = NSMenuItem(title: "Attach files…", action: #selector(menuAttach), keyEquivalent: "a"); attachItem.keyEquivalentModifierMask = [.command, .shift]; attachItem.target = self; fileMenu.addItem(attachItem)
        let shareItem = NSMenuItem(title: "Share a window…", action: #selector(menuShareWindow), keyEquivalent: "s"); shareItem.keyEquivalentModifierMask = [.command, .shift]; shareItem.target = self; fileMenu.addItem(shareItem)
        fileMenu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Close window", action: #selector(menuClose), keyEquivalent: "w"); closeItem.target = self; fileMenu.addItem(closeItem)
        let editItem = NSMenuItem(); main.addItem(editItem); let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        editMenu.addItem(.separator())
        let findItem = NSMenuItem(title: "Find in chats", action: #selector(menuLibrary), keyEquivalent: "f"); findItem.target = self; editMenu.addItem(findItem)
        let viewItem = NSMenuItem(); main.addItem(viewItem); let viewMenu = NSMenu(title: "View"); viewItem.submenu = viewMenu
        let sidebarItem = NSMenuItem(title: "Chat history", action: #selector(menuSidebar), keyEquivalent: "s"); sidebarItem.keyEquivalentModifierMask = [.command, .control]; sidebarItem.target = self; viewMenu.addItem(sidebarItem)
        let detailsItem = NSMenuItem(title: "Show files and notes", action: #selector(menuDetails), keyEquivalent: "i"); detailsItem.keyEquivalentModifierMask = [.command, .option]; detailsItem.target = self; viewMenu.addItem(detailsItem)
        viewMenu.addItem(.separator())
        let backItem = NSMenuItem(title: "Back to chat", action: #selector(menuBack), keyEquivalent: "["); backItem.target = self; viewMenu.addItem(backItem)
        let chatItem = NSMenuItem(); main.addItem(chatItem); chatItem.submenu = workspaceToolbar?.chatMenu()
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Vale")
        statusItem.button?.toolTip = "Show or hide Vale · Control–Option–Space\nDictate a question · Control–Option–D"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let menu = NSMenu()
        for (title, action) in [("Show or Hide Vale  ⌃⌥Space", #selector(menuWorkspace)), ("Dictate a Question  ⌃⌥D", #selector(menuDictation)), ("Chat history", #selector(menuLibrary)), ("Pause chat", #selector(menuPause)), ("Settings…", #selector(menuSettings))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator()); let quit = NSMenuItem(title: "Quit Vale", action: #selector(menuQuit), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        statusMenu = menu
    }
    private func registerHotKeys() {
        guard hotHandler == nil, hotKeys.isEmpty else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handler: EventHandlerUPP = { _, event, data in
            guard let event, let data else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID(signature: 0, id: 0)
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x4C696C74,
                  identifier.id == 1 || identifier.id == 2 else { return OSStatus(eventNotHandledErr) }
            let commandID = identifier.id
            let controller = Unmanaged<AppController>.fromOpaque(data).takeUnretainedValue()
            DispatchQueue.main.async { [weak controller] in
                guard let command = CompanionCommand(rawValue: commandID) else { return }
                controller?.performCompanionCommand(command)
            }
            return noErr
        }
        let installed = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &event, pointer, &hotHandler)
        guard installed == noErr else {
            hotHandler = nil
            model.shortcutWarning = "Global shortcuts are unavailable. Use Vale’s menu bar commands."
            return
        }
        var warnings: [String] = []
        for command in CompanionCommand.allCases {
            var reference: EventHotKeyRef?
            let key = command == .toggleVisibility ? kVK_Space : kVK_ANSI_D
            let identifier = EventHotKeyID(signature: 0x4C696C74, id: command.rawValue)
            let status = RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey), identifier, GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { hotKeys[command] = reference }
            else if command == .toggleVisibility {
                warnings.append("Control–Option–Space is unavailable. Show Vale from the menu bar.")
            } else {
                warnings.append("Control–Option–D is unavailable. Use Dictate a Question in the File menu.")
            }
        }
        model.shortcutWarning = warnings.isEmpty ? nil : warnings.joined(separator: " ")
    }
    private func unregisterHotKeys() {
        for reference in hotKeys.values { UnregisterEventHotKey(reference) }
        hotKeys.removeAll()
        if let hotHandler { RemoveEventHandler(hotHandler); self.hotHandler = nil }
    }
    func point(_ point: PointTarget, snapshot: ContextSnapshot) {
        clearAnnotation()
        guard point.isValid, let bounds = snapshot.frame, snapshot.generation == model.context.generation,model.context.pointIsVisible(point,frame:bounds,windowID:snapshot.windowID) else { return }
        let frames=NSScreen.screens.map{DisplayFrame(x:$0.frame.origin.x,y:$0.frame.origin.y,width:$0.frame.width,height:$0.frame.height)}
        let primaryHeight=HighlightPlacement.primaryHeight(frames) ?? NSScreen.screens.first?.frame.height ?? 900
        let itemTop=bounds.minY+CGFloat(point.y)*bounds.height
        let itemHeight=CGFloat(point.height)*bounds.height
        let frame = NSRect(x: bounds.minX + CGFloat(point.x) * bounds.width - 6, y: HighlightPlacement.appKitOriginY(cgMinY:itemTop,cgHeight:itemHeight,primaryHeight:primaryHeight) - 6, width: CGFloat(point.width) * bounds.width + 12, height: CGFloat(point.height) * bounds.height + 12)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false; window.ignoresMouseEvents = true; window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RoundedRectangle(cornerRadius: 7).stroke(Theme.accent, lineWidth: 2).padding(4).background(Theme.accent.opacity(0.06)).accessibilityLabel(point.label))
        annotation = window; window.orderFrontRegardless()
        let created = Date(); let expectedGeneration = snapshot.generation; let expectedFrame = snapshot.frame
        var checkingFrame = false
        annotationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Date().timeIntervalSince(created) > 5 || self.model.context.generation != expectedGeneration || self.model.context.currentFrame() != expectedFrame || !self.model.context.pointIsVisible(point,frame:bounds,windowID:snapshot.windowID,ignoring:CGWindowID(window.windowNumber)) { self.clearAnnotation(); return }
                if !checkingFrame {
                    checkingFrame = true
                    Task { [weak self, weak window] in
                        defer { checkingFrame = false }
                        guard let self, let window, self.annotation === window else { return }
                        let fresh = try? await self.model.context.capture()
                        guard self.annotation === window else { return }
                        let unchanged = fresh.map { snapshot.evidence.reflectsSameView($0.evidence) } ?? false
                        let visible = self.model.context.pointIsVisible(point, frame: bounds, windowID: snapshot.windowID, ignoring: CGWindowID(window.windowNumber))
                        if PointHighlight.shouldClear(windowUnchanged: unchanged, visible: visible) { self.clearAnnotation() }
                    }
                }
            }
        }
    }
    func clearAnnotation() { annotationTimer?.invalidate(); annotationTimer = nil; annotation?.orderOut(nil); annotation = nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === workspace {
            guard !nativeDialogOpen else { return false }
            dismissCompanion()
            return false
        }
        return true
    }
    @objc func systemSuspend() { model.suspend() }
    @objc private func menuClose() { guard !nativeDialogOpen else { return }; if NSApp.keyWindow === workspace { dismissCompanion() } else { NSApp.keyWindow?.performClose(nil) } }
    @objc private func menuNew() { guard !nativeDialogOpen else { return }; model.newSession() }
    @objc private func menuUpdates() { guard !nativeDialogOpen, model.updates.canCheck else { return }; model.updates.check() }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let guardedActions = [#selector(menuNew), #selector(menuSettings), #selector(menuLibrary), #selector(menuPause), #selector(menuUpdates), #selector(menuWorkspace), #selector(menuDictation), #selector(menuClose), #selector(menuAttach), #selector(menuShareWindow), #selector(menuSidebar), #selector(menuDetails), #selector(menuBack)]
        if nativeDialogOpen, let action = item.action, guardedActions.contains(action) { return false }
        if item.action == #selector(menuWorkspace) {
            let title = !workspace.isVisible ? "Show Vale" : workspace.isKeyWindow && NSApp.isActive ? "Hide Vale" : "Focus Vale"
            item.title = title + "  ⌃⌥Space"
            return canPerformCompanionCommand(.toggleVisibility)
        }
        if item.action == #selector(menuDictation) {
            item.title = (model.voice.listening ? "Finish Speaking and Send" : model.voice.starting || model.voice.speaking ? "Stop Voice" : "Dictate a Question") + "  ⌃⌥D"
            return canPerformCompanionCommand(.toggleDictation)
        }
        if item.action == #selector(menuUpdates) { return model.updates.canCheck }
        if item.action == #selector(menuPause) { item.title = model.paused && model.active != nil ? "Resume" : "Pause chat"; return model.active != nil }
        if item.action == #selector(menuAttach) { return model.active != nil && !model.importing }
        if item.action == #selector(menuShareWindow) { return model.active != nil && !model.paused }
        if item.action == #selector(menuDetails) { return model.active != nil }
        if item.action == #selector(menuBack) { return model.workspaceRoute != .chat || model.inspector != nil || model.compactHistoryVisible }
        return true
    }
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if (event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true), !showingStatusMenu, let menu = statusMenu, let button = statusItem.button {
            showingStatusMenu = true; statusItem.menu = menu; button.performClick(nil); statusItem.menu = nil; showingStatusMenu = false; return
        }
        if !showingStatusMenu { performCompanionCommand(.toggleVisibility) }
    }
    @objc private func menuWorkspace() { performCompanionCommand(.toggleVisibility) }
    @objc private func menuDictation() { performCompanionCommand(.toggleDictation) }
    @objc private func menuLibrary() { guard !nativeDialogOpen else { return }; model.showHistory() }
    @objc private func menuAttach() { guard !nativeDialogOpen, model.active != nil, !model.importing else { return }; model.attachFiles() }
    @objc private func menuShareWindow() {
        guard !nativeDialogOpen, model.active != nil, !model.paused else { return }
        model.commitComposer?()
        model.context.choose()
    }
    @objc private func menuSidebar() { guard !nativeDialogOpen else { return }; workspaceToolbar?.toggleSidebar() }
    @objc private func menuDetails() { guard !nativeDialogOpen, model.active != nil else { return }; workspaceToolbar?.toggleDetails() }
    @objc private func menuBack() { guard !nativeDialogOpen else { return }; model.backToChat() }
    @objc private func menuPause() { guard !nativeDialogOpen, model.active != nil else { return }; model.togglePause() }
    @objc private func menuSettings() { guard !nativeDialogOpen else { return }; model.openSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openWorkspace(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        model.commitComposer?(); model.suspend()
        unregisterHotKeys()
        if let monitor { NSEvent.removeMonitor(monitor) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
    deinit {
        for reference in hotKeys.values { UnregisterEventHotKey(reference) }
        if let hotHandler { RemoveEventHandler(hotHandler) }
    }
}
