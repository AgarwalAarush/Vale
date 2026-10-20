import AppKit
import SwiftUI
import LiltCore
import ImageIO
import UniformTypeIdentifiers

extension AppController {
    /// Additional native acceptance for the new workspace. Uses only generated fixture data.
    func runWorkspaceAcceptance(output: URL, results: inout [String: Bool]) async throws {
        let initialWindow = workspace.windowNumber
        let savedFrame = workspace.frame
        let savedAppearance = workspace.appearance
        var settledMinimumChecks: [Bool] = []
        defer { workspace.appearance = savedAppearance; workspace.setFrame(savedFrame, display: true) }
        func composer(in view: NSView) -> ComposerTextView? {
            if let value = view as? ComposerTextView { return value }
            for child in view.subviews { if let value = composer(in: child) { return value } }
            return nil
        }
        func oneWorkspace() -> Bool {
            let content = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
            return workspace.windowNumber == initialWindow && content.count == 1 && content.first === workspace
        }
        func capture(_ name: String) async throws {
            await settle()
            try snapshot(workspace, to: output.appendingPathComponent(name + ".png"))
        }
        model.voice.enableFixtures()
        model.sessions = []; model.activeID = nil; model.selectedID = nil
        model.newSession(title: "New chat")
        workspace.appearance = NSAppearance(named: .aqua)
        workspace.setContentSize(NSSize(width: 1040, height: 740))
        model.sidebarVisible = true; model.compactHistoryVisible = false
        openWorkspace()
        try await capture("workspace-01-empty-light")
        settledMinimumChecks.append(workspaceMinimumIsValid(workspace))
        results["workspaceOneWindowAtLaunch"] = oneWorkspace()
        results["workspaceUsesNativeCompactToolbar"] = workspace.toolbar != nil && workspace.toolbarStyle == .unifiedCompact
        let emptyEditor = workspace.contentView.flatMap { composer(in: $0) }
        workspace.appearance = NSAppearance(named: .darkAqua)
        try await capture("workspace-01b-empty-dark")
        workspace.setContentSize(workspace.contentMinSize)
        try await capture("workspace-01c-empty-minimum-dark")
        results["workspaceMinimumDarkUsesProductionFrameConstraint"] = workspaceMinimumIsValid(workspace, atMinimum: true)
        workspace.appearance = NSAppearance(named: .aqua)
        try await capture("workspace-01d-empty-minimum-light")
        results["workspaceMinimumLightUsesProductionFrameConstraint"] = workspaceMinimumIsValid(workspace, atMinimum: true)
        workspace.appearance = NSAppearance(named: .aqua)
        workspace.setContentSize(NSSize(width: 1040, height: 740))

        let fixtureFiles = [output.appendingPathComponent("fixtures/A.png"), output.appendingPathComponent("fixtures/Brief.pdf")]
        await model.importFiles(fixtureFiles)
        model.draft = "My unsent review, kept while I check the details."
        model.updateActive { chat in
            chat.title = "Planning a research project with diagrams, reading notes and a deliberately long conversation title"
            chat.messages = [
                Message(role: "user", text: "Compare the diagrams and summarize the planning notes."),
                Message(role: "assistant", text: "The first diagram contains a red circle; the second has a blue square.\n\nThe public PDF fixture includes the verification token **HARBOR-73**. Keep that token with the brief, then turn the notes into a short checklist.\n\nYou can keep the supporting details in this chat’s notes and return to this draft when you are ready.")
            ]
            chat.takeaway = "Public fixture note: compare the shapes, retain HARBOR-73, and bring a notebook."
        }
        model.persist(); await settle()
        for (index, title) in ["Weekly reading notes", "A clearer project brief", "Working through the probability problem", "Compare the revised diagrams", "Notes for the next conversation", "A saved thought with an unfinished draft", "A long research conversation about native macOS workflows and precise interface design"].enumerated() {
            var chat = LearningSession(title: title)
            chat.updated = Date().addingTimeInterval(-Double(index + 1) * 3600)
            chat.messages = [Message(role: "user", text: "Generated history content for native layout review.")]
            if index == 5 { chat.draft = "An unfinished thought, preserved locally." }
            model.sessions.append(chat)
        }
        let originalID = model.activeID
        let savedDraft = model.draft
        let pendingIDs = model.pendingFiles.map(\.id)
        guard let editor = workspace.contentView.flatMap({ composer(in: $0) }) else {
            results["workspaceComposerMounted"] = false
            return
        }
        results["workspaceComposerMounted"] = editor.window === workspace
        results["workspaceEmptyToConversationKeepsMountedEditor"] = emptyEditor === editor
        let observesFocusedEditor = editor.observedFocus && workspace.firstResponder === editor
        editor.setSelectedRange(NSRange(location: 3, length: 5))
        let selection = editor.selectedRange()
        try await capture("workspace-02-conversation-light")
        // Synthetic playback/listening only; capture active control contrast without audio hardware.
        model.setConversation(true)
        if let answer = model.active?.messages.last?.text { model.voice.speak(answer) }
        try await capture("workspace-02b-audio-active-light")
        workspace.appearance = NSAppearance(named: .darkAqua)
        try await capture("workspace-02c-audio-active-dark")
        model.setConversation(false); model.voice.stop()
        workspace.appearance = NSAppearance(named: .aqua)

        model.openSettings(); await settle()
        let observesCoveredEditor = !editor.observedFocus && workspace.firstResponder !== editor
        results["workspaceSettingsPreserveDraftFilesAndEditor"] = oneWorkspace() && model.workspaceRoute == .settings && model.activeID == originalID && model.draft == savedDraft && model.pendingFiles.map(\.id) == pendingIDs && workspace.contentView.flatMap({ composer(in: $0) }) === editor && editor.selectedRange() == selection
        try await capture("workspace-03-settings-light")
        model.setConversation(true); await settle()
        results["workspaceSettingsRetainsExplicitActivityUntilStopped"] = model.workspaceRoute == .settings && model.conversation && model.voice.listening && model.draft == savedDraft
        try await capture("workspace-03b-settings-active-voice")
        model.stopInteraction(); await settle()
        results["workspaceStopFromCoveredChatClearsActivityAndKeepsDraft"] = model.workspaceRoute == .settings && !model.conversation && !model.voice.listening && !model.context.hasSelection && model.draft == savedDraft
        model.backToChat(); await settle()
        settledMinimumChecks.append(workspaceMinimumIsValid(workspace))
        results["workspaceComposerObservationTracksFocusAndCoveredRoute"] = observesFocusedEditor && observesCoveredEditor && editor.observedFocus && workspace.firstResponder === editor
        results["workspaceBackRestoresComposerSelection"] = model.activeID == originalID && model.draft == savedDraft && editor.selectedRange() == selection && workspace.firstResponder === editor

        model.showInspector(.notes); await settle()
        results["workspaceNotesStayInWindow"] = oneWorkspace() && model.inspector == .notes && model.active?.takeaway.contains("HARBOR-73") == true && workspace.contentView.flatMap({ composer(in: $0) }) === editor
        try await capture("workspace-04-notes-light")
        model.closeInspector(); model.showInspector(.files)
        try await capture("workspace-05-files-light")
        if let pdf = model.active?.files.first(where: { $0.kind == .pdf }) {
            model.showFile?(pdf); await settle()
            results["workspacePDFPreviewStaysInWindow"] = oneWorkspace() && model.inspector == .file(pdf.id)
            try await capture("workspace-06-pdf-light")
        } else { results["workspacePDFPreviewStaysInWindow"] = false }
        model.closeInspector()
        model.showHistory(); await settle()
        results["workspaceHistoryKeepsCurrentDraft"] = oneWorkspace() && model.activeID == originalID && model.draft == savedDraft && model.historyFocus > 0
        model.historyQuery = "HARBOR-73"
        try await capture("workspace-07-search-light")
        model.historyQuery = ""; model.compactHistoryVisible = false
        model.backToChat(); model.setWeb(true); model.persist()
        try await capture("workspace-07b-web-on-light")
        workspace.appearance = NSAppearance(named: .darkAqua)
        try await capture("workspace-07c-web-on-dark")
        workspace.appearance = NSAppearance(named: .aqua)
        model.newSession(title: "Generated Web-off chat")
        let freshWebOff = model.active?.webEnabled == false
        try await capture("workspace-07d-web-off-light")
        if let originalID { model.navigateToChat(originalID) }
        await settle()
        let savedWebChat = try SessionStore(directory: output.appendingPathComponent("test-library")).load().first { $0.id == originalID }
        results["workspaceSavedWebOptInFollowsResumedChat"] = freshWebOff && model.activeID == originalID && model.active?.webEnabled == true && savedWebChat?.webEnabled == true && model.draft == savedDraft && model.pendingFiles.map(\.id) == pendingIDs
        model.setWeb(false)

        // A real NSTextView marked composition must be committed into the old draft before New chat.
        model.backToChat(); await settle()
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.setMarkedText(" 追加", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let composedDraft = editor.string
        model.newSession(title: "Another workspace fixture"); await settle()
        results["workspaceNavigationCommitsMarkedTextToOrigin"] = model.sessions.first(where: { $0.id == originalID })?.draft == composedDraft && model.activeID != originalID && model.draft.isEmpty
        if let originalID { model.navigateToChat(originalID) }
        await settle()
        results["workspaceHistoryResumesDraftAndFilesDirectly"] = oneWorkspace() && model.activeID == originalID && model.draft == composedDraft && model.pendingFiles.map(\.id) == pendingIDs

        let dialog = NSAlert()
        dialog.messageText = "Generated modal keyboard fixture"
        dialog.addButton(withTitle: "Done")
        dialog.beginSheetModal(for: workspace) { _ in }
        await settle()
        if let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: workspace.windowNumber, context: nil, characters: "n", charactersIgnoringModifiers: "n", isARepeat: false, keyCode: 45) { NSApp.sendEvent(key) }
        results["workspaceModalDialogDoesNotStartAnotherChat"] = model.activeID == originalID && model.draft == composedDraft
        workspace.endSheet(dialog.window); dialog.window.orderOut(nil); dialog.window.close()
        await settle()
        // Restore the explicit origin so a failed modal probe cannot contaminate later cases.
        if let originalID { model.navigateToChat(originalID) }
        await settle()

        workspace.appearance = NSAppearance(named: .darkAqua)
        try await capture("workspace-08-conversation-dark")
        model.openSettings(); try await capture("workspace-09-settings-dark")
        model.backToChat()
        workspace.appearance = NSAppearance(named: .aqua)
        workspace.setContentSize(workspace.contentMinSize); model.compactHistoryVisible = false
        try await capture("workspace-10-compact-chat")
        results["workspaceMinimumConversationUsesProductionFrameConstraint"] = workspaceMinimumIsValid(workspace, atMinimum: true)
        model.showInspector(.notes); try await capture("workspace-11-compact-notes")
        results["workspaceCompactInspectorKeepsWindowIdentity"] = oneWorkspace() && model.draft == composedDraft && model.inspector == .notes
        model.showInspector(.files); model.showHistory(); await settle()
        results["workspaceCompactFilesOpenHistoryInPlace"] = oneWorkspace() && model.compactHistoryVisible && model.inspector == nil && model.draft == composedDraft
        results["workspaceCompactHistoryOwnsSearchFocus"] = workspace.firstResponder is NSTextView && workspace.firstResponder !== editor
        try await capture("workspace-11b-compact-history")
        model.showInspector(.notes); await settle()
        model.closeInspector(); await settle()
        results["workspaceCompactHistoryNotesBackReachesComposer"] = oneWorkspace() && !model.compactHistoryVisible && model.inspector == nil && workspace.firstResponder === editor && model.activeID == originalID && model.draft == composedDraft && model.pendingFiles.map(\.id) == pendingIDs
        model.showHistory(); await settle()
        model.showInspector(.files); await settle()
        model.closeInspector(); await settle()
        results["workspaceCompactHistoryFilesBackReachesComposer"] = oneWorkspace() && !model.compactHistoryVisible && model.inspector == nil && workspace.firstResponder === editor && model.activeID == originalID && model.draft == composedDraft && model.pendingFiles.map(\.id) == pendingIDs
        model.backToChat(); await settle()
        model.closeInspector(); model.openSettings(); await settle()
        results["workspaceQueuedFocusDoesNotEnterHiddenComposer"] = model.workspaceRoute == .settings && workspace.firstResponder !== editor && model.draft == composedDraft
        model.backToChat(); await settle()
        model.closeInspector()
        workspace.setContentSize(NSSize(width: 1280, height: 800))
        model.showInspector(.notes); try await capture("workspace-12-wide-notes")
        results["workspaceWideInspectorKeepsWindowIdentity"] = oneWorkspace() && model.draft == composedDraft
        model.closeInspector(); model.backToChat()

        // Combined panel sizing is a visual acceptance case, not independent panel thumbnails.
        workspace.setContentSize(NSSize(width: 1040, height: 740)); model.sidebarVisible = true
        model.showInspector(.notes); try await capture("workspace-12b-default-details")
        model.closeInspector(); model.backToChat()

        model.persist(); let readyBeforeClose = !model.paused
        workspace.performClose(nil); await settle()
        results["workspaceCloseStopsTransientActivityAndPreservesDraft"] = !workspace.isVisible && !model.voice.listening && !model.voice.speaking && !model.context.hasSelection && model.draft == composedDraft
        openWorkspace(); await settle()
        settledMinimumChecks.append(workspaceMinimumIsValid(workspace))
        results["workspaceReopenKeepsTypingAndOneWindow"] = oneWorkspace() && model.activeID == originalID && model.draft == composedDraft && (!readyBeforeClose || !model.paused) && !model.voice.listening && !model.context.hasSelection
        let loaded = try SessionStore(directory: output.appendingPathComponent("test-library")).load().first(where: { $0.id == originalID })
        results["workspaceNavigationPersistsDraftNotesAndFiles"] = loaded?.draft == composedDraft && loaded?.pendingAttachments.map(\.id) == pendingIDs && loaded?.takeaway.contains("HARBOR-73") == true
        try runMultipageAttachmentAcceptance(output: output, results: &results)
        try await runCursorReplyAcceptance(output: output, results: &results)
        try await runAccountChangeAcceptance(output: output, results: &results)
        await runNativeUndoAcceptance(editor: editor, results: &results)
        try runClosedChatInputAcceptance(output: output, results: &results)
        try await runChatGPTSettingsVisualAcceptance(output: output)
        await settle()
        settledMinimumChecks.append(workspaceMinimumIsValid(workspace))
        results["workspaceMinimumConstraintsSurviveSettledRoutesAndFixtureRestoration"] = settledMinimumChecks.allSatisfy { $0 }
        try await runChatGPTWorkspaceVisualAcceptance(output: output, results: &results)
        try await runImportFeedbackAcceptance(output: output, results: &results)
    }
}

