import AppKit
import LiltCore

@MainActor private final class CurrentWorkIntegrationGate {
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

private struct CurrentWorkIntegrationRequest {
    let prompt: String
    let images: [Data]
}

extension AppController {
    /// AppModel → prompt/images → fixture provider integration, with generated
    /// storage, screen and selection data. No windows or real sensing are used.
    func runCurrentWorkIntegrationAcceptance(output: URL, results: inout [String: Bool]) async throws {
        guard CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") else {
            results["currentWorkIntegrationRequiresDisposableHarness"] = false; return
        }
        let account = try await ChatGPTAccountChecks.makeSettingsFixture()
        let directory = output.appendingPathComponent("current-work-integration-fixture")
        _ = try SessionStore(directory: directory)
        let legacy = LearningSession(title: "Generated context migration seed", mode: .assistant)
        guard var rows = try JSONSerialization.jsonObject(with: JSONEncoder().encode([legacy])) as? [[String: Any]] else {
            throw AppError("Generated context integration seed could not be encoded.")
        }
        for index in rows.indices { rows[index].removeValue(forKey: "mode") }
        try JSONSerialization.data(withJSONObject: rows).write(to: directory.appendingPathComponent("sessions.json"), options: .atomic)
        let fixture = try AppModel(testingAccount: account, dataDirectory: directory)
        fixture.voice.enableFixtures(); fixture.newSession(title: "Generated current work requests")
        defer { fixture.provider.fixtureReply = nil; fixture.suspend() }

        var requests: [CurrentWorkIntegrationRequest] = []
        fixture.provider.fixtureReply = { prompt, images, _, complete in
            requests.append(.init(prompt: prompt, images: images))
            complete(.success(TutorReply(text: "Generated integration answer \(requests.count).")))
        }
        var selection = "GENERATED-INVOCATION-SELECTION-STALE"
        let firstSelection = "GENERATED-FRESH-SELECTION-ALPHA-731"
        let secondSelection = "GENERATED-FRESH-SELECTION-BETA-732"
        var captures = 0
        fixture.workContext.installFixture(selection: { .init(text: selection) }, capture: {
            captures += 1
            return self.currentWorkIntegrationSnapshot(marker: "GENERATED-AUTO-SCREEN-\(captures)")
        })
        fixture.workContext.prepareInvocation()
        selection = firstSelection
        fixture.draft = "Generated first current-work question."
        fixture.send(); await until { !fixture.busy }
        selection = secondSelection
        fixture.draft = "Generated follow-up current-work question."
        fixture.send(); await until { !fixture.busy }
        results["currentWorkModelHandsFreshQuestionScreenAndSelectionToProvider"] = requests.count == 2 && captures == 2 &&
            requests[0].images == [currentWorkIntegrationSnapshot(marker: "GENERATED-AUTO-SCREEN-1").data] &&
            requests[1].images == [currentWorkIntegrationSnapshot(marker: "GENERATED-AUTO-SCREEN-2").data] &&
            requests[0].prompt.contains(firstSelection) && !requests[0].prompt.contains("GENERATED-INVOCATION-SELECTION-STALE") &&
            requests[1].prompt.contains(secondSelection) && !requests[1].prompt.contains(firstSelection) &&
            requests.allSatisfy { $0.prompt.contains("current display, excluding Vale") && $0.prompt.contains("<selection>") } &&
            fixture.active?.messages.filter { $0.role == "assistant" }.count == 2 && !fixture.workContext.hasSelectionText

        _ = fixture.persist()
        let backup = directory.appendingPathComponent("sessions-v1-backup.json")
        let stored = try Data(contentsOf: directory.appendingPathComponent("sessions.json"))
        let migration = try Data(contentsOf: backup)
        let inMemory = try JSONEncoder().encode(fixture.sessions)
        let transientMarkers = [firstSelection, secondSelection, "GENERATED-INVOCATION-SELECTION-STALE", "GENERATED-AUTO-SCREEN-1", "GENERATED-AUTO-SCREEN-2"]
        let persistedTexts = [stored, migration, inMemory].map { String(decoding: $0, as: UTF8.self) }
        let storedChat = try SessionStore(directory: directory).load().first { $0.id == fixture.activeID }
        results["currentWorkModelDoesNotPersistSelectionOrScreenshotInSessionsOrBackup"] =
            transientMarkers.allSatisfy { marker in persistedTexts.allSatisfy { !$0.contains(marker) && !$0.contains(Data(marker.utf8).base64EncodedString()) } } &&
            storedChat?.messages.count == 4 &&
            !fixture.workContext.hasSelectionText && fixture.context.latest == nil && !migration.isEmpty

