import AppKit
import LiltCore

@MainActor private final class ManualHiddenCaptureGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var waiting = false

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation; waiting = true
        }
    }

    func release() {
        released = true
        let held = continuation; continuation = nil; held?.resume()
    }
}

extension AppController {
    /// Actual AppModel/manual-window races, with automatic context disabled and
    /// generated in-memory screen/provider/voice fixtures. No chooser or desktop
    /// capture is opened, and no physical input or hardware behavior is claimed.
    func runManualHiddenCaptureAcceptance(output: URL, results: inout [String: Bool]) async throws {
        guard CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") else {
            results["manualHiddenCaptureRequiresDisposableHarness"] = false; return
        }
        let account = try await ChatGPTAccountChecks.makeSettingsFixture()
        try await manualHiddenPreHandoff(account: account, output: output, results: &results)
        try await manualHiddenPostReply(account: account, output: output, results: &results)
        let evidence: [String: Any] = [
            "method": "production AppModel send/hide/retry with gated generated WindowContext capture and provider adapter",
            "automaticContextEnabled": false, "realScreenCaptureVerified": false,
            "realMicrophoneOrSpeechVerified": false, "permissionPromptsRequested": false,
            "realProviderInferenceVerified": false, "physicalInputOrCompositorVerified": false
        ]
        let file = output.appendingPathComponent("manual-hidden-capture-method.json")
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func manualHiddenPreHandoff(account: ChatGPTAccount, output: URL, results: inout [String: Bool]) async throws {
        let directory = output.appendingPathComponent("manual-hidden-prehandoff-fixture")
        let fixture = try AppModel(testingAccount: account, dataDirectory: directory)
        fixture.voice.enableFixtures(); fixture.newSession(title: "Generated manual hide before handoff")
        fixture.workspaceOpen = true
        let gate = ManualHiddenCaptureGate()
        defer { gate.release(); fixture.provider.fixtureReply = nil; fixture.suspend() }
        var captures = 0, providerCalls = 0
        var requestImages: [[Data]] = []
        fixture.context.installFixture {
            captures += 1
            let captured = captures
            if captured == 1 { await gate.wait() }
            return self.manualHiddenSnapshot(marker: "GENERATED-MANUAL-PREHANDOFF-\(captured)")
        }
        fixture.provider.fixtureReply = { _, images, _, complete in
            providerCalls += 1; requestImages.append(images)
            complete(.success(TutorReply(text: "Generated manual-window retry answer.")))
        }
        let question = "Keep this generated manual-window question for retry."
        fixture.draft = question; fixture.send()
        let questionID = fixture.active?.messages.last?.id
        await until { gate.waiting }
        let wasAssembling = gate.waiting && fixture.context.capturing && fixture.busy && !fixture.workContext.enabled
        fixture.draft = "Keep this newer unsent manual-window draft."
        fixture.companionDidHide(); fixture.workspaceOpen = false
        let suspendedImmediately = !fixture.context.capturing && !fixture.context.live &&
            fixture.context.latest == nil && fixture.context.lastCapture == nil && fixture.context.hasSelection && fixture.context.windowID == 42
        gate.release(); await settle()
        let saved = try SessionStore(directory: directory).load().first { $0.id == fixture.activeID }
        results["manualWindowHideBeforeHandoffRejectsLateCaptureWithAutomaticContextOff"] = wasAssembling && suspendedImmediately &&
            providerCalls == 0 && captures == 1 && !fixture.busy && fixture.canRetry && fixture.error != nil &&
            fixture.active?.messages.last?.id == questionID && fixture.active?.messages.last?.text == question &&
            fixture.active?.messages.last?.answerFailed == true && saved?.messages.last?.answerFailed == true &&
            fixture.draft == "Keep this newer unsent manual-window draft." && saved?.draft == fixture.draft &&
            !fixture.context.capturing && fixture.context.latest == nil && fixture.context.lastCapture == nil

        fixture.workspaceOpen = true
        fixture.retry(); await until { !fixture.busy }
        await settle()
        results["manualWindowAfterHideRetriesOriginalQuestionWithRetainedChoiceAndFreshPixels"] = !fixture.workContext.enabled &&
            providerCalls == 1 && requestImages == [[manualHiddenSnapshot(marker: "GENERATED-MANUAL-PREHANDOFF-2").data]] &&
            fixture.context.hasSelection && fixture.context.windowID == 42 && captures >= 2 &&
            fixture.active?.messages.first?.id == questionID && fixture.active?.messages.filter { $0.role == "user" }.count == 1 &&
            fixture.active?.messages.last?.role == "assistant" && !fixture.canRetry && fixture.error == nil &&
            fixture.draft == "Keep this newer unsent manual-window draft." && fixture.active?.draft == fixture.draft
    }