extension AppController {
    /// The exact production window/view composition, with a generated account and isolated store.
    /// Generated credentials cannot reach the production Responses transport.
    func runChatGPTWorkspaceVisualAcceptance(output: URL, results: inout [String: Bool]) async throws {
        workspace.orderOut(nil)
        defer { workspace.makeKeyAndOrderFront(nil) }
        var settledMinimumChecks: [Bool] = []
        for (granted, identityPending) in [(true, false), (false, false), (true, true)] {
            let account = try await ChatGPTAccountChecks.makeSettingsFixture(planGranted: granted, identityPending: identityPending)
            let fixture = try AppModel(testingAccount: account, dataDirectory: output.appendingPathComponent("workspace-account-layout-\(granted)-\(identityPending)-fixture"))
            fixture.voice.enableFixtures(); fixture.newSession()
            let window = NativeWorkspaceWindow(model: fixture, rememberFrame: false)
            defer { fixture.suspend(); window.close() }
            window.setContentSize(NSSize(width: 1040, height: 740)); window.center()
            window.makeKeyAndOrderFront(nil)
            func editor(in view: NSView) -> ComposerTextView? {
                if let input = view as? ComposerTextView { return input }
                return view.subviews.lazy.compactMap { editor(in: $0) }.first
            }
            await settle()
            if let input = window.contentView.flatMap({ editor(in: $0) }) { window.makeFirstResponder(input) }
            let state = identityPending ? "retry-connection" : granted ? "connected" : "grant-needed"
            for dark in [false, true] {
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                await settle()
                try snapshot(window, to: output.appendingPathComponent("workspace-full-\(state)-\(dark ? "dark" : "light")-generated-account.png"), provenance: .generatedHarness(account: account))
            }
            if identityPending {
                window.setContentSize(window.contentMinSize)
                for dark in [false, true] {
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    await settle()
                    try snapshot(window, to: output.appendingPathComponent("workspace-full-retry-connection-minimum-\(dark ? "dark" : "light")-generated-account.png"), provenance: .generatedHarness(account: account))
                }
                results["workspaceRetryConnectionUsesTrueMinimumFrame"] = workspaceMinimumIsValid(window, atMinimum: true) && account.needsIdentityValidation && !account.permitsPlanUsage
            }
            if granted && !identityPending {
                try runCaptureProvenanceAcceptance(window: window, account: account, output: output, results: &results)
                fixture.draft = "Please turn the research into a practical plan."
                fixture.updateActive { chat in
                    chat.title = "Research notes and a practical plan"
                    chat.messages = [Message(role: "user", text: "How should I organize the work?"), Message(role: "assistant", text: "Start with the task you need to finish.\n\nKeep the supporting files in this conversation, write down the decisions, and work through one concrete step at a time. You can keep drafting while you review the answer.")]
                }
                await settle()
                try snapshot(window, to: output.appendingPathComponent("workspace-full-connected-conversation-dark-generated-account.png"), provenance: .generatedHarness(account: account))
                var refusedProduction = false
                fixture.provider.ask(prompt: "Generated account must remain offline") { result in
                    if case .failure = result { refusedProduction = true }
                }
                results["workspaceGeneratedAccountUsesRealViewsAndCannotReachProduction"] = fixture.provider.account === account && refusedProduction
                if let input = window.contentView.flatMap({ editor(in: $0) }) {
                    // Actual native Return with a permitted disposable account and generated attachments.
                    fixture.newSession(title: "Generated native Return with attachments")
                    await fixture.importFiles([output.appendingPathComponent("fixtures/A.png"), output.appendingPathComponent("fixtures/Brief.pdf")])
                    let attachmentIDs = fixture.pendingFiles.map(\.id)
                    let attachmentBytes = try fixture.pendingFiles.map { try Data(contentsOf: fixture.fileStore!.url(for: $0)) }
                    var returnCalls = 0, returnImages = 0
                    fixture.provider.fixtureReply = { _, images, _, complete in
                        returnCalls += 1; returnImages = images.count
                        complete(.success(TutorReply(text: "Generated native Return answer; no production request.")))
                    }
                    fixture.draft = "Generated native Return question."
                    await settle(); window.makeFirstResponder(input)
                    if let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) { NSApp.sendEvent(enter) }
                    await until { !fixture.busy }
                    let question = fixture.active?.messages.first
                    let retainedBytes = try (question?.attachments ?? []).map { try Data(contentsOf: fixture.fileStore!.url(for: $0)) }
                    results["workspaceGeneratedConnectedNativeReturnSendsOriginalAttachments"] = account.permitsPlanUsage && returnCalls == 1 && returnImages == 1 && question?.role == "user" && question?.text == "Generated native Return question." && question?.attachments.map(\.id) == attachmentIDs && retainedBytes == attachmentBytes && fixture.pendingFiles.isEmpty && fixture.draft.isEmpty && fixture.active?.messages.last?.text == "Generated native Return answer; no production request."
                    var sent = 0
                    fixture.provider.fixtureReply = { _, _, _, _ in sent += 1 }
                    func sendKey(_ text: String, code: UInt16) {
                        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code) { NSApp.sendEvent(event) }
                    }
                    window.setContentSize(NSSize(width: 1200, height: 740)); fixture.sidebarVisible = true
                    fixture.showInspector(.notes); fixture.draft = "Generated draft protected while resizing."
                    await settle(); window.makeFirstResponder(input)
                    let resizeDraft = fixture.draft, messageCount = fixture.active?.messages.count
                    window.setContentSize(NSSize(width: 1040, height: 740)); await settle()
                    let resignedOnResize = window.firstResponder !== input
                    sendKey("x", code: 7); sendKey("\r", code: 36); await settle()
                    results["workspaceResizeCoverResignsComposerAndRejectsHiddenKeys"] = resignedOnResize && fixture.draft == resizeDraft && fixture.active?.messages.count == messageCount && sent == 0

                    // Separate direct sidebar command from resizing, with a real marked composition.
                    fixture.stopInteraction(); fixture.sidebarVisible = false; fixture.showInspector(.notes)
                    fixture.draft = "Generated draft protected while showing history."
                    await settle(); window.makeFirstResponder(input)
                    input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
                    input.setMarkedText(" 追加", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                    let markedDraft = input.string
                    window.chrome.toggleSidebar(); await settle()
                    let resignedOnSidebar = window.firstResponder !== input
                    sendKey("x", code: 7); sendKey("\r", code: 36); await settle()
                    results["workspaceSidebarCoverCommitsMarkedTextAndRejectsHiddenKeys"] = resignedOnSidebar && fixture.draft == markedDraft && fixture.active?.draft == markedDraft && !input.hasMarkedText() && sent == 0
                } else {
                    results["workspaceGeneratedConnectedNativeReturnSendsOriginalAttachments"] = false
                    results["workspaceResizeCoverResignsComposerAndRejectsHiddenKeys"] = false
                    results["workspaceSidebarCoverCommitsMarkedTextAndRejectsHiddenKeys"] = false
                }
            }
            await settle()
            settledMinimumChecks.append(workspaceMinimumIsValid(window))
        }
        results["workspaceGeneratedAccountWindowsKeepPositiveSettledMinimum"] = settledMinimumChecks.allSatisfy { $0 }
    }
}

