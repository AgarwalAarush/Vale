import AppKit

/// Generated app-owned context only. These checks never access AX, NSWorkspace, SCK, or a personal screen.
@MainActor enum CurrentWorkContextChecks {
    static func run() async -> [String: Bool] {
        guard CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") else { return [:] }
        var results: [String: Bool] = [:]
        let ordinaryFixture = CurrentWorkContext(isTesting: true)
        ordinaryFixture.prepareInvocation()
        ordinaryFixture.refreshPermissions()
        ordinaryFixture.requestScreenAccess(); ordinaryFixture.requestSelectionAccess()
        results["currentWorkHarnessStartsDisabledWithoutRealSensing"] = !ordinaryFixture.enabled && !ordinaryFixture.screenAuthorized && !ordinaryFixture.selectionAuthorized && ordinaryFixture.sourceName == nil

        do {
            let context = CurrentWorkContext(isTesting: true)
            var captures = 0, reads = 0
            var selectionText = "Generated first selection"
            context.installFixture(selection: { reads += 1; return .init(text: selectionText) }, capture: {
                captures += 1; return snapshot(byte: UInt8(captures))
            })
            context.prepareInvocation()
            let readsAtInvocation = reads
            selectionText = "Generated current selection"
            let first = try await context.captureForQuestion()
            let firstIsCurrent = context.isCurrent(first.generation)
            selectionText = "Generated follow-up selection"
            let second = try await context.captureForQuestion()
            results["currentWorkRefreshesScreenshotAndSelectionPerQuestion"] = captures == 2 && reads == readsAtInvocation + 2 && first.screen?.data != second.screen?.data && first.selectedText == "Generated current selection" && second.selectedText == "Generated follow-up selection" && first.generation != second.generation && firstIsCurrent && !context.isCurrent(first.generation) && context.isCurrent(second.generation)
            results["currentWorkQuestionScreenHasNoWindowIdentityOrRetainedSelection"] = first.screen?.windowID == nil && first.screen?.generation == first.generation && second.screen?.generation == second.generation && !context.hasSelectionText

            context.prepareInvocation()
            let preparedReads = reads
            let rememberedSource = context.sourceName
            context.activateFixtureSource(processID: ProcessInfo.processInfo.processIdentifier, bundleIdentifier: "generated.current.process", name: "Generated renamed self")
            context.activateFixtureSource(processID: 2_000_081, bundleIdentifier: "local.lilt.companion", name: "Generated legacy Vale")
            context.activateFixtureSource(processID: 2_000_082, bundleIdentifier: "generated.renamed.vale", name: "Vale")
            results["currentWorkActivationObserverKeepsExternalSourceWithoutReadingSelection"] = reads == preparedReads && context.sourceName == rememberedSource && context.hasSelectionText
            context.suspend()
            results["currentWorkSuspendClearsSelectionButRetainsOnlySourceIdentity"] = !context.hasSelectionText && !context.capturing && context.enabled && context.sourceName == rememberedSource
            context.prepareInvocation()
            results["currentWorkInvocationCanRefreshRememberedSourceAfterSuspend"] = context.hasSelectionText && reads == preparedReads + 1
            context.setEnabled(false)
            let disabled = try await context.captureForQuestion()
            results["currentWorkDisableNeverReturnsStaleContext"] = !context.enabled && !context.hasSelectionText && disabled.screen == nil && disabled.selectedText == nil && disabled.notice == nil && captures == 2
        } catch { results["currentWorkFreshnessFixturesCompleted"] = false }

        do {
            let context = CurrentWorkContext(isTesting: true)
            var captures = 0
            context.installFixture(screenAuthorized: false, selection: { .init(text: "Generated selected paragraph") }, capture: { captures += 1; return snapshot(byte: 3) })
            let denied = try await context.captureForQuestion()
            results["currentWorkScreenPermissionDenialKeepsSelectionAndTypingAvailable"] = denied.screen == nil && denied.selectedText == "Generated selected paragraph" && denied.notice != nil && captures == 0
            let manual = try await context.captureForQuestion(includeScreen: false)
            results["currentWorkManualWindowPrecedenceSkipsAutomaticScreenAndPermissionNotice"] = manual.screen == nil && manual.selectedText == "Generated selected paragraph" && manual.notice == nil && captures == 0
            var forbiddenSelectionReads = 0
            context.installFixture(screenAuthorized: false, selectionAuthorized: false, selection: { forbiddenSelectionReads += 1; return .init(text: "Generated unavailable selection") }, capture: { captures += 1; return snapshot(byte: 4) })
            context.prepareInvocation()
            let deniedBoth = try await context.captureForQuestion()
            results["currentWorkDeniedAccessibilityDoesNotReadSelection"] = deniedBoth.screen == nil && deniedBoth.selectedText == nil && forbiddenSelectionReads == 0 && captures == 0
        } catch { results["currentWorkPermissionFixturesCompleted"] = false }

        do {
            let context = CurrentWorkContext(isTesting: true)
            var selected = CurrentWorkContext.FixtureSelection(text: String(repeating: "界", count: 20_000))
            context.installFixture(selection: { selected }, capture: { snapshot(byte: 5) })
            let bounded = try await context.captureForQuestion(includeScreen: false)
            results["currentWorkSelectedTextIsBoundedTo16000UTF16UnitsAndTransient"] = bounded.selectedText?.utf16.count == 16_000 && !context.hasSelectionText
            selected = .init(text: "Generated secure secret", role: "AXTextField", subrole: "AXSecureTextField")
            let secure = try await context.captureForQuestion(includeScreen: false)
            selected = .init(text: "Generated password secret", role: "AXPasswordField")
            let password = try await context.captureForQuestion(includeScreen: false)
            selected = .init(text: " \n\t ")
            let empty = try await context.captureForQuestion(includeScreen: false)
            results["currentWorkSkipsSecurePasswordAndEmptySelection"] = secure.selectedText == nil && password.selectedText == nil && empty.selectedText == nil
        } catch { results["currentWorkSelectionFixturesCompleted"] = false }

        for invalidation in [Invalidation.cancel, .disable, .suspend, .sourceChange] {
            results["currentWorkRejectsLateCaptureAfter\(invalidation.rawValue)"] = await rejectsLateCapture(after: invalidation)
        }
        results["currentWorkDeadlineReturnsBeforeUncooperativeCaptureCompletes"] = await deadlineIsBounded()
        return results
    }

