import AppKit
import LiltCore

extension AppController {
    /// Generated native-window commands exercise the same dispatcher as Carbon.
    /// They never register a global key, access real screen/AX/mic data, or claim
    /// physical keyboard, cross-application, multi-display or consent coverage.
    func runCompanionCommandAcceptance(output: URL, results: inout [String: Bool]) async throws {
        guard CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") else {
            results["companionCommandsRequireDisposableHarness"] = false; return
        }
        let primaryWasVisible = workspace.isVisible
        let primaryResponder = workspace.firstResponder
        workspace.orderOut(nil)
        defer {
            if primaryWasVisible {
                workspace.makeKeyAndOrderFront(nil)
                if let primaryResponder { workspace.makeFirstResponder(primaryResponder) }
            }
        }

        let account = try await ChatGPTAccountChecks.makeSettingsFixture()
        let fixture = try AppModel(testingAccount: account, dataDirectory: output.appendingPathComponent("companion-command-fixture"))
        fixture.voice.enableFixtures()
        fixture.newSession(title: "Generated companion commands")
        let panel = NativeWorkspaceWindow(model: fixture)
        let controller = AppController()
        controller.model = fixture; controller.workspace = panel; panel.delegate = controller
        fixture.showWorkspace = { [weak controller] in controller?.openWorkspace() }
        let background = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 180, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        background.title = "Generated focus fixture"; background.isReleasedWhenClosed = false
        defer {
            fixture.provider.fixtureReply = nil; fixture.showWorkspace = nil; fixture.suspend()
            panel.delegate = nil; panel.close(); background.close()
        }

        var startupSelectionReads = 0, startupCaptures = 0
        fixture.workContext.installFixture(selection: {
            startupSelectionReads += 1
            return .init(text: "Generated selection after explicit summon")
        }, capture: {
            startupCaptures += 1
            return ContextSnapshot(data: Data("GENERATED-STARTUP-CONTEXT".utf8), image: NSImage(size: NSSize(width: 2, height: 2)),
                                   windowID: nil, frame: CGRect(x: 0, y: 0, width: 2, height: 2), generation: UUID(), capturedAt: Date())
        })
        panel.orderOut(nil)
        controller.presentInitially()
        await settle(); applyHarnessCompanionLayout(panel)
        let startupEditor = companionCommandEditor(in: panel.contentView)
        results["companionInitialPresentationPreparesIdentityWithoutSelectionScreenOrMicrophone"] = panel.isVisible && panel.isKeyWindow &&
            startupEditor != nil && panel.firstResponder === startupEditor && fixture.workspaceOpen &&
            fixture.workContext.sourceName != nil && startupSelectionReads == 0 && startupCaptures == 0 &&
            !fixture.workContext.hasSelectionText && !fixture.voice.starting && !fixture.voice.listening
        controller.performCompanionCommand(.toggleVisibility); await settle()
        controller.performCompanionCommand(.toggleVisibility); await settle()
        results["companionExplicitSummonReadsSelectionAfterIdentityOnlyStartup"] = panel.isVisible && panel.firstResponder === startupEditor &&
            startupSelectionReads == 1 && startupCaptures == 0 && fixture.workContext.hasSelectionText && !fixture.voice.listening
        // The rest of this fixture isolates the existing command/editor tests.
        fixture.workContext.setEnabled(false)

        panel.orderOut(nil)
        controller.performCompanionCommand(.toggleVisibility)
        await settle(); applyHarnessCompanionLayout(panel)
        guard let input = companionCommandEditor(in: panel.contentView) else {
            results["companionCommandsHaveNativeEditor"] = false; return
        }
        results["companionCommandHiddenShowsAndFocusesWithoutMicrophone"] = panel.isVisible && panel.isKeyWindow &&
            panel.firstResponder === input && fixture.workspaceOpen && !fixture.voice.starting && !fixture.voice.listening

        input.undoManager?.removeAllActions()
        input.insertText("Generated shortcut draft.", replacementRange: NSRange(location: 0, length: input.string.utf16.count))
        await settle()
        let draft = input.string
        let selection = NSRange(location: 10, length: 8)
        input.setSelectedRange(selection)
        let undo = input.undoManager
        let canUndo = undo?.canUndo == true
        controller.performCompanionCommand(.toggleVisibility)
        await settle()
        results["companionCommandActiveHidesAndPersistsDraft"] = !panel.isVisible && !fixture.workspaceOpen &&
            fixture.draft == draft && fixture.active?.draft == draft && !fixture.voice.listening && !fixture.voice.starting
        controller.performCompanionCommand(.toggleVisibility)
        await settle(); applyHarnessCompanionLayout(panel)
        let restoredAfterHide = panel.isVisible && panel.isKeyWindow && panel.firstResponder === input &&
            companionCommandEditor(in: panel.contentView) === input && input.string == draft &&
            fixture.draft == draft && input.selectedRange() == selection && input.undoManager === undo && canUndo && undo?.canUndo == true