extension AppController {
    /// Actual Settings component with explicit generated accounts; never OAuth or personal credentials.
    func runChatGPTSettingsVisualAcceptance(output: URL) async throws {
        let previousView = workspace.contentView
        let previousFrame = workspace.frame
        let previousAppearance = workspace.appearance
        defer {
            workspace.contentView = previousView
            workspace.appearance = previousAppearance
            workspace.setFrame(previousFrame, display: true)
        }
        workspace.setContentSize(NSSize(width: 740, height: 650))
        for granted in [true, false] {
            let account = try await ChatGPTAccountChecks.makeSettingsFixture(planGranted: granted)
            let content = ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Generated account layout fixture · no OAuth performed").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    ChatGPTAccountSettings(account: account)
                }.padding(32).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Theme.background).foregroundStyle(Theme.ink)
            workspace.contentView = NativeWorkspaceWindow.contentContainer(for: content, size: workspace.contentView?.bounds.size ?? NSSize(width: 740, height: 650))
            for dark in [false, true] {
                workspace.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                await settle()
                let state = granted ? "connected" : "grant-needed"
                try snapshot(workspace, to: output.appendingPathComponent("workspace-account-\(state)-\(dark ? "dark" : "light")-fixture.png"), provenance: .generatedHarness(account: account))
            }
        }
    }
}

