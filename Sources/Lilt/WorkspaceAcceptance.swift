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
        model.newSession(title: "Workspace continuity fixture")
        workspace.appearance = NSAppearance(named: .aqua)
        workspace.setContentSize(NSSize(width: 1040, height: 740))
        model.sidebarVisible = true; model.compactHistoryVisible = false
        openWorkspace()
        try await capture("workspace-01-empty-light")
        results["workspaceOneWindowAtLaunch"] = oneWorkspace()
        let emptyEditor = workspace.contentView.flatMap { composer(in: $0) }

        let fixtureFiles = [output.appendingPathComponent("fixtures/A.png"), output.appendingPathComponent("fixtures/Brief.pdf")]
        await model.importFiles(fixtureFiles)
        model.draft = "My unsent review, kept while I check the details."
        model.updateActive { chat in
            chat.messages = [
                Message(role: "user", text: "Compare the diagrams and summarize the planning notes."),
                Message(role: "assistant", text: "The first diagram contains a red circle; the second has a blue square.\n\nThe public PDF fixture includes the verification token **HARBOR-73**. Keep that token with the brief, then turn the notes into a short checklist.\n\nYou can keep the supporting details in this chat’s notes and return to this draft when you are ready.")
            ]
            chat.takeaway = "Public fixture note: compare the shapes, retain HARBOR-73, and bring a notebook."
        }
        model.persist(); await settle()
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
        workspace.setContentSize(NSSize(width: 740, height: 560)); model.compactHistoryVisible = false
        try await capture("workspace-10-compact-chat")
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

        model.persist(); let readyBeforeClose = !model.paused
        workspace.performClose(nil); await settle()
        results["workspaceCloseStopsTransientActivityAndPreservesDraft"] = !workspace.isVisible && !model.voice.listening && !model.voice.speaking && !model.context.hasSelection && model.draft == composedDraft
        openWorkspace(); await settle()
        results["workspaceReopenKeepsTypingAndOneWindow"] = oneWorkspace() && model.activeID == originalID && model.draft == composedDraft && (!readyBeforeClose || !model.paused) && !model.voice.listening && !model.context.hasSelection
        let loaded = try SessionStore(directory: output.appendingPathComponent("test-library")).load().first(where: { $0.id == originalID })
        results["workspaceNavigationPersistsDraftNotesAndFiles"] = loaded?.draft == composedDraft && loaded?.pendingAttachments.map(\.id) == pendingIDs && loaded?.takeaway.contains("HARBOR-73") == true
        try runMultipageAttachmentAcceptance(output: output, results: &results)
        try await runCursorReplyAcceptance(output: output, results: &results)
        await runNativeUndoAcceptance(editor: editor, results: &results)
        try runClosedChatInputAcceptance(output: output, results: &results)
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
        let initial = AppModel(dataDirectory: directory)
        initial.voice.enableFixtures()
        defer { initial.suspend() }
        initial.newSession(title: "Generated saved attachment-only retry")
        initial.pasteImage(try Data(contentsOf: output.appendingPathComponent("fixtures/A.png")))
        initial.provider.fixtureReply = { _, _, _, complete in complete(.failure(AppError("Generated provider refusal"))) }
        initial.send(); await until { !initial.busy }
        initial.persist(); initial.suspend()
        let restored = AppModel(dataDirectory: directory)
        restored.voice.enableFixtures()
        defer { restored.suspend() }
        restored.prepareChat()
        let questionID = restored.active?.messages.last?.id
        var retriedImages = 0
        restored.provider.fixtureReply = { _, images, _, complete in retriedImages = images.count; complete(.success(TutorReply(text: "Generated attachment retry answer."))) }
        restored.retry(); await until { !restored.busy }
        results["cursorSavedAttachmentOnlyRetryUsesOriginalFiles"] = restored.active?.messages.last?.text == "Generated attachment retry answer." && restored.active?.messages.filter { $0.role == "user" }.count == 1 && restored.active?.messages.first?.id == questionID && restored.active?.messages.first?.answerFailed == false && restored.active?.messages.first?.attachments.count == 1 && retriedImages == 1

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
