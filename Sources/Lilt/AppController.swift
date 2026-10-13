import AppKit
import SwiftUI
import Carbon
import LiltCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppController: NSObject, NSApplicationDelegate {
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
    private var testing = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        testing = CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test")
        let testDirectory = testing ? URL(fileURLWithPath: CommandLine.arguments.last!).appendingPathComponent("test-library") : nil
        model = AppModel(dataDirectory: testDirectory)
        setupWindows(); setupMenu(); registerHotKey()
        model.showCoach = { [weak self] in self?.openCoach() }
        model.showLibrary = { [weak self] in self?.openLibrary() }
        model.hideOverlay = { [weak self] in self?.clearAnnotation() }
        model.showPoint = { [weak self] point, snapshot in self?.point(point, snapshot: snapshot) }
        model.showPreview = { [weak self] image in self?.preview(image) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.model.cancel(); self.model.voice.stop(); self.clearAnnotation(); return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," { self.model.settings = true; self.openLibrary(); return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "n" { self.model.selectedID = nil; self.model.settings = false; self.openLibrary(); return nil }
            return event
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemSuspend), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemSuspend), name: NSWorkspace.screensDidSleepNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(systemSuspend), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        if testing { Task { await runHarness() } } else { openLibrary() }
    }
    private func setupWindows() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        capsule = makePanel(size: NSSize(width: 430, height: 62))
        capsule.contentView = NSHostingView(rootView: CapsuleView(model: model, openCoach: { [weak self] in self?.openCoach() }))
        capsule.setFrameOrigin(NSPoint(x: visible.maxX - 450, y: visible.maxY - 82))
        coach = makePanel(size: NSSize(width: 410, height: 480))
        coach.contentView = NSHostingView(rootView: CoachView(model: model, close: { [weak self] in self?.coach.orderOut(nil) }))
        coach.setFrameOrigin(NSPoint(x: visible.maxX - 430, y: visible.minY + 24))
        library = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        library.title = "Lilt"; library.titlebarAppearsTransparent = true; library.titleVisibility = .hidden
        library.backgroundColor = NSColor(red: 0.10, green: 0.11, blue: 0.12, alpha: 1); library.appearance = NSAppearance(named: .darkAqua)
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
        }
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
        guard model.active != nil else { openLibrary(); return }
        library?.orderOut(nil)
        capsule.orderFrontRegardless(); coach.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, let root = self.coach.contentView else { return }
            func editor(_ view: NSView) -> NSView? {
                if view.identifier?.rawValue == "lilt.composer" { return view }
                for child in view.subviews { if let result = editor(child) { return result } }; return nil
            }
            if let input = editor(root) { self.coach.makeFirstResponder(input) }
        }
    }
    func openLibrary() { coach?.orderOut(nil); if model.active == nil { capsule?.orderOut(nil) }; library.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    private func setupMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(title: "Lilt"); appItem.submenu = appMenu
        let settings = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ","); settings.target = self; appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let appQuit = NSMenuItem(title: "Quit Lilt", action: #selector(menuQuit), keyEquivalent: "q"); appQuit.target = self; appMenu.addItem(appQuit)
        let fileItem = NSMenuItem(); main.addItem(fileItem); let fileMenu = NSMenu(title: "File"); fileItem.submenu = fileMenu
        let newItem = NSMenuItem(title: "New session", action: #selector(menuNew), keyEquivalent: "n"); newItem.target = self; fileMenu.addItem(newItem)
        fileMenu.addItem(NSMenuItem(title: "Close window", action: NSSelectorFromString("performClose:"), keyEquivalent: "w"))
        let editItem = NSMenuItem(); main.addItem(editItem); let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Lilt")
        statusItem.button?.toolTip = "Lilt · Control–Option–Space"
        let menu = NSMenu()
        for (title, action) in [("Open coach", #selector(menuCoach)), ("Session library", #selector(menuLibrary)), ("Pause session", #selector(menuPause)), ("Settings…", #selector(menuSettings))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator()); let quit = NSMenuItem(title: "Quit Lilt", action: #selector(menuQuit), keyEquivalent: "q"); quit.target = self; menu.addItem(quit); statusItem.menu = menu
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
        if status != noErr { model.error = "The coach shortcut is already in use. You can open Lilt from the menu bar." }
    }
    func point(_ point: PointTarget, snapshot: ContextSnapshot) {
        clearAnnotation()
        guard point.isValid, let bounds = snapshot.frame, snapshot.generation == model.context.generation else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let frame = NSRect(x: bounds.minX + CGFloat(point.x) * bounds.width - 6, y: primaryHeight - bounds.minY - CGFloat(point.y + point.height) * bounds.height - 6, width: CGFloat(point.width) * bounds.width + 12, height: CGFloat(point.height) * bounds.height + 12)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false; window.ignoresMouseEvents = true; window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RoundedRectangle(cornerRadius: 7).stroke(Theme.accent, lineWidth: 2).padding(4).background(Theme.accent.opacity(0.06)).accessibilityLabel(point.label))
        annotation = window; window.orderFrontRegardless()
        let created = Date(); let expectedGeneration = snapshot.generation; let expectedFrame = snapshot.frame; let expectedData = snapshot.data
        var checkingFrame = false
        annotationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Date().timeIntervalSince(created) > 5 || self.model.context.generation != expectedGeneration || self.model.context.currentFrame() != expectedFrame { self.clearAnnotation(); return }
                if !checkingFrame {
                    checkingFrame = true
                    Task { [weak self, weak window] in
                        defer { checkingFrame = false }
                        guard let self, let window, self.annotation === window else { return }
                        let fresh = try? await self.model.context.capture()
                        guard self.annotation === window else { return }
                        if fresh?.data != expectedData { self.clearAnnotation() }
                    }
                }
            }
        }
    }
    func clearAnnotation() { annotationTimer?.invalidate(); annotationTimer = nil; annotation?.orderOut(nil); annotation = nil }
    private func preview(_ image: NSImage) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Shared context preview"; window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: Image(nsImage: image).resizable().scaledToFit().padding(16).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background))
        window.center(); auxiliary.append(window); window.makeKeyAndOrderFront(nil)
        if auxiliary.count > 3 { auxiliary.removeFirst().close() }
    }
    @objc func systemSuspend() { model.suspend() }
    @objc private func menuNew() { model.selectedID = nil; model.settings = false; openLibrary() }
    @objc private func menuCoach() { openCoach() }
    @objc private func menuLibrary() { openLibrary() }
    @objc private func menuPause() { if model.active != nil { model.togglePause() } }
    @objc private func menuSettings() { model.settings = true; openLibrary() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openLibrary(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.suspend(); if let hotKey { UnregisterEventHotKey(hotKey) }; if let monitor { NSEvent.removeMonitor(monitor) } }
}
