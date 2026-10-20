import AppKit
import LiltCore

extension AppController {
    /// Focused regression coverage for the owner's actual1.3.3 rejection.
    /// Images are generated-data, full native in-process rasters. They do not
    /// establish macOS26 compositor optics, physical input or real capture.
    func runOwnerReportedUIAcceptance(output: URL, results: inout [String: Bool]) async throws {
        guard CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test"),
              let primary = workspace as? NativeWorkspaceWindow,
              let primaryEditor = ownerUIEditor(in: primary.contentView) else {
            results["ownerUIHarnessHasNativeEditor"] = false; return
        }
        let savedExpanded = model.companionExpanded
        let savedAppearance = primary.appearance
        let savedDraft = model.draft
        let savedSelection = primaryEditor.selectedRange()
        let savedSessionID = model.activeID
        defer {
            if model.draft != savedDraft { model.draft = savedDraft }
            model.backToChat(); model.companionExpanded = savedExpanded
            primary.appearance = savedAppearance
            primary.makeKeyAndOrderFront(nil)
            applyHarnessCompanionLayout(primary)
            primary.makeFirstResponder(primaryEditor)
            primaryEditor.setSelectedRange(savedSelection)
        }
        var measurements: [[String: Any]] = []

        // Exercise the actual application's native menu/monitor without ever
        // dispatching a capture chooser or touching the global pasteboard.
        func items(in menu: NSMenu?) -> [NSMenuItem] {
            guard let menu else { return [] }
            return menu.items.flatMap { [$0] + items(in: $0.submenu) }
        }
        let contextModifiers: NSEvent.ModifierFlags = [.command, .shift]
        let fileItems = items(in: NSApp.mainMenu).filter { $0.keyEquivalent.lowercased() == "a" && $0.keyEquivalentModifierMask == contextModifiers }
        let windowItems = items(in: NSApp.mainMenu).filter { $0.keyEquivalent.lowercased() == "s" && $0.keyEquivalentModifierMask == contextModifiers }
        results["ownerMainMenuExposesUniqueFileAndWindowKeyboardCommands"] = fileItems.count == 1 && windowItems.count == 1 && fileItems.first?.action != nil && windowItems.first?.action != nil
        let hadUndo = primaryEditor.undoManager?.canUndo == true
        func sendSettingsKey() {
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: primary.windowNumber,
                context: nil, characters: ",", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43) {
                NSApp.sendEvent(event)
            }
        }
        primary.makeKeyAndOrderFront(nil); primary.makeFirstResponder(primaryEditor)
        sendSettingsKey(); await settle(); applyHarnessCompanionLayout(primary)
        let settingsOpened = model.workspaceRoute == .settings && primary.firstResponder !== primaryEditor
        model.backToChat(); await settle(); applyHarnessCompanionLayout(primary)
        results["ownerCommandCommaRetainsNativeDraftSelectionAndUndo"] = settingsOpened && model.chatSurfaceVisible &&
            model.activeID == savedSessionID && model.draft == savedDraft && primaryEditor.string == savedDraft &&
            ownerUIEditor(in: primary.contentView) === primaryEditor && primaryEditor.selectedRange() == savedSelection &&
            (primaryEditor.undoManager?.canUndo == true) == hadUndo

        do {
            let alert = NSAlert()
            alert.messageText = "Generated command boundary"
            alert.informativeText = "Disposable native sheet; no files, screen or microphone access."
            alert.addButton(withTitle: "Done")
            alert.beginSheetModal(for: primary) { _ in }
            defer {
                if primary.attachedSheet === alert.window { primary.endSheet(alert.window) }
                alert.window.orderOut(nil)
            }
            await settle()
            let blocked = fileItems.count == 1 && windowItems.count == 1 &&
                !validateMenuItem(fileItems[0]) && !validateMenuItem(windowItems[0])
            sendSettingsKey(); await settle()
            results["ownerNativeSheetBlocksContextCommandsAndSettingsShortcut"] = blocked &&
                primary.attachedSheet === alert.window && model.chatSurfaceVisible && model.draft == savedDraft &&
                model.activeID == savedSessionID && primaryEditor.selectedRange() == savedSelection
        }
        await settle()