    private enum Invalidation: String { case cancel = "Cancellation", disable = "Disable", suspend = "Suspend", sourceChange = "SourceChange" }

    private static func rejectsLateCapture(after action: Invalidation) async -> Bool {
        let context = CurrentWorkContext(isTesting: true)
        let gate = FixtureCaptureGate()
        context.installFixture(selection: { .init(text: "Generated transient selection") }, capture: { await gate.wait(); return snapshot(byte: 91) })
        let question = Task { try await context.captureForQuestion() }
        guard await gate.started() else { question.cancel(); gate.release(); return false }
        switch action {
        case .cancel: question.cancel()
        case .disable: context.setEnabled(false)
        case .suspend: context.suspend()
        case .sourceChange: context.activateFixtureSource(processID: 2_000_101, name: "Replacement generated source")
        }
        let rejected: Bool
        switch await question.result { case .success: rejected = false; case .failure: rejected = true }
        let generationAfterInvalidation = context.generation
        gate.release()
        for _ in 0..<8 { await Task.yield() }
        return rejected && !context.hasSelectionText && !context.capturing && context.generation == generationAfterInvalidation && (action != .sourceChange || context.sourceName == "Replacement generated source")
    }

    private static func deadlineIsBounded() async -> Bool {
        let context = CurrentWorkContext(isTesting: true)
        let gate = FixtureCaptureGate()
        context.installFixture(timeout: 0.05, capture: { await gate.wait(); return snapshot(byte: 92) })
        let start = Date()
        let question = Task { try await context.captureForQuestion() }
        let rejected: Bool
        switch await question.result { case .success: rejected = false; case .failure: rejected = true }
        let bounded = Date().timeIntervalSince(start) < 1 && gate.waiting && !context.capturing
        gate.release()
        for _ in 0..<8 { await Task.yield() }
        context.installFixture(capture: { snapshot(byte: 93) })
        let fresh = try? await context.captureForQuestion()
        return rejected && bounded && fresh?.screen?.data == snapshot(byte: 93).data
    }

    private static func snapshot(byte: UInt8) -> ContextSnapshot {
        // A generated two-pixel image, not a desktop capture or provider response.
        let image = NSImage(size: NSSize(width: 2, height: 2))
        return ContextSnapshot(data: Data([byte, 0x47, 0x45, 0x4E]), image: image, windowID: 999, frame: CGRect(x: 0, y: 0, width: 2, height: 2), generation: UUID(), capturedAt: Date())
    }

    @MainActor private final class FixtureCaptureGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var waiting = false
        func wait() async {
            await withCheckedContinuation { continuation in self.continuation = continuation; waiting = true }
        }
        func started() async -> Bool {
            for _ in 0..<100 {
                if waiting { return true }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            return false
        }
        func release() { let held = continuation; continuation = nil; held?.resume() }
    }
}