        background.makeKeyAndOrderFront(nil); await settle()
        let wasBackground = panel.isVisible && !panel.isKeyWindow
        controller.performCompanionCommand(.toggleVisibility)
        await settle()
        results["companionCommandVisibleBackgroundFocusesSameDraftSelectionAndUndo"] = restoredAfterHide && wasBackground &&
            panel.isVisible && panel.isKeyWindow && panel.firstResponder === input &&
            companionCommandEditor(in: panel.contentView) === input && fixture.draft == draft &&
            input.selectedRange() == selection && input.undoManager === undo && undo?.canUndo == true && !fixture.voice.listening
        background.orderOut(nil)
        undo?.undo(); await settle()
        let undoRestoredEmpty = input.string.isEmpty && fixture.draft.isEmpty
        undo?.redo(); await settle()
        results["companionCommandRoundTripPreservesWorkingNativeUndo"] = undoRestoredEmpty && input.string == draft && fixture.draft == draft

        input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
        input.setMarkedText(" 追加", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let composedDraft = input.string
        controller.performCompanionCommand(.toggleVisibility); await settle()
        controller.performCompanionCommand(.toggleVisibility); await settle()
        results["companionCommandHideCommitsIMEWithoutRemountingEditor"] = panel.isVisible && panel.firstResponder === input &&
            companionCommandEditor(in: panel.contentView) === input && !input.hasMarkedText() &&
            input.string == composedDraft && fixture.draft == composedDraft && fixture.active?.draft == composedDraft

        fixture.openSettings(); await settle()
        controller.openWorkspace(); await settle()
        results["companionOrdinaryOpenPreservesRequestedSettingsRoute"] = fixture.workspaceRoute == .settings && panel.isVisible &&
            panel.firstResponder !== input && fixture.draft == composedDraft && !fixture.voice.listening
        controller.performCompanionCommand(.toggleVisibility); await settle()
        controller.performCompanionCommand(.toggleVisibility); await settle()
        results["companionGlobalShowReturnsToChatAndExistingEditor"] = fixture.chatSurfaceVisible && panel.isVisible &&
            panel.firstResponder === input && companionCommandEditor(in: panel.contentView) === input && fixture.draft == composedDraft

        let showItem = NSMenuItem(title: "Generated show command", action: NSSelectorFromString("menuWorkspace"), keyEquivalent: "")
        let dictationItem = NSMenuItem(title: "Generated dictation command", action: NSSelectorFromString("menuDictation"), keyEquivalent: "")
        fixture.paused = true
        controller.performCompanionCommand(.toggleDictation)
        results["companionDictationPausedGuardMatchesMenuValidation"] = !controller.canPerformCompanionCommand(.toggleDictation) &&
            !controller.validateMenuItem(dictationItem) && !fixture.voice.starting && !fixture.voice.listening && fixture.draft == composedDraft
        fixture.paused = false
        let sessionID = fixture.activeID
        fixture.activeID = nil
        controller.performCompanionCommand(.toggleDictation)
        results["companionDictationRequiresAnActiveChat"] = !controller.canPerformCompanionCommand(.toggleDictation) &&
            !controller.validateMenuItem(dictationItem) && fixture.activeID == nil && !fixture.voice.starting && !fixture.voice.listening
        fixture.activeID = sessionID

        do {
            let sheet = NSAlert()
            sheet.messageText = "Generated companion command boundary"
            sheet.informativeText = "Disposable native sheet; no screen or microphone permission request."
            sheet.addButton(withTitle: "Done")
            sheet.beginSheetModal(for: panel) { _ in }
            defer { panel.endSheet(sheet.window); sheet.window.orderOut(nil) }
            await settle()
            controller.performCompanionCommand(.toggleVisibility)
            controller.performCompanionCommand(.toggleDictation)
            await settle()
            results["companionNativeSheetBlocksShowHideAndDictationActionsAndValidation"] = panel.attachedSheet === sheet.window &&
                panel.isVisible && !controller.canPerformCompanionCommand(.toggleVisibility) &&
                !controller.canPerformCompanionCommand(.toggleDictation) && !controller.validateMenuItem(showItem) &&
                !controller.validateMenuItem(dictationItem) && fixture.activeID == sessionID &&
                fixture.draft == composedDraft && !fixture.voice.starting && !fixture.voice.listening
        }
        await settle()

        controller.performCompanionCommand(.toggleVisibility); await settle()
        let hiddenBeforeDictation = !panel.isVisible
        controller.performCompanionCommand(.toggleDictation); await settle()
        results["companionExplicitDictationShowsFocusesAndStartsFixtureMic"] = hiddenBeforeDictation && panel.isVisible &&
            panel.isKeyWindow && panel.firstResponder === input && fixture.chatSurfaceVisible && fixture.companionExpanded &&
            fixture.voice.listening && !fixture.voice.starting && controller.validateMenuItem(dictationItem)
        let messageCount = fixture.active?.messages.count
        controller.performCompanionCommand(.toggleDictation); await settle()
        results["companionRepeatedDictationFinishesWithoutEmptySendOrRestart"] = !fixture.voice.listening && !fixture.voice.starting &&
            !fixture.busy && fixture.active?.messages.count == messageCount && fixture.draft == composedDraft

        background.makeKeyAndOrderFront(nil); await settle()
        controller.performCompanionCommand(.toggleDictation); await settle()
        results["companionBackgroundDictationFocusesExistingNativeComposer"] = panel.isVisible && panel.isKeyWindow &&
            panel.firstResponder === input && companionCommandEditor(in: panel.contentView) === input && fixture.voice.listening
        controller.performCompanionCommand(.toggleVisibility); await settle()
        results["companionHideStopsActiveFixtureMicWithoutLosingDraft"] = !panel.isVisible && !fixture.voice.listening &&
            !fixture.voice.starting && !fixture.conversation && fixture.draft == composedDraft
        background.orderOut(nil)

        var pending: ((Result<TutorReply, Error>) -> Void)?
        var sends = 0
        fixture.provider.fixtureReply = { _, _, _, completion in sends += 1; pending = completion }
        controller.performCompanionCommand(.toggleDictation)
        fixture.voice.simulateUtterance("Generated spoken question", token: fixture.voice.fixtureRecognitionToken)
        await until { pending != nil }
        controller.performCompanionCommand(.toggleVisibility); await settle()
        let awaitingHiddenReply = !panel.isVisible && fixture.busy && sends == 1
        pending?(.success(TutorReply(text: "Generated reply received while Vale is hidden.")))
        await until { !fixture.busy }
        results["companionHidePreservesHandedProviderReplyWithoutVoiceRearm"] = awaitingHiddenReply && !panel.isVisible &&
            fixture.active?.messages.last?.role == "assistant" && sends == 1 && !fixture.voice.listening && !fixture.voice.speaking && !fixture.conversation

        let blockedAccount = try await ChatGPTAccountChecks.makeSettingsFixture(planGranted: false)
        let blocked = try AppModel(testingAccount: blockedAccount, dataDirectory: output.appendingPathComponent("companion-command-blocked-fixture"))
        blocked.voice.enableFixtures(); blocked.newSession(title: "Generated unavailable plan")
        let blockedPanel = NativeWorkspaceWindow(model: blocked)
        let blockedController = AppController(); blockedController.model = blocked; blockedController.workspace = blockedPanel
        defer { blocked.suspend(); blockedPanel.close() }
        blockedController.performCompanionCommand(.toggleDictation)
        results["companionDictationShortcutCannotBypassPlanEligibility"] = !blockedAccount.permitsPlanUsage &&
            !blockedController.canPerformCompanionCommand(.toggleDictation) && !blockedController.validateMenuItem(dictationItem) &&
            !blocked.voice.starting && !blocked.voice.listening && !blockedPanel.isVisible

        func menuItems(_ menu: NSMenu?) -> [NSMenuItem] {
            guard let menu else { return [] }
            return menu.items.flatMap { [$0] + menuItems($0.submenu) }
        }
        let commands = menuItems(NSApp.mainMenu).filter { $0.action == showItem.action || $0.action == dictationItem.action }
        results["companionMenuCommandsShowShortcutLegendsWithoutDuplicateKeyHandlers"] = commands.count == 2 &&
            commands.allSatisfy { $0.keyEquivalent.isEmpty && $0.title.contains("⌃⌥") }

        let evidence: [String: Any] = [
            "method": "generated AppKit panel, same native NSTextView, software dispatch through production companion commands",
            "globalHotKeysRegistered": false, "physicalKeyboardVerified": false, "realMicrophoneVerified": false,
            "realScreenOrSelectedTextRead": false, "crossApplicationRestoreVerified": false, "multiDisplayVerified": false,
            "fixtureAccount": true, "fixtureVoice": true
        ]
        let file = output.appendingPathComponent("companion-command-method.json")
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func companionCommandEditor(in root: NSView?) -> ComposerTextView? {
        guard let root else { return nil }
        if let editor = root as? ComposerTextView { return editor }
        return root.subviews.lazy.compactMap { self.companionCommandEditor(in: $0) }.first
    }
}
