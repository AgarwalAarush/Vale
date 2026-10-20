import AppKit
import LiltCore

/// SwiftUI virtual accessibility nodes can implement the public selectors
/// without declaring the full NSAccessibilityProtocol conformance. Optional
/// Objective-C dispatch preserves those nodes instead of pruning their tree.
struct CompanionAccessibilityElement {
    let object: NSObject
    func accessibilityIdentifier() -> String? { (object as AnyObject).accessibilityIdentifier?() ?? nil }
    func accessibilityChildren() -> [Any] { (object as AnyObject).accessibilityChildren?() ?? [] }
    func accessibilityLabel() -> String? { (object as AnyObject).accessibilityLabel?() ?? nil }
    func accessibilityValue() -> Any? { (object as AnyObject).accessibilityValue?() ?? nil }
    func accessibilityHelp() -> String? { (object as AnyObject).accessibilityHelp?() ?? nil }
    func accessibilityFrame() -> NSRect { (object as AnyObject).accessibilityFrame?() ?? .zero }
    func accessibilityRole() -> NSAccessibility.Role? { (object as AnyObject).accessibilityRole?() ?? nil }
    func isAccessibilityEnabled() -> Bool { (object as AnyObject).isAccessibilityEnabled?() ?? false }
    func isAccessibilityHidden() -> Bool { (object as AnyObject).isAccessibilityHidden?() ?? false }
    func accessibilityPerformPress() -> Bool { (object as AnyObject).accessibilityPerformPress?() ?? false }
}

@MainActor enum CompanionControlProbeTrace {
    static var events: [[String: Any]] = []
}

