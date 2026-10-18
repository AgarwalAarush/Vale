import AppKit
import SwiftUI
import Carbon
import LiltCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppController: NSObject, NSApplicationDelegate,NSMenuItemValidation,NSWindowDelegate {
    var model: AppModel!
    var capsule: FloatingPanel!
    var coach: FloatingPanel!
    var library: NSWindow!
    var statusItem: NSStatusItem!
    var annotation: NSWindow?
    private var annotationTimer: Timer?
    private var hotKey: EventHotKeyRef?
    private var hotHandler: EventHandlerRef?
    private var monitor: Any?
    private var auxiliary: [NSWindow] = []
    private var contextPreviews:[NSWindow]=[]
    private var filePreviews:[ObjectIdentifier:UUID]=[:]
    private var statusMenu: NSMenu?
    private var showingStatusMenu = false
    private var testing = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        testing = CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test")
        let testDirectory = testing ? URL(fileURLWithPath: CommandLine.arguments.last!).appendingPathComponent("test-library") : nil
        model = AppModel(dataDirectory: testDirectory)
        setupWindows(); setupMenu(); if !testing{registerHotKey()}
        model.showCoach = { [weak self] in self?.openCoach() }
        model.showLibrary = { [weak self] in self?.openLibrary() }
        model.hideOverlay = { [weak self] in self?.clearAnnotation() }
        model.showPoint = { [weak self] point, snapshot in self?.point(point, snapshot: snapshot) }
        model.contextReset = { [weak self] in guard let self else{return};for window in self.contextPreviews{window.close()} }
        model.filesRemoved = { [weak self] ids in guard let self else{return};for window in self.auxiliary.filter({self.filePreviews[ObjectIdentifier($0)].map{ids.contains($0)} ?? false}){window.close()} }
        model.showPreview = { [weak self] image in self?.preview(image) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                let dialog = self.coach.attachedSheet != nil || NSApp.modalWindow != nil || NSApp.keyWindow?.attachedSheet != nil
                if EscapeKey.stopsSession(dialogOpen: dialog) { self.model.stopInteraction(); self.clearAnnotation(); return nil }
                return event
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," { self.model.settings = true; self.openLibrary(); return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "n" { self.model.newSession(); return nil }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            if CoachClose.hidesTheCoach(key: event.charactersIgnoringModifiers ?? "", command: mods.contains(.command), shift: mods.contains(.shift), option: mods.contains(.option), control: mods.contains(.control), coachIsKey: self.coach.isKeyWindow, blocked: self.coach.attachedSheet != nil || NSApp.modalWindow != nil) {
                self.model.coachOpen = false
                self.coach.orderOut(nil); return nil
            }
            return event
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemSuspend), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemSuspend), name: NSWorkspace.screensDidSleepNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(systemSuspend), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        model.expandCoach = { [weak self] in self?.toggleCoachSize() }
        model.showFile = { [weak self] record in self?.previewFile(record) }
        model.closePreview = { [weak self] in self?.contextPreviews.forEach { $0.close() } }
        model.focusComposer = { [weak self] in DispatchQueue.main.async { self?.focusComposer() } }
        if testing { Task { await runHarness() } } else { model.prepareChat(); if model.active == nil { openCoach() } }
    }
    private func setupWindows() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        capsule = makePanel(size: NSSize(width: 430, height: 62))
        capsule.contentView = NSHostingView(rootView: CapsuleView(model: model, openCoach: { [weak self] in self?.openCoach() }))
        coach = makePanel(size: NSSize(width: 410, height: 480))
        let coachHost=NSHostingView(rootView:CoachView(model:model,close:{[weak self]in self?.model.coachOpen=false;self?.coach.orderOut(nil)}));coachHost.sizingOptions=[];coachHost.autoresizingMask=[.width,.height];coach.contentView=coachHost;coach.setContentSize(NSSize(width:410,height:480))
        coach.setFrameOrigin(NSPoint(x: visible.maxX - 430, y: visible.minY + 24))
        seatCapsule()
        NotificationCenter.default.addObserver(self, selector: #selector(coachMoved), name: NSWindow.didMoveNotification, object: coach)
        NotificationCenter.default.addObserver(self, selector: #selector(coachMoved), name: NSWindow.didResizeNotification, object: coach)
        library = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        library.title = "Vale"; library.titlebarAppearsTransparent = true; library.titleVisibility = .hidden
        library.backgroundColor = Theme.windowBackground; library.appearance = NSAppearance(named: .darkAqua)
        let libraryHost = NSHostingView(rootView: LibraryView(model: model))
        libraryHost.sizingOptions = []
        libraryHost.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
        libraryHost.autoresizingMask = [.width, .height]
        library.contentView = libraryHost
        library.setContentSize(NSSize(width: 900, height: 650))
        library.minSize = NSSize(width: 760, height: 540); library.isReleasedWhenClosed = false; library.center()
        if !testing {
            library.setFrameAutosaveName("LiltLibrary")
            if library.frame.width > visible.width || library.frame.height > visible.height { library.setContentSize(NSSize(width: min(900, visible.width), height: min(650, visible.height - 30))); library.center() }
            bringLibraryOnScreen()
        }
    }
    private func bringLibraryOnScreen() {
        let window=DisplayRect(x:library.frame.origin.x,y:library.frame.origin.y,width:library.frame.width,height:library.frame.height)
        let screens=NSScreen.screens.map{DisplayRect(x:$0.frame.origin.x,y:$0.frame.origin.y,width:$0.frame.width,height:$0.frame.height)}
        if !WindowPlacement.isVisible(window,on:screens){library.center()}
    }
    private func makePanel(size: NSSize) -> FloatingPanel {
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }
    func openCoach() {
        if model.active == nil { model.prepareChat() }
        guard LaunchPresentation.presentsCoach(hasActiveChat: model.active != nil, hasError: model.error != nil) else { return }
        model.coachOpen=true
        library?.orderOut(nil)
        seatCapsule()
        capsule.orderFrontRegardless(); coach.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.focusComposer() }
    }
    /// After a question leaves the field, the keyboard returns there. The field may not exist on the first try.
    private func focusComposer(attemptsLeft: Int = ComposerFocus.attempts) {
        guard ComposerFocus.shouldRetry(found: false, attemptsLeft: attemptsLeft) else { return }
        if let root = coach.contentView, let field = Self.composerField(in: root) {
            coach.makeFirstResponder(field)
            return
        }
        let remaining = attemptsLeft - 1
        DispatchQueue.main.async { [weak self] in self?.focusComposer(attemptsLeft: remaining) }
    }
    private static func composerField(in view: NSView) -> NSView? {
        if view.identifier?.rawValue == "lilt.composer" { return view }
        for child in view.subviews { if let result = composerField(in: child) { return result } }
        return nil
    }
    func openLibrary() { model.coachOpen = false; coach?.orderOut(nil); if model.active == nil { capsule?.orderOut(nil) }; library.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    private func toggleCoachSize(){
        model.expanded.toggle();let visible=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        let size=NSSize(width:min(model.expanded ? 560 : 410,visible.width-32),height:min(model.expanded ? 700 : 480,visible.height-40))
        let origin=NSPoint(x:max(visible.minX+16,min(coach.frame.maxX-size.width,visible.maxX-size.width-16)),y:max(visible.minY+20,min(coach.frame.minY,visible.maxY-size.height-20)))
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduce ? 0 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            coach.animator().setFrame(NSRect(origin: origin, size: size), display: true)
        } completionHandler: { [weak self] in self?.seatCapsule() }
    }
    /// The capsule shares the coach’s right edge and sits in the gap above it.
    private func seatCapsule() {
        guard CapsuleSeat.onTheCoach else { return }
        let screen = coach.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let y = CapsuleSeat.y(coachMaxY: coach.frame.maxY, capsuleHeight: capsule.frame.height, visibleMaxY: visible.maxY)
        let x = min(max(visible.minX + 16, coach.frame.maxX - capsule.frame.width), visible.maxX - capsule.frame.width - 16)
        capsule.setFrameOrigin(NSPoint(x: x, y: y))
    }
    @objc private func coachMoved() {
        guard coach.isVisible else { return }
        seatCapsule()
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
        statusItem.button?.toolTip = "Vale · click to type · Control–Option–Space"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let menu = NSMenu()
        for (title, action) in [("Open assistant", #selector(menuCoach)), ("Chat history", #selector(menuLibrary)), ("Pause chat", #selector(menuPause)), ("Settings…", #selector(menuSettings))] {
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
            DispatchQueue.main.async { controller.openCoach() }; return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &event, pointer, &hotHandler)
        let id = EventHotKeyID(signature: 0x4C696C74, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { model.shortcutWarning = "The shortcut is already in use. Open Vale from the menu bar." }
    }
    func point(_ point: PointTarget, snapshot: ContextSnapshot) {
        clearAnnotation()
        guard point.isValid, let bounds = snapshot.frame, snapshot.generation == model.context.generation,model.context.pointIsVisible(point,frame:bounds,windowID:snapshot.windowID) else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let frame = NSRect(x: bounds.minX + CGFloat(point.x) * bounds.width - 6, y: primaryHeight - bounds.minY - CGFloat(point.y + point.height) * bounds.height - 6, width: CGFloat(point.width) * bounds.width + 12, height: CGFloat(point.height) * bounds.height + 12)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false; window.ignoresMouseEvents = true; window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RoundedRectangle(cornerRadius: 7).stroke(Theme.accent, lineWidth: 2).padding(4).background(Theme.accent.opacity(0.06)).accessibilityLabel(point.label))
        annotation = window; window.orderFrontRegardless()
        let expectedGeneration = snapshot.generation; let expectedFrame = snapshot.frame
        annotationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let windowUnchanged = self.model.context.generation == expectedGeneration && self.model.context.currentFrame() == expectedFrame
                let visible = self.model.context.pointIsVisible(point,frame:bounds,windowID:snapshot.windowID,ignoring:CGWindowID(window.windowNumber))
                if PointHighlight.shouldClear(windowUnchanged: windowUnchanged, visible: visible) { self.clearAnnotation() }
            }
        }
    }
    func clearAnnotation() { annotationTimer?.invalidate(); annotationTimer = nil; annotation?.orderOut(nil); annotation = nil }
    private func preview(_ image: NSImage) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Shared context preview"; window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .darkAqua); window.backgroundColor = Theme.windowBackground
        let host=NSHostingView(rootView: Image(nsImage: image).resizable().scaledToFit().padding(16).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background));host.sizingOptions=[];window.contentView=host;window.setContentSize(NSSize(width:800,height:520));window.delegate=self;contextPreviews.append(window)
        window.center(); auxiliary.append(window); window.makeKeyAndOrderFront(nil)
        if auxiliary.count > 3 { auxiliary.removeFirst().close() }
    }
    private func previewFile(_ record:AttachmentRecord) {
        guard let files=model.fileStore else{return}
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:550),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title=record.name;window.isReleasedWhenClosed=false;window.delegate=self;filePreviews[ObjectIdentifier(window)]=record.id;window.appearance=NSAppearance(named:.darkAqua)
        let host=NSHostingView(rootView:FilePreviewView(record:record,store:files));host.sizingOptions=[];window.contentView=host;window.setContentSize(NSSize(width:800,height:550));window.center()
        auxiliary.append(window);window.makeKeyAndOrderFront(nil);if auxiliary.count>3{auxiliary.removeFirst().close()}
    }
    func windowWillClose(_ notification:Notification){
        guard let window=notification.object as? NSWindow else{return}
        auxiliary.removeAll{$0===window};contextPreviews.removeAll{$0===window};filePreviews.removeValue(forKey:ObjectIdentifier(window));window.contentView=nil
    }
    @objc func systemSuspend() { model.suspend() }
    @objc private func menuClose() {
        let blocked = coach.attachedSheet != nil || NSApp.modalWindow != nil
        if CoachClose.hidesTheCoach(key: "w", command: true, shift: false, option: false, control: false, coachIsKey: coach.isKeyWindow, blocked: blocked) {
            model.coachOpen = false
            coach.orderOut(nil)
            return
        }
        NSApp.keyWindow?.performClose(nil)
    }
    @objc private func menuNew() { model.newSession() }
    @objc private func menuUpdates() { model.updates.check() }
    func validateMenuItem(_ item:NSMenuItem)->Bool {
        if item.action == #selector(menuUpdates) { return model.updates.canCheck }
        if item.action == #selector(menuPause) { item.title = model.paused && model.active != nil ? "Resume" : "Pause chat"; return model.active != nil }
        return true
    }
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu, !showingStatusMenu, let menu = statusMenu, let button = statusItem.button {
            showingStatusMenu = true
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
            showingStatusMenu = false
            return
        }
        if showingStatusMenu { return }
        openCoach()
    }
    @objc private func menuCoach() { openCoach() }
    @objc private func menuLibrary() { openLibrary() }
    @objc private func menuPause() { if model.active != nil { model.togglePause() } }
    @objc private func menuSettings() { model.settings = true; openLibrary() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openCoach(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.suspend(); if let hotKey { UnregisterEventHotKey(hotKey) }; if let monitor { NSEvent.removeMonitor(monitor) } }
}