        let manualSelection = "GENERATED-MANUAL-WINDOW-SELECTION-733"
        let manualSnapshot = currentWorkIntegrationSnapshot(marker: "GENERATED-EXPLICIT-WINDOW-733", windowID: 42)
        let autoCapturesBeforeManual = captures
        var manualCaptures = 0
        fixture.context.installFixture {
            manualCaptures += 1
            return manualSnapshot
        }
        selection = manualSelection
        fixture.draft = "Generated explicit-window question."
        fixture.send(); await until { !fixture.busy }
        let manualRequest = requests.last
        results["currentWorkModelExplicitWindowOverridesAutoScreenAndKeepsSelection"] = requests.count == 3 &&
            captures == autoCapturesBeforeManual && manualCaptures >= 1 && manualRequest?.images == [manualSnapshot.data] &&
            manualRequest?.prompt.contains("fresh selected-window screenshot") == true &&
            manualRequest?.prompt.contains("current display, excluding Vale") == false &&
            manualRequest?.prompt.contains(manualSelection) == true && !fixture.workContext.hasSelectionText
        await settle()
        fixture.context.stop()

        var deniedCaptures = 0
        let deniedSelection = "GENERATED-DENIED-SCREEN-SELECTION-734"
        fixture.workContext.installFixture(screenAuthorized: false, selection: { .init(text: deniedSelection) }, capture: {
            deniedCaptures += 1
            return self.currentWorkIntegrationSnapshot(marker: "GENERATED-FORBIDDEN-SCREEN")
        })
        fixture.draft = "Generated typed question with screen permission off."
        fixture.send(); await until { !fixture.busy }
        let selectionOnly = requests.last
        fixture.workContext.installFixture(screenAuthorized: false, selectionAuthorized: false, selection: { .init(text: deniedSelection) }, capture: {
            deniedCaptures += 1
            return self.currentWorkIntegrationSnapshot(marker: "GENERATED-FORBIDDEN-SCREEN")
        })
        fixture.draft = "Generated typed question with both context permissions off."
        fixture.send(); await until { !fixture.busy }
        let typedOnly = requests.last
        results["currentWorkModelDeniedScreenStillSendsTypedPromptWithOptionalSelection"] = requests.count == 5 && deniedCaptures == 0 &&
            selectionOnly?.images.isEmpty == true && selectionOnly?.prompt.contains(deniedSelection) == true &&
            selectionOnly?.prompt.contains("Generated typed question with screen permission off.") == true &&
            selectionOnly?.prompt.contains("Screen not included. Allow Screen Recording in Settings.") == true &&
            typedOnly?.images.isEmpty == true && typedOnly?.prompt.contains(deniedSelection) == false &&
            typedOnly?.prompt.contains("Generated typed question with both context permissions off.") == true &&
            typedOnly?.prompt.contains("No screen image is attached") == true && fixture.error == nil && !fixture.busy

