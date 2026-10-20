import AppKit
import LiltCore

extension AppController {
    /// Generated context in the real production panel, without desktop or AX reads.
    func runCurrentWorkVisualAcceptance(output: URL, results: inout [String: Bool]) async throws {
        guard CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") else {
            results["currentWorkVisualRequiresDisposableHarness"] = false; return
        }
        let visible = workspace.isVisible
        workspace.orderOut(nil)
        defer { if visible { workspace.makeKeyAndOrderFront(nil) } }
        let account = try await ChatGPTAccountChecks.makeSettingsFixture()
        let fixture = try AppModel(testingAccount: account, dataDirectory: output.appendingPathComponent("current-work-visual-fixture"))
        fixture.voice.enableFixtures(); fixture.newSession(title: "Generated context layout")
        let data = try Data(contentsOf: output.appendingPathComponent("fixtures/A.png"))
        let panel = NativeWorkspaceWindow(model: fixture, rememberFrame: false)
        defer { fixture.suspend(); panel.close() }
        func editor(_ view: NSView?) -> ComposerTextView? {
            guard let view else { return nil }
            if let input = view as? ComposerTextView { return input }
            return view.subviews.lazy.compactMap { editor($0) }.first
        }
        func install(allowed: Bool) {
            fixture.workContext.installFixture(screenAuthorized: allowed, selectionAuthorized: allowed,
                selection: { .init(text: "Generated textbook selection") }, capture: {
                    ContextSnapshot(data: data, image: NSImage(data: data)!, windowID: nil,
                        frame: CGRect(x: 0, y: 0, width: 400, height: 260), generation: UUID(), capturedAt: Date())
                })
            fixture.workContext.prepareInvocation()
        }
        var ready: [Bool] = [], context: [Bool] = [], denied: [Bool] = [], settings: [Bool] = []
        for dark in [false, true] {
            let name = dark ? "dark" : "light"
            panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            install(allowed: true)
            fixture.backToChat(); fixture.draft = ""; fixture.collapseCompanion()
            panel.makeKeyAndOrderFront(nil); await settle(); applyHarnessCompanionLayout(panel)
            let input = editor(panel.contentView)
            ready.append(fixture.workContext.enabled && !fixture.companionExpanded &&
                abs(panel.frame.width - 300) < 1 && abs(panel.frame.height - 45) < 1)
            try snapshot(panel, to: output.appendingPathComponent("current-work-ready-" + name + ".png"), provenance: .generatedHarness(account: account))
            fixture.expandCompanion(); await settle(); applyHarnessCompanionLayout(panel)
            if let input { panel.makeFirstResponder(input) }
            let contextHeight = panel.frame.height
            context.append(fixture.workContext.screenAuthorized && fixture.workContext.hasSelectionText &&
                panel.frame.width == 320 && contextHeight < 190 && contextHeight >= 140 &&
                input != nil && editor(panel.contentView) === input && panel.firstResponder === input)
            try snapshot(panel, to: output.appendingPathComponent("current-work-selection-ask-" + name + ".png"), provenance: .generatedHarness(account: account))
            install(allowed: false); await settle(); applyHarnessCompanionLayout(panel)
            denied.append(!fixture.workContext.screenAuthorized && !fixture.workContext.selectionAuthorized &&
                !fixture.workContext.hasSelectionText && panel.frame.height == contextHeight && fixture.draft.isEmpty &&
                editor(panel.contentView) === input && !fixture.voice.listening)
            try snapshot(panel, to: output.appendingPathComponent("current-work-permission-ask-" + name + ".png"), provenance: .generatedHarness(account: account))
            fixture.openSettings(); await settle(); applyHarnessCompanionLayout(panel)
            settings.append(fixture.workspaceRoute == .settings && panel.frame.width == 380 && panel.frame.height == 520 &&
                editor(panel.contentView) === input && panel.firstResponder !== input)
            try snapshot(panel, to: output.appendingPathComponent("current-work-settings-" + name + ".png"), provenance: .generatedHarness(account: account))
        }
        results["currentWorkEnabledPreservesReadyFootprint"] = ready.allSatisfy { $0 }
        results["currentWorkSelectionUsesCompactAskAndSameFocusedEditor"] = context.allSatisfy { $0 }
        results["currentWorkPermissionNoticeKeepsTypingAndGeometry"] = denied.allSatisfy { $0 }
        results["currentWorkSettingsRetainsCompactRouteAndEditor"] = settings.allSatisfy { $0 }
    }
}
