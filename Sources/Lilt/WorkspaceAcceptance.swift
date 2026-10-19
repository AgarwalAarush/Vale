import AppKit
import SwiftUI
import LiltCore

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
        editor.setSelectedRange(NSRange(location: 3, length: 5))
        let selection = editor.selectedRange()
        try await capture("workspace-02-conversation-light")

        model.openSettings(); await settle()
        results["workspaceSettingsPreserveDraftFilesAndEditor"] = oneWorkspace() && model.workspaceRoute == .settings && model.activeID == originalID && model.draft == savedDraft && model.pendingFiles.map(\.id) == pendingIDs && workspace.contentView.flatMap({ composer(in: $0) }) === editor && editor.selectedRange() == selection
        try await capture("workspace-03-settings-light")
        model.setConversation(true); await settle()
        results["workspaceSettingsRetainsExplicitActivityUntilStopped"] = model.workspaceRoute == .settings && model.conversation && model.voice.listening && model.draft == savedDraft
        try await capture("workspace-03b-settings-active-voice")
        model.stopInteraction(); await settle()
        results["workspaceStopFromCoveredChatClearsActivityAndKeepsDraft"] = model.workspaceRoute == .settings && !model.conversation && !model.voice.listening && !model.context.hasSelection && model.draft == savedDraft
        model.backToChat(); await settle()
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
    }
}
