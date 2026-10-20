import AppKit
import LiltCore

extension AppController {
    /// Drive the real production presentation; never substitute the rejected workspace sizes.
    func applyHarnessCompanionLayout(_ window: NSWindow) {
        (window as? NativeWorkspaceWindow)?.applyCompanionLayout(animated: false)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func companionAccessibilityElements(in window: NSWindow) -> [any NSAccessibilityProtocol] {
        var seen = Set<ObjectIdentifier>()
        var elements: [any NSAccessibilityProtocol] = []
        func visit(_ object: Any) {
            guard let element = object as? any NSAccessibilityProtocol else { return }
            guard !element.isAccessibilityHidden() else { return }
            if let view = element as? NSView, view.isHiddenOrHasHiddenAncestor { return }
            let identity = ObjectIdentifier(element as AnyObject)
            guard seen.insert(identity).inserted else { return }
            elements.append(element)
            for child in element.accessibilityChildren() ?? [] { visit(child) }
            if let view = element as? NSView { for child in view.subviews { visit(child) } }
        }
        if let content = window.contentView { visit(content) }
        return elements
    }

    func companionElement(in window: NSWindow, identifier: String, label: String? = nil) -> (any NSAccessibilityProtocol)? {
        let elements = companionAccessibilityElements(in: window)
        return elements.first { $0.accessibilityIdentifier() == identifier } ?? label.flatMap { label in
            elements.first { $0.accessibilityLabel() == label }
        }
    }

    /// This is a native accessibility action, not a physical pointer/VoiceOver claim.
    @discardableResult func pressCompanionControl(in window: NSWindow, identifier: String, label: String? = nil) -> Bool {
        companionElement(in: window, identifier: identifier, label: label)?.accessibilityPerformPress() == true
    }

    func companionShowsImportStatus(in window: NSWindow, expected: String) -> Bool {
        guard let element = companionElement(in: window, identifier: "vale.companion.import-status", label: expected) else { return false }
        let value = element.accessibilityValue() as? String
        return element.accessibilityLabel() == expected || value == expected || element.accessibilityHelp() == expected
    }

    /// Generated native Ready/Ask/Answer journeys and frame traces. No provider or sensor hardware.
    func runCompactCompanionAcceptance(output: URL, results: inout [String: Bool]) async throws {
        guard let panel = workspace as? NativeWorkspaceWindow else {
            results["companionUsesOneProductionPanel"] = false; return
        }
        func editor(in view: NSView) -> ComposerTextView? {
            if let input = view as? ComposerTextView { return input }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let identity = panel.windowNumber
        var frames: [[String: Any]] = []
        func record(_ state: String) {
            frames.append(["state": state, "windowNumber": panel.windowNumber,
                "x": panel.frame.minX, "y": panel.frame.minY, "width": panel.frame.width,
                "height": panel.frame.height, "maxX": panel.frame.maxX, "maxY": panel.frame.maxY])
        }
        func capture(_ state: String) async throws {
            await settle(); applyHarnessCompanionLayout(panel); record(state)
            try snapshot(panel, to: output.appendingPathComponent(state + ".png"))
        }
        model.stopInteraction(); model.backToChat(); model.draft = ""
        model.updateActive { $0.messages = []; $0.guide = nil }
        model.error = nil; model.collapseCompanion(); panel.summon(on: NSScreen.main)
        panel.makeKeyAndOrderFront(nil)
        await settle(); applyHarnessCompanionLayout(panel)
        guard let input = panel.contentView.flatMap({ editor(in: $0) }) else {
            results["companionContinuousEditorMounted"] = false; return
        }
        panel.makeFirstResponder(input)
        let anchor = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        for dark in [false, true] {
            panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            try await capture("companion-ready-\(dark ? "dark" : "light")")
        }
        results["companionReadyIs300By45AndNeverStartsSensors"] = abs(panel.frame.width - 300) < 1 && abs(panel.frame.height - 45) < 1 && !model.voice.listening && !model.voice.starting && !model.voice.speaking && !model.context.hasSelection && !model.busy
        panel.summon(on: panel.screen); panel.summon(on: panel.screen)
        results["companionRepeatedSummonKeepsWindowAndIdleState"] = panel.windowNumber == identity && !model.companionExpanded && model.draft.isEmpty && !model.voice.listening && !model.context.hasSelection
        panel.appearance = NSAppearance(named: .aqua)
        panel.makeFirstResponder(input)
        input.insertText("Why is kinetic energy squared?", replacementRange: NSRange(location: NSNotFound, length: 0))
        await settle(); applyHarnessCompanionLayout(panel)
        input.setSelectedRange(NSRange(location: 7, length: 7))
        let selection = input.selectedRange(), draft = model.draft
        try await capture("companion-ask-light")
        results["companionTypingExpandsSameFocusedEditor"] = model.companionExpanded && abs(panel.frame.width - 320) < 1 && panel.contentView.flatMap({ editor(in: $0) }) === input && panel.firstResponder === input && !draft.isEmpty && (input.font?.pointSize ?? 0) >= 13
        let collapsed = pressCompanionControl(in: panel, identifier: "vale.companion.collapse", label: "Collapse Vale")
        await settle(); applyHarnessCompanionLayout(panel)
        let collapsedPreserved = collapsed && !model.companionExpanded && model.draft == draft && input.selectedRange() == selection && abs(panel.frame.height - 45) < 1
        let expanded = pressCompanionControl(in: panel, identifier: "vale.companion.expand", label: "Expand Vale")
        await settle(); applyHarnessCompanionLayout(panel)
        results["companionNativeCollapseExpandPreservesDraftSelectionAndEditor"] = collapsedPreserved && expanded && model.companionExpanded && model.draft == draft && input.selectedRange() == selection && panel.contentView.flatMap({ editor(in: $0) }) === input
        model.updateActive { $0.messages = [Message(role: "user", text: "Why is kinetic energy squared?"), Message(role: "assistant", text: "Doubling speed takes four times the work. That is why kinetic energy grows with v².\n\nEₖ = ½mv²")] }
        model.draft = ""
        try await capture("companion-answer-short-light")
        results["companionShortAnswerUsesBounded350PointPanel"] = abs(panel.frame.width - 350) < 1 && workspaceMinimumIsValid(panel) && panel.contentView.flatMap({ editor(in: $0) }) === input
        model.updateActive { chat in
            chat.messages.append(Message(role: "assistant", text: (1...35).map { "\($0). Generated long explanation: kinetic energy is the work needed to accelerate a mass from rest to speed v. Keep the question and follow-up controls reachable.\n\n`energy = 0.5 * mass * speed * speed`" }.joined(separator: "\n\n")))
        }
        try await capture("companion-answer-long-light")
        let scrolls = companionScrollViews(in: panel.contentView)
        let longScroll = scrolls.first { ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 50 && $0.contentView.bounds.height > 45 }
        if let scroll = longScroll, let document = scroll.documentView {
            document.scroll(NSPoint(x: 0, y: document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        try await capture("companion-answer-long-bottom-light")
        results["companionLongAnswerScrollsWithoutGrowingOffscreen"] = longScroll != nil && workspaceMinimumIsValid(panel) && panel.frame.height <= 650 && panel.contentView.flatMap({ editor(in: $0) }) === input
        let imageData = try Data(contentsOf: output.appendingPathComponent("fixtures/A.png"))
        model.pasteImage(imageData)
        model.context.installFixture {
            ContextSnapshot(data: imageData, image: NSImage(data: imageData)!, windowID: 42,
                frame: CGRect(x: 100, y: 100, width: 400, height: 260), generation: UUID(), capturedAt: Date())
        }
        model.busy = true; model.error = "Generated combined-state message. Your question and files remain saved."
        model.draft = draft; await settle(); applyHarnessCompanionLayout(panel)
        // A programmatic size stress on the actual production hierarchy, not a
        // claim about a physical small display or its window-server placement.
        panel.setFrame(NSRect(x: anchor.x - 350, y: anchor.y - 360, width: 350, height: 360), display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        let inputRect = input.convert(input.bounds, to: panel.contentView)
        try snapshot(panel, to: output.appendingPathComponent("companion-constrained-height-combined-synthetic-stress.png"))
        let stop = companionElement(in: panel, identifier: "vale.companion.stop-response", label: "Stop response")
        let stopFrame = stop?.accessibilityFrame() ?? .zero
        results["companionConstrainedHeightKeepsComposerAndStopReachable"] = inputRect.minY >= -1 && inputRect.maxY <= panel.frame.height + 1 && inputRect.width > 100 && stop != nil && stopFrame.width > 0 && stopFrame.height > 0 && panel.frame.intersects(stopFrame) && model.pendingFiles.count == 1 && model.context.hasSelection
        model.busy = false; model.error = nil; model.stopSharing()
        if let attachment = model.pendingFiles.first { model.removeFile(attachment) }
        applyHarnessCompanionLayout(panel)
        model.draft = draft
        model.openSettings(); await settle(); applyHarnessCompanionLayout(panel)
        let covered = panel.firstResponder !== input
        let back = pressCompanionControl(in: panel, identifier: "vale.companion.back", label: "Back to chat")
        await settle(); applyHarnessCompanionLayout(panel)
        results["companionNativeBackReturnsFromSettingsToSameDraft"] = covered && back && model.chatSurfaceVisible && model.draft == draft && panel.contentView.flatMap({ editor(in: $0) }) === input && panel.firstResponder === input
        record("companion-returned-from-settings")
        let chatID = model.activeID
        func sendEscape() {
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) { NSApp.sendEvent(event) }
        }
        panel.makeFirstResponder(input); sendEscape(); await settle(); applyHarnessCompanionLayout(panel)
        let escapeCollapsed = panel.isVisible && !model.companionExpanded && model.draft == draft
        sendEscape(); await settle()
        let escapeDismissed = !panel.isVisible && model.activeID == chatID && model.draft == draft
        openWorkspace(); await settle(); applyHarnessCompanionLayout(panel)
        results["companionEscapeCollapseDismissSummonPreservesDraft"] = escapeCollapsed && escapeDismissed && panel.isVisible && panel.windowNumber == identity && model.activeID == chatID && model.draft == draft && !model.voice.listening && !model.context.hasSelection
        record("companion-escape-resummoned")
        results["companionAllStateTransitionsKeepTopRightAnchor"] = frames.allSatisfy { row in
            guard let x = row["maxX"] as? CGFloat, let y = row["maxY"] as? CGFloat else { return false }
            return abs(x - anchor.x) <= 1 && abs(y - anchor.y) <= 1 && row["windowNumber"] as? Int == identity
        }
        results["companionUsesOneProductionPanel"] = panel is NSPanel && panel.styleMask == .borderless && panel.toolbar == nil && NSApp.windows.filter { $0.isVisible && $0.identifier?.rawValue == "vale.workspace" }.count == 1
        try JSONSerialization.data(withJSONObject: ["method": "generated native production-panel state and accessibility actions", "physicalInputVerified": false, "frames": frames], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("companion-state-transitions.json"), options: .atomic)
        model.draft = ""; model.updateActive { $0.messages = [] }; model.collapseCompanion()
        await settle(); applyHarnessCompanionLayout(panel)
    }

    func companionScrollViews(in root: NSView?) -> [NSScrollView] {
        guard let root else { return [] }
        return (root as? NSScrollView).map { [$0] } ?? root.subviews.flatMap { companionScrollViews(in: $0) }
    }
}