        // A granted, memory-only account removes the legitimate disconnected
        // status row so the ordinary empty Ask geometry can be measured.
        primary.orderOut(nil)
        let account = try await ChatGPTAccountChecks.makeSettingsFixture()
        let fixture = try AppModel(testingAccount: account, dataDirectory: output.appendingPathComponent("owner-ui-connected-fixture"))
        fixture.voice.enableFixtures(); fixture.newSession(title: "Generated owner UI geometry")
        let panel = NativeWorkspaceWindow(model: fixture)
        defer { fixture.suspend(); panel.close() }
        panel.makeKeyAndOrderFront(nil)
        await settle(); applyHarnessCompanionLayout(panel)
        guard let input = ownerUIEditor(in: panel.contentView), let root = panel.contentView else {
            results["ownerUIHarnessHasNativeEditor"] = false; return
        }
        var readyGeometry: [Bool] = [], askGeometry: [Bool] = [], settingsGeometry: [Bool] = []
        var glyphAndUndo = false
        for dark in [false, true] {
            let appearance = dark ? "dark" : "light"
            panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            fixture.backToChat(); fixture.draft = ""; fixture.collapseCompanion()
            await settle(); applyHarnessCompanionLayout(panel); panel.makeFirstResponder(input)
            input.setSelectedRange(NSRange(location: 0, length: 0))
            panel.contentView?.layoutSubtreeIfNeeded()
            let readyCaret = ownerUICaretRect(input, in: panel)
            let readyPlaceholder = input.placeholderFirstGlyphRect
            let readyLine = readyCaret.map { input.convert($0, to: root) }
            readyGeometry.append(readyCaret != nil && readyPlaceholder != nil && readyLine != nil &&
                abs((readyCaret?.minX ?? -100) - (readyPlaceholder?.minX ?? 100)) <= 1.5 &&
                abs((readyLine?.midY ?? -100) - root.bounds.midY) <= 1.5 &&
                (readyLine?.height ?? 0) >= 13 && (readyLine?.height ?? 100) <= 22 &&
                abs(panel.frame.height - 45) < 1 && abs(panel.frame.width - 300) < 1 &&
                input.string.isEmpty && fixture.draft.isEmpty)
            measurements.append(["state": "ready-" + appearance, "caret": ownerUIRect(readyCaret),
                "placeholderFirstGlyph": ownerUIRect(readyPlaceholder), "nativeLineInRoot": ownerUIRect(readyLine),
                "panelHeight": panel.frame.height, "fontSize": input.font?.pointSize ?? 0])
            try snapshot(panel, to: output.appendingPathComponent("owner-ready-" + appearance + ".png"), provenance: .generatedHarness(account: account))

            fixture.expandCompanion(); await settle(); applyHarnessCompanionLayout(panel)
            panel.makeFirstResponder(input)
            let askCaret = ownerUICaretRect(input, in: panel)
            let askPlaceholder = input.placeholderFirstGlyphRect
            let askLine = askCaret.map { input.convert($0, to: root) }
            let textTop = askLine.map { root.bounds.maxY - $0.maxY } ?? 10_000
            askGeometry.append(account.permitsPlanUsage && fixture.active?.messages.isEmpty == true &&
                fixture.pendingFiles.isEmpty && !fixture.context.hasSelection && fixture.error == nil &&
                panel.frame.height < 150 && panel.frame.height > 90 && textTop >= 30 && textTop <= 60 &&
                askCaret != nil && askPlaceholder != nil && abs((askCaret?.minX ?? -100) - (askPlaceholder?.minX ?? 100)) <= 1.5 &&
                ownerUIEditor(in: panel.contentView) === input)
            measurements.append(["state": "empty-ask-" + appearance, "caret": ownerUIRect(askCaret),
                "placeholderFirstGlyph": ownerUIRect(askPlaceholder), "firstTextTopFromPanel": textTop,
                "panelHeight": panel.frame.height, "panelWidth": panel.frame.width])
            try snapshot(panel, to: output.appendingPathComponent("owner-empty-ask-" + appearance + ".png"), provenance: .generatedHarness(account: account))

            if !dark, let before = input.placeholderFirstGlyphRect {
                // Compare actual independently laid-out placeholder and typed A;
                // this catches the original5pt fragment-padding/baseline drift.
                input.undoManager?.removeAllActions()
                input.insertText("A", replacementRange: NSRange(location: 0, length: 0))
                await settle(); applyHarnessCompanionLayout(panel)
                var actual: NSRect?
                if let layout = input.layoutManager, let container = input.textContainer, layout.numberOfGlyphs > 0 {
                    layout.ensureLayout(for: container)
                    actual = layout.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: container)
                        .offsetBy(dx: input.textContainerOrigin.x, dy: input.textContainerOrigin.y)
                }
                let typedOnlyA = input.string == "A" && fixture.draft == "A" && input.placeholderFirstGlyphRect == nil
                let hasUndo = input.undoManager?.canUndo == true
                if hasUndo { input.undoManager?.undo() }
                await settle(); applyHarnessCompanionLayout(panel)
                glyphAndUndo = typedOnlyA && hasUndo && actual != nil &&
                    abs(before.minX - (actual?.minX ?? 100)) <= 0.5 && abs(before.minY - (actual?.minY ?? 100)) <= 0.5 &&
                    abs(before.height - (actual?.height ?? 100)) <= 0.5 && input.string.isEmpty && fixture.draft.isEmpty &&
                    input.placeholderFirstGlyphRect != nil && input.selectedRange() == NSRange(location: 0, length: 0)
                measurements.append(["state": "native-placeholder-vs-typed-A", "placeholder": ownerUIRect(before),
                    "typedGlyph": ownerUIRect(actual), "nativeUndoRestoredEmptyDraft": glyphAndUndo])
            }

