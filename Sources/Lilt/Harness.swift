import AppKit
import LiltCore

extension AppController {
    func snapshot(_ window: NSWindow, to file: URL) throws {
        guard let view = window.contentView else { throw AppError("Missing content view") }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw AppError("Couldn’t render native view") }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw AppError("Couldn’t encode native view") }
        try data.write(to: file)
    }
    func settle() async { try? await Task.sleep(nanoseconds: 650_000_000) }
    func runHarness() async {
        let output = URL(fileURLWithPath: CommandLine.arguments.last!)
        var results: [String: Bool] = [:]
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            model.sessions = []; model.activeID = nil; model.selectedID = nil
            model.onboarding = true; openLibrary(); await settle()
            try snapshot(library, to: output.appendingPathComponent("01-welcome.png"))
            model.onboarding = false; await settle()
            try snapshot(library, to: output.appendingPathComponent("02-library-empty.png"))
            model.newSession(title: "LeetCode"); await settle()
            results["learningKeepsLibraryOutOfTheWay"] = !library.isVisible
            try snapshot(capsule, to: output.appendingPathComponent("03-capsule.png"))
            try snapshot(coach, to: output.appendingPathComponent("04-coach-empty.png"))
            func findEditor(_ view: NSView) -> ComposerTextView? {
                if let editor = view as? ComposerTextView { return editor }
                for child in view.subviews { if let found = findEditor(child) { return found } }; return nil
            }
            let editor = findEditor(coach.contentView!)
            results["composerGetsKeyboardFocus"] = coach.firstResponder === editor
            model.draft = "First line"
            await settle()
            if let editor, let shiftReturn = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0, windowNumber: coach.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
                editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0)); editor.keyDown(with: shiftReturn)
                results["shiftReturnAddsNewline"] = model.draft.contains("\n")
            }
            model.send("Cancellation probe"); model.cancel()
            await settle()
            results["cancelDiscardsPendingCompletion"] = !model.busy && model.active?.messages.last?.role == "user"
            model.updateActive { $0.messages = [] }
            model.draft = "Why does a stack fit this problem?"
            await settle(); try snapshot(coach, to: output.appendingPathComponent("05-typing.png"))
            model.togglePause(); results["pausePreservesDraft"] = model.draft == "Why does a stack fit this problem?"
            results["pauseStopsMicAndSharing"] = !model.voice.listening && model.context.filter == nil && !model.busy
            await settle(); try snapshot(coach, to: output.appendingPathComponent("06-paused.png"))
            model.togglePause(); results["resumePreservesDraft"] = !model.paused && !model.draft.isEmpty
            if CommandLine.arguments.contains("--integration-test") {
                if let editor, let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: coach.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) { editor.keyDown(with: enter) }
                results["returnSendsQuestion"] = model.active?.messages.last?.role == "user" && model.draft.isEmpty
                let start = Date()
                while model.busy && Date().timeIntervalSince(start) < 155 { try? await Task.sleep(nanoseconds: 200_000_000) }
                results["realTutorReply"] = model.active?.messages.last?.role == "assistant"
                results["replyIsNotEmpty"] = model.active?.messages.last?.text.isEmpty == false
                await settle(); try snapshot(coach, to: output.appendingPathComponent("07-real-tutor-reply.png"))
                let image = try Data(contentsOf: output.appendingPathComponent("07-real-tutor-reply.png"))
                let vision = TutorProvider()
                let answer: Result<TutorReply, Error> = await withCheckedContinuation { continuation in
                    vision.ask(prompt: "Read the learner question in this attached screenshot of Lilt. Which data structure is it about? Answer in five words or fewer. Return null for point.", image: image) { continuation.resume(returning: $0) }
                }
                if case .success(let reply) = answer { results["realImageInput"] = reply.text.lowercased().contains("stack") }
                else { results["realImageInput"] = false }
            } else {
                model.updateActive { $0.messages = [Message(role: "user", text: "Why does a stack fit this problem?"), Message(role: "assistant", text: "When you find a closing bracket, which unmatched opening bracket should it pair with: the earliest one or the most recent one?")] }
                model.draft = "The most recent one, so last in, first out?"
                await settle(); try snapshot(coach, to: output.appendingPathComponent("07-conversation-fixture.png"))
            }
            model.draft = "A draft to preserve"
            model.persist()
            let id = model.activeID!
            model.complete(); results["completionHidesFloatingWindows"] = !coach.isVisible && !capsule.isVisible; results["completeSavesSession"] = model.sessions.first?.completed == true
            model.setTakeaway("Match the most recent unmatched opening bracket first.", for: id)
            model.persist(); await settle(); try snapshot(library, to: output.appendingPathComponent("08-session-review.png"))
            model.resume(id); results["resumeRestoresDraft"] = model.draft == "A draft to preserve"
            model.showLibrary?(); model.settings = true; await settle(); try snapshot(library, to: output.appendingPathComponent("09-settings.png"))
            model.error = "The tutor connection stopped. Check your sign-in, then retry."; openCoach(); await settle()
            try snapshot(coach, to: output.appendingPathComponent("10-recovery.png"))
            results["librarySizeIsStable"] = library.contentView?.bounds.size == NSSize(width: 900, height: 650)
            results["nativeWindowsHaveExpectedSizes"] = capsule.frame.size == NSSize(width: 430, height: 62) && coach.frame.size == NSSize(width: 410, height: 480)
            results["sessionStoreRoundTrip"] = (try? SessionStore(directory: output.appendingPathComponent("test-library")).load().first?.draft) == "A draft to preserve"
            let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("results.json"))
            print(String(data: data, encoding: .utf8)!)
            model.suspend()
            exit(results.values.allSatisfy { $0 } ? 0 : 1)
        } catch { print("Harness failed: \(error)"); exit(1) }
    }
}