        for failure in ["Error", "Timeout"] {
            try await currentWorkIntegrationCaptureUnavailable(failure, account: account, output: output, results: &results)
        }
        for invalidation in ["Disable", "SourceChange", "Hide"] {
            try await currentWorkIntegrationInvalidation(invalidation, account: account, output: output, results: &results)
        }
        let evidence: [String: Any] = [
            "method": "production AppModel.send/retry, generated account/context, fixture provider prompt/image observations and disposable persisted chats",
            "providerRequestsVerified": "generated adapter only", "realAccountOrInferenceVerified": false,
            "realScreenCaptureVerified": false, "realAccessibilitySelectionVerified": false,
            "permissionPromptsRequested": false, "nativeGUIOrPhysicalInputVerified": false
        ]
        let file = output.appendingPathComponent("current-work-integration-method.json")
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func currentWorkIntegrationCaptureUnavailable(_ failure: String, account: ChatGPTAccount, output: URL, results: inout [String: Bool]) async throws {
        let directory = output.appendingPathComponent("current-work-unavailable-\(failure.lowercased())-integration-fixture")
        let fixture = try AppModel(testingAccount: account, dataDirectory: directory)
        fixture.voice.enableFixtures(); fixture.newSession(title: "Generated authorized screen \(failure)")
        let gate = CurrentWorkIntegrationGate()
        defer { gate.release(); fixture.provider.fixtureReply = nil; fixture.suspend() }
        let selectedText = "GENERATED-AUTHORIZED-\(failure.uppercased())-SELECTION"
        let staleImage = currentWorkIntegrationSnapshot(marker: "GENERATED-LATE-UNAVAILABLE-\(failure.uppercased())-SCREEN")
        var captures = 0
        fixture.workContext.installFixture(screenAuthorized: true, timeout: failure == "Timeout" ? 0.05 : 6,
                                           selection: { .init(text: selectedText) }, capture: {
            captures += 1
            if failure == "Error" { throw AppError("Generated authorized SDK capture failure") }
            await gate.wait()
            return staleImage
        })
        var requests: [CurrentWorkIntegrationRequest] = []
        fixture.provider.fixtureReply = { prompt, images, _, complete in
            requests.append(.init(prompt: prompt, images: images))
            complete(.success(TutorReply(text: "Generated answer without current-screen context.")))
        }
        let question = "Generated typed question despite authorized capture \(failure.lowercased())."
        let start = Date()
        fixture.draft = question; fixture.send()
        await until({ !fixture.busy }, seconds: 2)
        let request = requests.first
        let notice = "Current screen unavailable for this question. Use only the supplied selection and attachments."
        results["currentWorkModelAuthorized\(failure)StillSendsExactlyOneQuestionWithoutScreen"] = captures == 1 && requests.count == 1 &&
            request?.images.isEmpty == true && request?.prompt.contains(question) == true && request?.prompt.contains(selectedText) == true &&
            request?.prompt.contains("Context availability: " + notice) == true &&
            request?.prompt.contains("No screen image is attached. Do not imply you can see the screen.") == true &&
            request?.prompt.contains("fresh selected-window screenshot") == false && request?.prompt.contains("current display, excluding Vale") == false &&
            fixture.workContext.screenAuthorized && fixture.workContext.screenUnavailable && !fixture.workContext.hasSelectionText && !fixture.workContext.capturing &&
            !fixture.busy && fixture.error == nil && !fixture.hasFailedQuestion && !fixture.canRetry &&
            fixture.active?.messages.filter({ $0.role == "user" }).count == 1 && fixture.active?.messages.last?.role == "assistant" &&
            fixture.active?.messages.contains(where: { $0.answerFailed }) == false && Date().timeIntervalSince(start) < 2 &&
            (failure != "Timeout" || gate.waiting)

        if failure == "Timeout" {
            let generationAfterQuestion = fixture.workContext.generation
            let messagesAfterQuestion = fixture.active?.messages
            gate.release()
            await settle()
            results["currentWorkModelAuthorizedTimeoutLateFrameNeverReachesProviderOrChangesAnswer"] = requests.count == 1 && captures == 1 &&
                requests.allSatisfy { $0.images.isEmpty && !$0.images.contains(staleImage.data) } &&
                fixture.workContext.isCurrent(generationAfterQuestion) && fixture.workContext.screenUnavailable && !fixture.workContext.capturing &&
                fixture.active?.messages == messagesAfterQuestion && !fixture.busy && fixture.error == nil && !fixture.hasFailedQuestion && !fixture.canRetry
        }
    }