            let selection = input.selectedRange()
            fixture.openSettings(); await settle(); applyHarnessCompanionLayout(panel)
            settingsGeometry.append(fixture.workspaceRoute == .settings && panel.frame.width <= 400 && panel.frame.height <= 550 &&
                panel.firstResponder !== input && ownerUIEditor(in: panel.contentView) === input && fixture.draft.isEmpty && input.selectedRange() == selection)
            measurements.append(["state": "settings-" + appearance, "panelWidth": panel.frame.width,
                "panelHeight": panel.frame.height, "sameNativeEditor": ownerUIEditor(in: panel.contentView) === input])
            try snapshot(panel, to: output.appendingPathComponent("owner-settings-" + appearance + ".png"), provenance: .generatedHarness(account: account))
        }
        results["ownerReadyNativeCaretMatchesPlaceholderAndCentersVisibleLine"] = readyGeometry.count == 2 && readyGeometry.allSatisfy { $0 }
        results["ownerEmptyConnectedAskStartsBelowHeaderWithoutBlankRows"] = askGeometry.count == 2 && askGeometry.allSatisfy { $0 }
        results["ownerNativePlaceholderMatchesTypedGlyphAndUndoRestoresEmptyDraft"] = glyphAndUndo
        results["ownerSettingsIsCompactAndRetainsSameNativeEditor"] = settingsGeometry.count == 2 && settingsGeometry.allSatisfy { $0 }
        let data = try JSONSerialization.data(withJSONObject: [
            "method": "generated native TextKit geometry, software-injected settings key and full-window in-process raster",
            "physicalInputVerified": false, "macOS26CompositorVerified": false,
            "screenOrMicrophoneAccessRequested": false, "measurements": measurements
        ], options: [.prettyPrinted, .sortedKeys])
        let file = output.appendingPathComponent("owner-ui-native-measurements.json")
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func ownerUIEditor(in root: NSView?) -> ComposerTextView? {
        guard let root else { return nil }
        if let editor = root as? ComposerTextView { return editor }
        return root.subviews.lazy.compactMap { ownerUIEditor(in: $0) }.first
    }
    private func ownerUICaretRect(_ editor: ComposerTextView, in window: NSWindow) -> NSRect? {
        var actual = NSRange(location: NSNotFound, length: 0)
        let screen = editor.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: &actual)
        guard actual.location == 0, screen.minX.isFinite, screen.minY.isFinite, screen.height > 0, screen.height < 100 else { return nil }
        return editor.convert(window.convertFromScreen(screen), from: nil)
    }
    private func ownerUIRect(_ rect: NSRect?) -> [String: CGFloat] {
        guard let rect else { return [:] }
        return ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }
}