extension AppController {
    /// Real AppModel cancellation with a generated connection notification and reply adapter.
    /// This exercises account isolation; it does not perform OAuth or access a real account.
    func runAccountChangeAcceptance(output: URL, results: inout [String: Bool]) async throws {
        let directory = output.appendingPathComponent("account-change-fixture-" + UUID().uuidString)
        let fixture = AppModel(dataDirectory: directory)
        fixture.voice.enableFixtures()
        defer { fixture.suspend() }
        fixture.newSession(title: "Generated account isolation")
        var providerCalls = 0
        fixture.provider.fixtureReply = { _, _, _, _ in providerCalls += 1 }
        fixture.draft = "Keep this question with its original account."
        fixture.send()
        NotificationCenter.default.post(name: ChatGPTAccount.connectionWillChange, object: fixture.provider.account)
        await settle()
        results["chatGPTConnectionChangeCancelsPreprocessing"] = providerCalls == 0 && !fixture.busy && fixture.canRetry && fixture.active?.messages.last?.text == "Keep this question with its original account." && fixture.active?.messages.last?.answerFailed == true

        var pending: ((Result<TutorReply, Error>) -> Void)?
        fixture.provider.fixtureReply = { _, _, _, complete in pending = complete }
        fixture.retry(); await until { pending != nil }
        let reachedProvider = pending != nil && fixture.busy
        fixture.draft = "Preserve this next draft."
        pending?(.success(TutorReply(text: "Generated stale account reply.")))
        NotificationCenter.default.post(name: ChatGPTAccount.connectionWillChange, object: fixture.provider.account)
        await settle()
        let stored = try SessionStore(directory: directory).load().first { $0.id == fixture.activeID }
        results["chatGPTConnectionChangeRejectsQueuedReplyAndKeepsRetry"] = reachedProvider && !fixture.busy && !fixture.conversation && !fixture.voice.listening && !fixture.voice.speaking && !fixture.context.hasSelection && fixture.canRetry && fixture.active?.messages.count == 1 && fixture.draft == "Preserve this next draft." && stored?.draft == fixture.draft && stored?.messages.last?.answerFailed == true
    }
}

extension AppController {
    /// Real model/store transitions on generated data; not a physical URL-drop or button-click claim.
    func runClosedChatInputAcceptance(output: URL, results: inout [String: Bool]) throws {
        let directory = output.appendingPathComponent("closed-chat-input-fixture-" + UUID().uuidString)
        let link = URL(string: "https://example.com/vale-close-drop")!
        let fixture = AppModel(dataDirectory: directory)
        fixture.voice.enableFixtures()
        fixture.newSession(title: "Generated only chat before Close")
        let originalID = fixture.activeID
        fixture.complete()
        let closedOnlyChat = fixture.sessions.count == 1 && fixture.active == nil && fixture.draft.isEmpty
        fixture.keepDroppedLinks([link])
        results["workspaceClosedChatURLDropOwnsEditableDraft"] = closedOnlyChat && fixture.activeID == originalID && fixture.active != nil && fixture.active?.draft == link.absoluteString && fixture.draft == link.absoluteString && fixture.hasInput && !fixture.paused
        let saved = fixture.persist()
        fixture.suspend()

        let restored = AppModel(dataDirectory: directory)
        restored.voice.enableFixtures()
        defer { restored.suspend() }
        restored.prepareChat()
        results["workspaceClosedChatURLDropSurvivesModelRelaunch"] = saved && restored.activeID == originalID && restored.active?.draft == link.absoluteString && restored.draft == link.absoluteString && restored.hasInput

        let originalText = "Generated review kept exactly."
        restored.editDraft(originalText)
        restored.keepDroppedLinks([link])
        let appendedWithoutNewline = restored.draft == originalText + "\n" + link.absoluteString
        restored.editDraft(originalText + "\n")
        restored.keepDroppedLinks([link])
        results["workspaceDroppedURLPreservesDraftWithOneNewline"] = appendedWithoutNewline && restored.draft == originalText + "\n" + link.absoluteString && restored.active?.draft == restored.draft

        // The empty workspace's central New chat control now calls this same model action.
        // Verify its actual identity/data behavior without treating a direct call as a native click.
        restored.pasteImage(try Data(contentsOf: output.appendingPathComponent("fixtures/A.png")))
        let previousID = restored.activeID
        let previousDraft = restored.draft
        let previousFiles = restored.pendingFiles
        let previousBytes = try previousFiles.map { record -> Data in
            guard let fileStore = restored.fileStore else { throw AppError("Generated chat attachment store unavailable") }
            return try Data(contentsOf: fileStore.url(for: record))
        }
        restored.complete()
        let closedPreviousChat = restored.active == nil && restored.draft.isEmpty
        restored.newSession()
        let newID = restored.activeID
        let persisted = restored.persist()
        let retained = try SessionStore(directory: directory).load().first { $0.id == previousID }
        let retainedBytes = try (retained?.pendingAttachments ?? []).map { record -> Data in
            guard let fileStore = restored.fileStore else { throw AppError("Generated chat attachment store unavailable") }
            return try Data(contentsOf: fileStore.url(for: record))
        }
        results["workspaceClosedChatNewChatKeepsPriorDraftAndFiles"] = closedPreviousChat && newID != nil && newID != previousID && restored.active != nil && restored.draft.isEmpty && restored.pendingFiles.isEmpty && persisted && retained?.draft == previousDraft && !previousFiles.isEmpty && retained?.pendingAttachments.map(\.id) == previousFiles.map(\.id) && retainedBytes == previousBytes
    }
}