extension AppController {
    /// Drive the real production presentation; never substitute the rejected workspace sizes.
    func applyHarnessCompanionLayout(_ window: NSWindow) {
        (window as? NativeWorkspaceWindow)?.applyCompanionLayout(animated: false)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func companionAccessibilityElements(in window: NSWindow) -> [CompanionAccessibilityElement] {
        var seen = Set<ObjectIdentifier>()
        var elements: [CompanionAccessibilityElement] = []
        func visit(_ value: Any) {
            guard let object = value as? NSObject else { return }
            let element = CompanionAccessibilityElement(object: object)
            guard !element.isAccessibilityHidden() else { return }
            if let view = object as? NSView, view.isHiddenOrHasHiddenAncestor { return }
            let identity = ObjectIdentifier(object)
            guard seen.insert(identity).inserted else { return }
            elements.append(element)
            for child in element.accessibilityChildren() { visit(child) }
            if let view = object as? NSView { for child in view.subviews { visit(child) } }
        }
        if let content = window.contentView { visit(content) }
        return elements
    }

    func companionElement(in window: NSWindow, identifier: String, label: String? = nil) -> CompanionAccessibilityElement? {
        let elements = companionAccessibilityElements(in: window)
        return elements.first { $0.accessibilityIdentifier() == identifier } ?? label.flatMap { label in
            elements.first { $0.accessibilityLabel() == label }
        }
    }

    /// Prefer an exposed public AX action. SwiftUI's in-process AX tree may be
    /// unavailable; then dispatch real mouse events only into a known generated
    /// companion's own control region. Callers verify the resulting state/focus.
    @discardableResult func pressCompanionControl(in window: NSWindow, identifier: String, label: String? = nil) -> Bool {
        let matches = companionAccessibilityElements(in: window).filter {
            $0.accessibilityIdentifier() == identifier || (label != nil && $0.accessibilityLabel() == label)
        }
        let ordered = matches.filter { $0.accessibilityRole() == .button } + matches.filter { $0.accessibilityRole() != .button }
        for element in ordered where element.accessibilityPerformPress() {
            CompanionControlProbeTrace.events.append(["identifier": identifier, "method": "public-native-accessibility-press", "windowNumber": window.windowNumber])
            return true
        }
        guard (CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test")),
              window is NativeWorkspaceWindow, window.identifier?.rawValue == "vale.workspace",
              window.isVisible, let content = window.contentView as? NativeCompanionMaterial else { return false }
        let point: NSPoint
        switch identifier {
        case "vale.companion.back": point = NSPoint(x: 60, y: window.frame.height - 24)
        case "vale.companion.collapse": point = NSPoint(x: window.frame.width - 26, y: window.frame.height - 21.5)
        case "vale.companion.expand": point = NSPoint(x: 23, y: 22.5)
        case "vale.companion.ready-input-top", "vale.companion.ready-input-center":
            guard let input = window.firstResponder as? ComposerTextView else { return false }
            let visible = input.visibleRect
            guard visible.width > 20, visible.height > 4 else { return false }
            let top = input.isFlipped ? visible.minY + 2 : visible.maxY - 2
            point = input.convert(NSPoint(x: visible.midX, y: identifier.hasSuffix("top") ? top : visible.midY), to: nil)
        case "vale.companion.stop-response": point = NSPoint(x: window.frame.width - 33, y: 29.5)
        default: return false
        }
        guard NSRect(origin: .zero, size: window.frame.size).contains(point),
              let hit = content.hitTest(content.convert(point, from: nil)) else { return false }
        let time = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: time,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: time + 0.01,
                windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else { return false }
        CompanionControlProbeTrace.events.append(["identifier": identifier, "method": "software-injected-native-mouse-events", "windowNumber": window.windowNumber,
            "xInWindow": point.x, "yInWindow": point.y, "hitViewClass": String(describing: type(of: hit)), "accessibilityPressAvailable": false, "physicalInputVerified": false])
        // A native control may run a synchronous tracking loop during mouseDown.
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
        return true
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
        results["companionEditorHasNativeTextSystem"] = input.textStorage != nil && input.layoutManager != nil && input.textContainer != nil
        guard results["companionEditorHasNativeTextSystem"] == true else { return }
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
        let readyChat = model.activeID
        var readyClicks: [Bool] = []
        for location in ["top", "center"] {
            let clicked = pressCompanionControl(in: panel, identifier: "vale.companion.ready-input-" + location)
            await settle(); applyHarnessCompanionLayout(panel)
            readyClicks.append(clicked && model.companionExpanded && model.chatSurfaceVisible && model.activeID == readyChat && model.draft.isEmpty && panel.firstResponder === input && panel.contentView.flatMap({ editor(in: $0) }) === input && !model.voice.listening && !model.busy && !model.context.hasSelection)
            model.collapseCompanion(); await settle(); applyHarnessCompanionLayout(panel)
        }
        results["companionReadyPointerClicksExpandSameEditorWithoutHiddenHeaderAction"] = readyClicks.count == 2 && readyClicks.allSatisfy { $0 }
        panel.makeFirstResponder(input)
        input.insertText("Why is kinetic energy squared?", replacementRange: NSRange(location: NSNotFound, length: 0))
        await settle(); applyHarnessCompanionLayout(panel)
        input.setSelectedRange(NSRange(location: 7, length: 7))
        let selection = input.selectedRange(), draft = model.draft
        try await capture("companion-ask-light")
        results["companionTypingExpandsSameFocusedEditor"] = model.companionExpanded && abs(panel.frame.width - 320) < 1 && panel.contentView.flatMap({ editor(in: $0) }) === input && panel.firstResponder === input && !draft.isEmpty && (input.font?.pointSize ?? 0) >= 13
        // Do not click expanded-only coordinates after a failed prerequisite:
        // on Ready those coordinates belong to a native pop-up menu.
        guard results["companionTypingExpandsSameFocusedEditor"] == true else { return }
        let collapsed = pressCompanionControl(in: panel, identifier: "vale.companion.collapse", label: "Collapse Vale")
        await settle(); applyHarnessCompanionLayout(panel)
        let collapsedPreserved = collapsed && !model.companionExpanded && model.draft == draft && input.selectedRange() == selection && abs(panel.frame.height - 45) < 1
        // The owner removed the decorative app-icon expansion button. The
        // actual Ready editor remains the primary pointer expansion surface.
        panel.makeFirstResponder(input)
        let expanded = pressCompanionControl(in: panel, identifier: "vale.companion.ready-input-center")
        await settle(); applyHarnessCompanionLayout(panel)
        results["companionNativeCollapseExpandPreservesDraftAndEditor"] = collapsedPreserved && expanded && model.companionExpanded && model.draft == draft && panel.contentView.flatMap({ editor(in: $0) }) === input
        // A long user question must not bury progress or the arriving answer.
        let longQuestion = (1...45).map { "Generated question paragraph \($0): explain the relationship between speed, work and kinetic energy while I read this textbook." }.joined(separator: "\n\n")
        model.draft = ""; model.updateActive { $0.messages = [Message(role: "user", text: longQuestion)] }
        model.busy = true
        try await capture("companion-long-question-thinking-light")
        func replyTailVisible(_ phase: String) -> Bool {
            let candidates = companionScrollViews(in: panel.contentView).filter {
                $0 !== input.enclosingScrollView && ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 100 && $0.contentView.bounds.height > 45
            }
            guard let scroll = candidates.max(by: { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }), let document = scroll.documentView else { return false }
            let visible = scroll.documentVisibleRect
            let tail = document.isFlipped ? document.bounds.maxY - visible.maxY : visible.minY - document.bounds.minY
            CompanionControlProbeTrace.events.append(["phase": phase, "method": "native-reply-scroll-viewport", "documentHeight": document.bounds.height, "viewportY": visible.minY, "viewportHeight": visible.height, "distanceFromTail": tail, "physicalInputVerified": false])
            return tail <= 4 && visible.height > 45 && document.bounds.height > visible.height + 100
        }
        results["companionLongQuestionRevealsThinkingInNativeViewport"] = model.busy && !model.companionShowsEarlierMessages && replyTailVisible("long-question-thinking")
        model.busy = false
        model.updateActive { $0.messages.append(Message(role: "assistant", text: "Generated arriving answer: doubling speed requires four times the work. Kinetic energy grows with v².")) }
        try await capture("companion-long-question-arriving-answer-light")
        results["companionLongQuestionRevealsArrivingAnswerInNativeViewport"] = !model.busy && !model.companionShowsEarlierMessages && replyTailVisible("long-question-answer")
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
        let combinedStateWasPresent = model.pendingFiles.count == 1 && model.context.hasSelection && model.busy
        let stopDispatched = pressCompanionControl(in: panel, identifier: "vale.companion.stop-response", label: "Stop response")
        await settle()
        results["companionConstrainedHeightKeepsComposerAndStopReachable"] = inputRect.minY >= -1 && inputRect.maxY <= 361 && inputRect.width > 100 && combinedStateWasPresent && stopDispatched && !model.busy && model.draft == draft && model.pendingFiles.count == 1
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
        results["companionUsesOneProductionPanel"] = panel is NSPanel && panel.styleMask.subtracting(.resizable).isEmpty && panel.toolbar == nil && NSApp.windows.filter { $0.isVisible && $0.identifier?.rawValue == "vale.workspace" }.count == 1
        try JSONSerialization.data(withJSONObject: ["method": "generated native production-panel state and software-injected native controls", "physicalInputVerified": false, "frames": frames, "controlEvents": CompanionControlProbeTrace.events], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("companion-state-transitions.json"), options: .atomic)
        try await runOwnerReportedUIAcceptance(output: output, results: &results)
        model.draft = ""; model.updateActive { $0.messages = [] }; model.collapseCompanion()
        await settle(); applyHarnessCompanionLayout(panel)
    }

    func companionScrollViews(in root: NSView?) -> [NSScrollView] {
        guard let root else { return [] }
        return ((root as? NSScrollView).map { [$0] } ?? []) + root.subviews.flatMap { companionScrollViews(in: $0) }
    }

    func performCompanionMenuAction(title: String) -> Bool {
        func find(in menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.title == title, item.action != nil { return item }
                if let submenu = item.submenu, let found = find(in: submenu) { return found }
            }
            return nil
        }
        guard let menu = NSApp.mainMenu, let item = find(in: menu), let action = item.action else { return false }
        return NSApp.sendAction(action, to: item.target, from: item)
    }
}
