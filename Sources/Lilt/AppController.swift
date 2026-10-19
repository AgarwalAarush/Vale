import AppKit
import SwiftUI
import Carbon
import LiltCore

@MainActor final class AppController: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate {
    var model: AppModel!
    var workspace: NSWindow!
    var statusItem: NSStatusItem!
    var annotation: NSWindow?
    private var annotationTimer: Timer?
    private var hotKey: EventHotKeyRef?
    private var hotHandler: EventHandlerRef?
    private var monitor: Any?
    private var statusMenu: NSMenu?
    private var showingStatusMenu = false
    private var testing = false
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
        if !testing { registerHotKey() }
        model.showWorkspace = { [weak self] in self?.openWorkspace() }
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
                if EscapeKey.stopsSession(dialogOpen: dialog) { self.model.stopInteraction(); self.clearAnnotation(); return nil }
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
        else { model.prepareChat(); openWorkspace() }
    }

    private func setupWorkspace() {
        workspace = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        workspace.title = "Vale"; workspace.titleVisibility = .hidden; workspace.titlebarAppearsTransparent = true
        workspace.backgroundColor = Theme.windowBackground; workspace.isReleasedWhenClosed = false; workspace.delegate = self
        workspace.identifier = NSUserInterfaceItemIdentifier("vale.workspace")
        workspace.minSize = NSSize(width: 740, height: 560)
        let host = NSHostingView(rootView: WorkspaceView(model: model))
        host.sizingOptions = []; host.autoresizingMask = [.width, .height]
        workspace.contentView = host; workspace.setContentSize(NSSize(width: 1040, height: 740)); workspace.center()
        if !testing { workspace.setFrameAutosaveName("ValeWorkspace"); bringWorkspaceOnScreen() }
    }
    private func bringWorkspaceOnScreen() {
        let screens = NSScreen.screens.map { DisplayRect(x: $0.visibleFrame.minX, y: $0.visibleFrame.minY, width: $0.visibleFrame.width, height: $0.visibleFrame.height) }
        let frame = workspace.frame
        if !WindowPlacement.isVisible(DisplayRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height), on: screens) { workspace.center() }
        if let screen = workspace.screen ?? NSScreen.main, frame.width > screen.visibleFrame.width || frame.height > screen.visibleFrame.height {
            workspace.setFrame(screen.visibleFrame.insetBy(dx: 12, dy: 12), display: true)
        }
    }
    func openWorkspace() {
        guard !nativeDialogOpen else { return }
        bringWorkspaceOnScreen(); model.workspaceOpen = true
        workspace.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if composerMayReceiveFocus { focusComposer(attemptsLeft: ComposerFocus.attempts) }
        else { workspace.makeFirstResponder(nil) }
    }
    private var composerMayReceiveFocus: Bool {
        !nativeDialogOpen && workspace.isVisible && !workspace.isMiniaturized && model.workspaceRoute == .chat && model.inspector == nil &&
        (!model.compactHistoryVisible || (workspace.contentView?.bounds.width ?? 0) >= 860)
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
        let closeItem = NSMenuItem(title: "Close window", action: #selector(menuClose), keyEquivalent: "w"); closeItem.target = self; fileMenu.addItem(closeItem)
        let editItem = NSMenuItem(); main.addItem(editItem); let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Vale")
        statusItem.button?.toolTip = "Vale · open workspace · Control–Option–Space"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let menu = NSMenu()
        for (title, action) in [("Open Vale", #selector(menuWorkspace)), ("Chat history", #selector(menuLibrary)), ("Pause chat", #selector(menuPause)), ("Settings…", #selector(menuSettings))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator()); let quit = NSMenuItem(title: "Quit Vale", action: #selector(menuQuit), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        statusMenu = menu
    }
    private func registerHotKey() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handler: EventHandlerUPP = { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<AppController>.fromOpaque(data).takeUnretainedValue()
            DispatchQueue.main.async { controller.openWorkspace() }; return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &event, pointer, &hotHandler)
        let id = EventHotKeyID(signature: 0x4C696C74, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { model.shortcutWarning = "The shortcut is already in use. Open Vale from the menu bar." }
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
            model.commitComposer?(); model.stopInteraction(); model.persist(); model.workspaceOpen = false
            model.contextPreview = nil
            if model.inspector == .context { model.closeInspector() }
            clearAnnotation()
        }
        return true
    }
    @objc func systemSuspend() { model.suspend() }
    @objc private func menuClose() { guard !nativeDialogOpen else { return }; NSApp.keyWindow?.performClose(nil) }
    @objc private func menuNew() { guard !nativeDialogOpen else { return }; model.newSession() }
    @objc private func menuUpdates() { guard !nativeDialogOpen, model.updates.canCheck else { return }; model.updates.check() }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let guardedActions = [#selector(menuNew), #selector(menuSettings), #selector(menuLibrary), #selector(menuPause), #selector(menuUpdates), #selector(menuWorkspace), #selector(menuClose)]
        if nativeDialogOpen, let action = item.action, guardedActions.contains(action) { return false }
        if item.action == #selector(menuUpdates) { return model.updates.canCheck }
        if item.action == #selector(menuPause) { item.title = model.paused && model.active != nil ? "Resume" : "Pause chat"; return model.active != nil }
        return true
    }
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if (event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true), !showingStatusMenu, let menu = statusMenu, let button = statusItem.button {
            showingStatusMenu = true; statusItem.menu = menu; button.performClick(nil); statusItem.menu = nil; showingStatusMenu = false; return
        }
        if !showingStatusMenu { openWorkspace() }
    }
    @objc private func menuWorkspace() { openWorkspace() }
    @objc private func menuLibrary() { guard !nativeDialogOpen else { return }; model.showHistory() }
    @objc private func menuPause() { guard !nativeDialogOpen, model.active != nil else { return }; model.togglePause() }
    @objc private func menuSettings() { guard !nativeDialogOpen else { return }; model.openSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openWorkspace(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        model.commitComposer?(); model.suspend()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