private final class AttachmentPageFault: @unchecked Sendable {
    private let lock = NSLock()
    private var denied = true
    func recover() { lock.lock(); denied = false; lock.unlock() }
    func remove(_ url: URL) throws {
        lock.lock(); let shouldDeny = denied && url.pathExtension == "pages"; lock.unlock()
        if shouldDeny { throw AppError("Generated attachment-page deletion denial") }
        try FileManager.default.removeItem(at: url)
    }
}

extension AppController {
    /// Generated native attachment bytes, private ownership and real deletion/retry; no personal library.
    func runMultipageAttachmentAcceptance(output: URL, results: inout [String: Bool]) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.tiff.identifier as CFString, 2, nil) else { throw AppError("Couldn’t create generated TIFF fixture") }
        for name in ["A.png", "B.png"] {
            guard let source = CGImageSourceCreateWithURL(output.appendingPathComponent("fixtures/" + name) as CFURL, nil) else { throw AppError("Missing generated image fixture") }
            CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        }
        guard CGImageDestinationFinalize(destination) else { throw AppError("Couldn’t finish generated TIFF fixture") }
        let directory = output.appendingPathComponent("multipage-fixture-" + UUID().uuidString)
        let fixture = AppModel(dataDirectory: directory)
        defer { fixture.suspend() }
        fixture.newSession(title: "Generated multi-page attachment")
        fixture.pasteImage(data as Data)
        guard let id = fixture.activeID, let record = fixture.active?.pendingAttachments.first, let files = fixture.fileStore else { throw AppError("Generated multi-page attachment import failed") }
        let primary = files.url(for: record), pages = primary.appendingPathExtension("pages")
        let context = try files.context(for: [record], leadingImages: 1)
        func privateFile(_ url: URL) -> Bool {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o600
        }
        results["attachmentMultipageBytesPrivateAndNumberedAfterWindow"] = privateFile(primary) && privateFile(pages) && context.images.count == 2 && context.text.contains("Image 2") && context.text.contains("Image 3")
        fixture.delete(id)
        results["attachmentMultipageForgetPurgesAllOwnedBytes"] = fixture.sessions.isEmpty && !FileManager.default.fileExists(atPath: primary.path) && !FileManager.default.fileExists(atPath: pages.path)

        let fault = AttachmentPageFault()
        let retry = AppModel(dataDirectory: directory.appendingPathComponent("retry"), fileRemoval: { try fault.remove($0) })
        defer { retry.suspend() }
        retry.newSession(title: "Generated sidecar deletion retry")
        retry.pasteImage(data as Data)
        guard let retryID = retry.activeID, let retryRecord = retry.active?.pendingAttachments.first, let retryFiles = retry.fileStore else { throw AppError("Generated retry attachment import failed") }
        let retryPrimary = retryFiles.url(for: retryRecord), retryPages = retryPrimary.appendingPathExtension("pages")
        retry.delete(retryID)
        results["attachmentMultipageDeletionFailureKeepsRetryableOwnership"] = retry.sessions.contains { $0.id == retryID } && retry.error != nil && FileManager.default.fileExists(atPath: retryPrimary.path) && FileManager.default.fileExists(atPath: retryPages.path)
        fault.recover(); retry.delete(retryID)
        results["attachmentMultipageRetryPurgesAllOwnedBytes"] = retry.sessions.isEmpty && retry.error == nil && !FileManager.default.fileExists(atPath: retryPrimary.path) && !FileManager.default.fileExists(atPath: retryPages.path)
    }
}