    private func manualHiddenPostReply(account: ChatGPTAccount, output: URL, results: inout [String: Bool]) async throws {
        let directory = output.appendingPathComponent("manual-hidden-postreply-fixture")
        let fixture = try AppModel(testingAccount: account, dataDirectory: directory)
        fixture.voice.enableFixtures(); fixture.newSession(title: "Generated manual hide during reply verification")
        fixture.workspaceOpen = true
        let gate = ManualHiddenCaptureGate()
        defer { gate.release(); fixture.provider.fixtureReply = nil; fixture.suspend() }
        var captures = 0, providerCalls = 0, points = 0
        var annotationVisible = false
        var pending: ((Result<TutorReply, Error>) -> Void)?
        var requestImages: [[Data]] = []
        let source = manualHiddenSnapshot(marker: "GENERATED-MANUAL-POSTREPLY")
        fixture.context.installFixture {
            captures += 1
            if captures == 2 { await gate.wait() }
            return source
        }
        fixture.showPoint = { _, _ in points += 1; annotationVisible = true }
        fixture.hideOverlay = { annotationVisible = false }
        fixture.provider.fixtureReply = { _, images, _, complete in
            providerCalls += 1; requestImages.append(images); pending = complete
        }
        fixture.draft = "Generated spoken manual-window question."
        fixture.send(spoken: true)
        await until { pending != nil }
        let handedOff = providerCalls == 1 && fixture.busy && captures == 1 && !fixture.workContext.enabled
        let reply = TutorReply(text: "Generated answer retained while its screen verification is cancelled.",
                              point: PointTarget(x: 0.2, y: 0.2, width: 0.3, height: 0.3, label: "Generated manual target"))
        pending?(.success(reply)); pending = nil
        await until { gate.waiting }
        let answerID = fixture.active?.messages.last?.id
        let verificationGeneration = fixture.context.generation
        let verificationStarted = gate.waiting && captures == 2 && fixture.context.capturing && fixture.active?.messages.last?.role == "assistant"
        fixture.draft = "Keep the generated draft beside the handed-off answer."
        fixture.companionDidHide(); fixture.workspaceOpen = false
        _ = fixture.persist()
        let suspendedImmediately = !fixture.context.capturing && !fixture.context.live && fixture.context.latest == nil &&
            fixture.context.lastCapture == nil && fixture.context.generation != verificationGeneration && fixture.context.hasSelection && fixture.context.windowID == 42
        // A rapid show must not make the old awaited verification current again.
        fixture.workspaceOpen = true
        gate.release(); await settle()
        let saved = try SessionStore(directory: directory).load().first { $0.id == fixture.activeID }
        results["manualWindowHideDuringPostReplyVerificationKeepsAnswerWithoutOverlayOrAudio"] = handedOff && verificationStarted &&
            suspendedImmediately && providerCalls == 1 && captures == 2 && points == 0 && !annotationVisible &&
            !fixture.context.capturing && fixture.context.latest == nil && fixture.context.lastCapture == nil &&
            !fixture.voice.listening && !fixture.voice.starting && !fixture.voice.speaking && !fixture.conversation &&
            fixture.active?.messages.last?.id == answerID && fixture.active?.messages.last?.text == reply.text &&
            saved?.messages.last?.id == answerID && saved?.messages.last?.text == reply.text && saved?.draft == fixture.draft

        fixture.provider.fixtureReply = { _, images, _, complete in
            providerCalls += 1; requestImages.append(images)
            complete(.success(TutorReply(text: "Generated next question uses the retained explicit window.")))
        }
        fixture.draft = "Generated next question after showing Vale again."
        fixture.send(); await until { !fixture.busy }
        await settle()
        results["manualWindowPostReplyHideRetainsChoiceForNextExplicitQuestion"] = !fixture.workContext.enabled &&
            providerCalls == 2 && requestImages == [[source.data], [source.data]] && captures >= 3 &&
            fixture.context.hasSelection && fixture.context.windowID == 42 && fixture.active?.messages.last?.role == "assistant" &&
            fixture.active?.messages.last?.text == "Generated next question uses the retained explicit window." && fixture.error == nil
    }

    private func manualHiddenSnapshot(marker: String) -> ContextSnapshot {
        ContextSnapshot(data: Data(marker.utf8), image: NSImage(size: NSSize(width: 2, height: 2)), windowID: 42,
                        frame: CGRect(x: 100, y: 100, width: 400, height: 260), generation: UUID(), capturedAt: Date())
    }
}