    private func currentWorkIntegrationInvalidation(_ invalidation: String, account: ChatGPTAccount, output: URL, results: inout [String: Bool]) async throws {
        let directory = output.appendingPathComponent("current-work-\(invalidation.lowercased())-integration-fixture")
        let fixture = try AppModel(testingAccount: account, dataDirectory: directory)
        fixture.voice.enableFixtures(); fixture.newSession(title: "Generated in-flight \(invalidation)")
        let gate = CurrentWorkIntegrationGate()
        defer { gate.release(); fixture.provider.fixtureReply = nil; fixture.suspend() }
        let staleSelection = "GENERATED-STALE-\(invalidation.uppercased())-SELECTION"
        let staleImage = currentWorkIntegrationSnapshot(marker: "GENERATED-STALE-\(invalidation.uppercased())-SCREEN")
        fixture.workContext.installFixture(selection: { .init(text: staleSelection) }, capture: {
            await gate.wait()
            return staleImage
        })
        var requests: [CurrentWorkIntegrationRequest] = []
        fixture.provider.fixtureReply = { prompt, images, _, complete in
            requests.append(.init(prompt: prompt, images: images))
            complete(.success(TutorReply(text: "Generated \(invalidation) retry answer.")))
        }
        let question = "Keep the generated \(invalidation) question available for retry."
        fixture.draft = question; fixture.send()
        let questionID = fixture.active?.messages.last?.id
        await until { gate.waiting }
        let captureStarted = gate.waiting && fixture.workContext.capturing && fixture.busy
        let newerDraft = "Keep the newer unsent \(invalidation) draft."
        fixture.draft = newerDraft
        switch invalidation {
        case "Disable": fixture.workContext.setEnabled(false)
        case "SourceChange": fixture.workContext.activateFixtureSource(processID: 2_000_074, name: "Generated replacement source")
        default: fixture.companionDidHide(); fixture.workspaceOpen = false
        }
        gate.release()
        await until { !fixture.busy }
        let saved = try SessionStore(directory: directory).load().first { $0.id == fixture.activeID }
        results["currentWorkModel\(invalidation)DuringCaptureNeverHandsStaleRequestToProvider"] = captureStarted && requests.isEmpty &&
            !fixture.busy && !fixture.workContext.capturing && !fixture.workContext.hasSelectionText &&
            fixture.canRetry && fixture.active?.messages.last?.id == questionID && fixture.active?.messages.last?.text == question &&
            fixture.active?.messages.last?.answerFailed == true && fixture.draft == newerDraft &&
            saved?.messages.last?.answerFailed == true && saved?.draft == newerDraft

        let freshSelection = "GENERATED-FRESH-\(invalidation.uppercased())-RETRY-SELECTION"
        let freshImage = currentWorkIntegrationSnapshot(marker: "GENERATED-FRESH-\(invalidation.uppercased())-RETRY-SCREEN")
        if invalidation != "Disable" {
            fixture.workContext.installFixture(selection: { .init(text: freshSelection) }, capture: { freshImage })
            fixture.workContext.prepareInvocation()
        }
        fixture.workspaceOpen = true
        fixture.retry(); await until { !fixture.busy }
        let request = requests.last
        let freshContext = invalidation == "Disable"
            ? request?.images.isEmpty == true && request?.prompt.contains(freshSelection) == false
            : request?.images == [freshImage.data] && request?.prompt.contains(freshSelection) == true
        results["currentWorkModel\(invalidation)RetryUsesFreshContextAndOriginalQuestion"] = requests.count == 1 && freshContext &&
            request?.prompt.contains(staleSelection) == false && request?.images.contains(staleImage.data) == false &&
            request?.prompt.contains(question) == true && fixture.active?.messages.first?.id == questionID &&
            fixture.active?.messages.filter { $0.role == "user" }.count == 1 && fixture.active?.messages.last?.role == "assistant" &&
            fixture.draft == newerDraft && fixture.active?.draft == newerDraft && !fixture.canRetry && fixture.error == nil
    }

    private func currentWorkIntegrationSnapshot(marker: String, windowID: CGWindowID? = nil) -> ContextSnapshot {
        // Marker bytes are intentionally synthetic fixture input, not a PNG read
        // from any desktop. The provider adapter observes these same RAM bytes.
        ContextSnapshot(data: Data(marker.utf8), image: NSImage(size: NSSize(width: 2, height: 2)), windowID: windowID,
                        frame: CGRect(x: 100, y: 100, width: 400, height: 260), generation: UUID(), capturedAt: Date())
    }
}