extension AppController {
    /// Real model/store transitions with a labeled generated provider adapter.
    func runCursorReplyAcceptance(output: URL, results: inout [String: Bool]) async throws {
        let directory = output.appendingPathComponent("cursor-reply-fixture-" + UUID().uuidString)
        let account = try await ChatGPTAccountChecks.makeSettingsFixture()
        let initial = try AppModel(testingAccount: account, dataDirectory: directory)
        initial.voice.enableFixtures()
        defer { initial.suspend() }
        initial.newSession(title: "Generated saved attachment-only retry")
        initial.pasteImage(try Data(contentsOf: output.appendingPathComponent("fixtures/A.png")))
        initial.provider.fixtureReply = { _, _, _, complete in complete(.failure(AppError("Generated provider refusal"))) }
        initial.send(); await until { !initial.busy }
        let failedChatID = initial.activeID, questionID = initial.active?.messages.last?.id
        initial.draft = "Keep this newer unsent draft."
        initial.pasteImage(try Data(contentsOf: output.appendingPathComponent("fixtures/B.png")))
        let pendingIDs = initial.pendingFiles.map(\.id)
        let pendingBytes = try initial.pendingFiles.map { try Data(contentsOf: initial.fileStore!.url(for: $0)) }
        initial.newSession(title: "Generated recovery navigation destination")
        let otherChatCannotRetry = !initial.canRetry
        if let failedChatID { initial.navigateToChat(failedChatID) }
        results["workspaceFailedQuestionRetryVisibleEnabledAfterNavigation"] = otherChatCannotRetry && initial.canRetry && initial.retryEnabled && initial.active?.messages.last?.id == questionID && initial.draft == "Keep this newer unsent draft." && initial.pendingFiles.map(\.id) == pendingIDs
        workspace.orderOut(nil)
        defer { workspace.makeKeyAndOrderFront(nil) }
        let navigationWindow = NativeWorkspaceWindow(model: initial)
        navigationWindow.appearance = NSAppearance(named: .darkAqua); navigationWindow.makeKeyAndOrderFront(nil)
        await settle()
        try snapshot(navigationWindow, to: output.appendingPathComponent("workspace-restored-failed-retry-navigation-dark-generated-account.png"), provenance: .generatedHarness(account: account))
        navigationWindow.close(); initial.persist(); initial.suspend()
        let restored = try AppModel(testingAccount: account, dataDirectory: directory)
        restored.voice.enableFixtures()
        defer { restored.suspend() }
        restored.prepareChat()
        // Reopen the persisted failed chat after the fresh model's normal launch selection.
        if let failedChatID { restored.navigateToChat(failedChatID) }
        let restoredWindow = NativeWorkspaceWindow(model: restored)
        defer { restoredWindow.close() }
        restoredWindow.appearance = NSAppearance(named: .darkAqua); restoredWindow.makeKeyAndOrderFront(nil)
        await settle()
        results["workspaceFailedQuestionRetryVisibleEnabledAfterRelaunch"] = !restored.hasFailedQuestion && restored.canRetry && restored.retryEnabled && restored.activeID == failedChatID && restored.active?.messages.last?.id == questionID
        try snapshot(restoredWindow, to: output.appendingPathComponent("workspace-restored-failed-retry-relaunch-dark-generated-account.png"), provenance: .generatedHarness(account: account))
        var retriedImages = 0, retryCalls = 0
        restored.provider.fixtureReply = { _, images, _, complete in retryCalls += 1; retriedImages = images.count; complete(.success(TutorReply(text: "Generated attachment retry answer."))) }
        let storeFile = directory.appendingPathComponent("sessions.json")
        let savedStore = try Data(contentsOf: storeFile)
        let originalQuestion = restored.active?.messages.last
        var storeFaultActive = true
        defer {
            if storeFaultActive { try? FileManager.default.removeItem(at: storeFile); try? savedStore.write(to: storeFile, options: .atomic) }
        }
        try FileManager.default.removeItem(at: storeFile)
        try FileManager.default.createDirectory(at: storeFile, withIntermediateDirectories: false)
        if restored.retryEnabled { restored.retry() }
        await settle()
        let keptDuringFault = originalQuestion?.answerFailed == true && originalQuestion?.id == questionID && !restored.busy && retryCalls == 0 && !restored.hasFailedQuestion && restored.canRetry && restored.retryEnabled && restored.error != nil && restored.active?.messages.last?.id == originalQuestion?.id && restored.active?.messages.last?.answerFailed == originalQuestion?.answerFailed && restored.active?.messages.last?.replyStopped == originalQuestion?.replyStopped && restored.active?.messages.filter { $0.role == "user" }.count == 1 && restored.draft == "Keep this newer unsent draft." && restored.pendingFiles.map(\.id) == pendingIDs
        try FileManager.default.removeItem(at: storeFile)
        try savedStore.write(to: storeFile, options: .atomic); storeFaultActive = false
        let recoveredSave = restored.persist()
        let recoveredQuestion = try SessionStore(directory: directory).load().first { $0.id == failedChatID }?.messages.last
        let keptPendingBytes = try restored.pendingFiles.map { try Data(contentsOf: restored.fileStore!.url(for: $0)) }
        results["workspaceRestoredRetrySaveFailureKeepsVisibleRecoveryAndOwnership"] = keptDuringFault && recoveredSave && recoveredQuestion?.id == questionID && recoveredQuestion?.answerFailed == true && restored.canRetry && restored.retryEnabled && retryCalls == 0 && keptPendingBytes == pendingBytes
        try snapshot(restoredWindow, to: output.appendingPathComponent("workspace-restored-failed-retry-save-recovered-dark-generated-account.png"), provenance: .generatedHarness(account: account))
        // The rendered Retry message uses this exact enabled gate and action.
        if restored.retryEnabled { restored.retry() }
        await until { !restored.busy }
        let retainedPendingBytes = try restored.pendingFiles.map { try Data(contentsOf: restored.fileStore!.url(for: $0)) }
        results["cursorSavedAttachmentOnlyRetryUsesOriginalFiles"] = restored.active?.messages.last?.text == "Generated attachment retry answer." && restored.active?.messages.filter { $0.role == "user" }.count == 1 && restored.active?.messages.first?.id == questionID && restored.active?.messages.first?.answerFailed == false && restored.active?.messages.first?.attachments.count == 1 && retryCalls == 1 && retriedImages == 1 && restored.draft == "Keep this newer unsent draft." && restored.pendingFiles.map(\.id) == pendingIDs && retainedPendingBytes == pendingBytes && !restored.canRetry
        restoredWindow.orderOut(nil)

        restored.newSession(title: "Generated stale-answer refresh")
        restored.updateActive { $0.messages = [Message(role: "user", text: "Which button?"), Message(role: "assistant", text: "Generated stale answer.", screenChanged: true)] }
        restored.draft = "Keep this unsent personal draft."
        restored.persist()
        var pending: ((Result<TutorReply, Error>) -> Void)?
        restored.provider.fixtureReply = { _, _, _, complete in pending = complete }
        restored.refreshAnswer(); await until { pending != nil }
        let staleReplacedBeforeReply = restored.busy && restored.active?.messages.count == 1 && restored.active?.messages.first?.text == "Which button?"
        pending?(.success(TutorReply(text: "Generated fresh answer.")))
        await until { !restored.busy }
        results["cursorStaleRefreshReplacesOnlyStaleAnswerAndKeepsDraft"] = staleReplacedBeforeReply && restored.active?.messages.count == 2 && restored.active?.messages.last?.text == "Generated fresh answer." && restored.draft == "Keep this unsent personal draft."
    }
}

extension AppController {
    /// Uses actual NSTextView editing/undo; generated provider adapter prevents any live request.
    func runNativeUndoAcceptance(editor: ComposerTextView, results: inout [String: Bool]) async {
        let previousAdapter = model.provider.fixtureReply
        defer { model.provider.fixtureReply = previousAdapter }
        model.provider.fixtureReply = { _, _, _, _ in }
        model.newSession(title: "Generated native undo origin"); await settle()
        editor.insertText("Generated draft before navigation", replacementRange: NSRange(location: 0, length: 0))
        await settle()
        let navigationHadUndo = editor.undoManager?.canUndo == true
        let oldID = model.activeID
        model.newSession(title: "Generated native undo destination"); await settle()
        results["workspaceNewChatDropsPriorDraftNativeUndo"] = navigationHadUndo && model.activeID != oldID && model.draft.isEmpty && editor.string.isEmpty && editor.undoManager?.canUndo != true
        editor.insertText("Generated question for native Undo", replacementRange: NSRange(location: 0, length: 0))
        await settle()
        let sendHadUndo = editor.undoManager?.canUndo == true
        model.send(); await settle()
        let sentUndoWasCleared = editor.undoManager?.canUndo != true
        if editor.undoManager?.canUndo == true { editor.undoManager?.undo() }
        await settle()
        results["workspaceSentQuestionCannotReturnThroughNativeUndo"] = sendHadUndo && sentUndoWasCleared && model.draft.isEmpty && editor.string.isEmpty && model.active?.messages.last?.role == "user"
        model.stopInteraction()
    }
}

extension AppController {
    /// Negative provenance uses only the generated window and never a personal account.
    func runCaptureProvenanceAcceptance(window: NSWindow, account: ChatGPTAccount, output: URL, results: inout [String: Bool]) throws {
        let directory = output.appendingPathComponent("private-provenance-checks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let unknown = directory.appendingPathComponent("unknown-default.png")
        try NativeWindowEvidence.capture(window, to: unknown)
        let nonfixture = NativeWindowEvidence.Provenance.classify(harness: true, disposable: false, accountless: false)
        let nongenerated = directory.appendingPathComponent("nonfixture-classification.png")
        try NativeWindowEvidence.capture(window, to: nongenerated, provenance: nonfixture)
        let generated = directory.appendingPathComponent("generated-fixture.png")
        try NativeWindowEvidence.capture(window, to: generated, provenance: .generatedHarness(account: account))
        func metadata(_ file: URL) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(contentsOf: file.appendingPathExtension("json"))) as? [String: Any] ?? [:]
        }
        let unknownMetadata = try metadata(unknown), nonfixtureMetadata = try metadata(nongenerated), generatedMetadata = try metadata(generated)
        results["nativeCaptureDefaultsUnknownAndNonfixtureStaysPrivate"] = unknownMetadata["generatedTestDataOnly"] as? Bool == false && unknownMetadata["publicArchiveEligible"] as? Bool == false && nonfixture == .unknown && nonfixtureMetadata["publicArchiveEligible"] as? Bool == false && NativeWindowEvidence.Provenance.classify(harness: false, disposable: true, accountless: true) == .unknown
        results["nativeCaptureExplicitDisposableAndAccountlessProvenance"] = generatedMetadata["generatedTestDataOnly"] as? Bool == true && generatedMetadata["captureProvenance"] as? String == "generated-disposable-fixture" && NativeWindowEvidence.Provenance.classify(harness: true, disposable: false, accountless: true) == .generatedAccountlessHarness
        results["nativeCaptureFilesAndSidecarsArePrivate"] = [unknown, nongenerated, generated].allSatisfy { file in
            [file, file.appendingPathExtension("json")].allSatisfy { item in
                let attributes = try? FileManager.default.attributesOfItem(atPath: item.path)
                return (attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o600
            }
        }
    }
}

@MainActor private final class WorkspaceImportFixtureGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var open = false
    func wait() async {
        if open { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { open = true; continuation?.resume(); continuation = nil }
}

extension AppController {
    /// Held generated imports render bounded loading states; the actual detached file work still runs.
    func runImportFeedbackAcceptance(output: URL, results: inout [String: Bool]) async throws {
        workspace.orderOut(nil)
        defer { workspace.makeKeyAndOrderFront(nil) }
        let account = try await ChatGPTAccountChecks.makeSettingsFixture()
        let directory = output.appendingPathComponent("import-feedback-fixture-" + UUID().uuidString)
        let fixture = try AppModel(testingAccount: account, dataDirectory: directory)
        fixture.voice.enableFixtures(); fixture.newSession(title: "Generated import owner")
        fixture.draft = "Owner draft stays editable."
        let ownerID = fixture.activeID
        let window = NativeWorkspaceWindow(model: fixture)
        defer { fixture.suspend(); window.close() }
        window.makeKeyAndOrderFront(nil)
        func capture(_ state: String) async throws {
            await settle()
            try snapshot(window, to: output.appendingPathComponent(state + ".png"), provenance: .generatedHarness(account: account))
        }
        func editor(in view: NSView) -> ComposerTextView? {
            if let input = view as? ComposerTextView { return input }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let gate = WorkspaceImportFixtureGate()
        defer { gate.release() }
        try fixture.installImportFixtureGate { await gate.wait() }
        let importing = Task { await fixture.importFiles([output.appendingPathComponent("fixtures/A.png"), output.appendingPathComponent("fixtures/Brief.pdf")]) }
        await until { fixture.importing }
        window.appearance = NSAppearance(named: .aqua)
        try await capture("workspace-import-chat-light-generated-account")
        if let input = window.contentView.flatMap({ editor(in: $0) }) {
            window.makeFirstResponder(input)
            input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
            input.insertText(" More while adding files.", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        await settle()
        let ownerDraft = "Owner draft stays editable. More while adding files."
        results["workspaceImportProgressKeepsNativeDraftingAvailable"] = fixture.importing && fixture.importOwnerID == ownerID && fixture.importStatus == "Adding files…" && fixture.pendingFiles.isEmpty && fixture.draft == ownerDraft && window.firstResponder === window.contentView.flatMap({ editor(in: $0) })
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(window.contentMinSize)
        try await capture("workspace-import-minimum-dark-generated-account")
        results["workspaceImportStatusUsesTrueMinimumFrame"] = workspaceMinimumIsValid(window, atMinimum: true)
        window.setContentSize(NSSize(width: 1040, height: 740))
        fixture.showInspector(.files)
        try await capture("workspace-import-files-dark-generated-account")
        fixture.openSettings()
        try await capture("workspace-import-covered-settings-dark-generated-account")
        let noImportStop = window.toolbar?.items.contains { $0.itemIdentifier.rawValue == "vale.stop" } == false
        let coveredStatus = window.toolbar?.items.first { $0.itemIdentifier.rawValue == "vale.activity" }?.toolTip == "Adding files…"
        fixture.newSession(title: "Generated other chat during import")
        let otherID = fixture.activeID
        fixture.draft = "Other chat draft stays here."
        window.appearance = NSAppearance(named: .aqua)
        try await capture("workspace-import-other-owner-chat-light-generated-account")
        fixture.showInspector(.files)
        try await capture("workspace-import-other-owner-files-light-generated-account")
        fixture.openSettings()
        try await capture("workspace-import-other-owner-settings-light-generated-account")
        results["workspaceImportCoveredAndOtherChatIdentifyOwnerWithoutFalseStop"] = noImportStop && coveredStatus && fixture.importing && fixture.importOwnerID == ownerID && fixture.importStatus == "Adding files to Generated import owner…" && window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "vale.activity" })?.toolTip == fixture.importStatus && window.toolbar?.items.contains(where: { $0.itemIdentifier.rawValue == "vale.stop" }) == false
        // Reconcile the hidden original window after every covered-route transition. Matching
        // NSToolbar identifiers previously let that other model remove this window's Back/status.
        var toolbarTrace: [[String: Any]] = []
        var coveredRouteChecks: [Bool] = [], backActionChecks: [Bool] = []
        func recordCoveredToolbar(_ state: String, expectedStatus: String) -> Bool {
            let toolbar = window.toolbar
            let back = toolbar?.items.first { $0.itemIdentifier.rawValue == "vale.back" }
            let activity = toolbar?.items.first { $0.itemIdentifier.rawValue == "vale.activity" }
            let label = activity?.view as? NSTextField
            let visible = toolbar?.visibleItems?.map { $0.itemIdentifier.rawValue } ?? []
            let sourceItems = workspace.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
            let isolated = toolbar != nil && workspace.toolbar != nil && toolbar?.identifier != workspace.toolbar?.identifier
            let passed = isolated && !workspace.isVisible && !sourceItems.contains("vale.back") && back?.isEnabled == true && back?.action != nil && visible.contains("vale.back") && visible.contains("vale.activity") && activity?.toolTip == expectedStatus && label?.stringValue == expectedStatus && label?.accessibilityLabel() == expectedStatus && activity?.menuFormRepresentation?.title == expectedStatus && toolbar?.items.contains(where: { $0.itemIdentifier.rawValue == "vale.stop" }) == false
            // Keep heterogeneous diagnostics in small typed assignments for the Swift compiler.
            var row: [String: Any] = [:]
            row["state"] = state
            row["passed"] = passed
            row["expectedStatus"] = expectedStatus
            row["windowTitle"] = window.title
            row["route"] = fixture.workspaceRoute.rawValue
            row["appearance"] = window.effectiveAppearance.name.rawValue
            row["frame"] = ["width": window.frame.width, "height": window.frame.height]
            row["sourceHidden"] = !workspace.isVisible
            row["identifiersAreDistinct"] = isolated
            row["sourceToolbarIdentifier"] = workspace.toolbar?.identifier ?? "none"
            row["fixtureToolbarIdentifier"] = toolbar?.identifier ?? "none"
            row["sourceItems"] = sourceItems
            row["fixtureItems"] = toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
            row["fixtureVisibleItems"] = visible
            row["activityTooltip"] = activity?.toolTip ?? "missing"
            row["activityText"] = label?.stringValue ?? "missing"
            row["activityAccessibilityLabel"] = label?.accessibilityLabel() ?? "missing"
            toolbarTrace.append(row)
            return passed
        }
        if let ownerID, let otherID {
            let hiddenSourceIsNormalChat = model.workspaceRoute == .chat && model.inspector == nil && !model.compactHistoryVisible
            for dark in [false, true] {
                for minimum in [false, true] {
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    window.setContentSize(minimum ? window.contentMinSize : NSSize(width: 1040, height: 740))
                    for chatID in [ownerID, otherID] {
                        fixture.navigateToChat(chatID)
                        let otherOwner = chatID == otherID
                        let expectedStatus = otherOwner ? "Adding files to Generated import owner…" : "Adding files…"
                        let ownerName = otherOwner ? "other-owner" : "owner"
                        let state = "\(ownerName)-\(minimum ? "minimum" : "default")-\(dark ? "dark" : "light")"
                        fixture.showInspector(.files); await settle()
                        model.composerFocus += 1; await settle()
                        coveredRouteChecks.append(hiddenSourceIsNormalChat && recordCoveredToolbar(state + "-files", expectedStatus: expectedStatus))
                        fixture.openSettings(); await settle()
                        model.composerFocus += 1; await settle()
                        coveredRouteChecks.append(recordCoveredToolbar(state + "-settings", expectedStatus: expectedStatus) && (!minimum || workspaceMinimumIsValid(window, atMinimum: true)))
                        if minimum { try await capture("workspace-import-repeat-\(ownerName)-settings-minimum-\(dark ? "dark" : "light")-generated-account") }
                        let back = window.toolbar?.items.first { $0.itemIdentifier.rawValue == "vale.back" }
                        let accepted: Bool
                        if let back, let action = back.action { accepted = NSApp.sendAction(action, to: back.target, from: back) }
                        else { accepted = false }
                        await settle()
                        let expectedDraft = otherOwner ? "Other chat draft stays here." : ownerDraft
                        let returned = accepted && fixture.workspaceRoute == .chat && fixture.inspector == nil && !fixture.compactHistoryVisible && fixture.activeID == chatID && fixture.draft == expectedDraft && window.firstResponder === window.contentView.flatMap({ editor(in: $0) })
                        backActionChecks.append(returned)
                        toolbarTrace.append(["state": state + "-back-action", "passed": returned, "actionAccepted": accepted])
                    }
                }
            }
            // Keep the original success/failure ownership precondition: the other chat is active.
            fixture.navigateToChat(otherID); fixture.openSettings(); await settle()
        }
        results["workspaceImportToolbarIsolatedAcrossOwnersRoutesSizesAndAppearances"] = coveredRouteChecks.count == 16 && coveredRouteChecks.allSatisfy { $0 }
        results["workspaceImportNativeBackReturnsToEachDraftAcrossRepeatedRoutes"] = backActionChecks.count == 8 && backActionChecks.allSatisfy { $0 }
        try JSONSerialization.data(withJSONObject: ["method": "generated native toolbar cross-window transition checks", "states": toolbarTrace], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("import-toolbar-transitions.json"), options: .atomic)
        gate.release(); await importing.value; await settle()
        let owner = fixture.sessions.first { $0.id == ownerID }
        let ownerRecords = owner?.pendingAttachments ?? []
        let persisted = try SessionStore(directory: directory).load()
        let savedOwner = persisted.first { $0.id == ownerID }, savedOther = persisted.first { $0.id == otherID }
        results["workspaceAsyncImportSuccessKeepsFilesAndBothDraftOwners"] = !fixture.importing && fixture.importOwnerID == nil && fixture.importStatus == nil && fixture.error == nil && ownerRecords.count == 2 && savedOwner?.pendingAttachments.map(\.id) == ownerRecords.map(\.id) && savedOwner?.draft == ownerDraft && savedOther?.draft == "Other chat draft stays here." && owner?.draft == ownerDraft && fixture.activeID == otherID && fixture.pendingFiles.isEmpty && fixture.draft == "Other chat draft stays here." && window.toolbar?.items.contains(where: { $0.itemIdentifier.rawValue == "vale.activity" }) == false
        // A second real asynchronous import fails on a generated nonexistent file.
        let failureGate = WorkspaceImportFixtureGate()
        defer { failureGate.release() }
        if let ownerID { fixture.navigateToChat(ownerID) }
        try fixture.installImportFixtureGate { await failureGate.wait() }
        let failing = Task { await fixture.importFiles([output.appendingPathComponent("fixtures/generated-missing-file.txt")]) }
        await until { fixture.importing }
        if let otherID { fixture.navigateToChat(otherID) }
        failureGate.release(); await failing.value; await settle()
        results["workspaceAsyncImportFailureReplacesProgressWithoutMovingFilesOrDraft"] = !fixture.importing && fixture.importOwnerID == nil && fixture.importStatus == nil && fixture.error?.contains("generated-missing-file.txt") == true && fixture.activeID == otherID && fixture.pendingFiles.isEmpty && fixture.draft == "Other chat draft stays here." && fixture.sessions.first(where: { $0.id == ownerID })?.pendingAttachments.map(\.id) == ownerRecords.map(\.id)
        fixture.backToChat(); window.appearance = NSAppearance(named: .darkAqua)
        try await capture("workspace-import-failure-dark-generated-account")
    }
}

extension AppController {
    /// Compare against the independent product floor and toolbar-aware geometry, not minSize alone.
    func workspaceMinimumIsValid(_ window: NSWindow, atMinimum: Bool = false) -> Bool {
        let floor = NativeWorkspaceWindow.minimumFrameSize
        let minimumContent = window.contentMinSize
        let expectedFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContent)).size
        let values = [minimumContent.width, minimumContent.height, expectedFrame.width, expectedFrame.height, window.minSize.width, window.minSize.height]
        guard values.allSatisfy({ $0.isFinite && $0 > 0 }),
              floor.width >= 740, floor.height >= 560,
              window.minSize.width >= floor.width, window.minSize.height >= floor.height,
              expectedFrame.width >= floor.width, expectedFrame.height >= floor.height else { return false }
        guard atMinimum else { return true }
        guard let actualContent = window.contentView?.bounds.size else { return false }
        return abs(actualContent.width - minimumContent.width) < 1 && abs(actualContent.height - minimumContent.height) < 1 && abs(window.frame.width - expectedFrame.width) < 1 && abs(window.frame.height - expectedFrame.height) < 1 && window.frame.width >= 740 && window.frame.height >= 560
    }
}
