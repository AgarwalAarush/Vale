import AppKit
import ApplicationServices
import Combine
@preconcurrency import ScreenCaptureKit

/// A single question's context. Neither screen bytes nor selected text are persisted by this service.
struct CurrentWorkSnapshot {
    var screen: ContextSnapshot?
    var selectedText: String?
    var generation: UUID
    var notice: String?
}

@MainActor private final class CurrentWorkCaptureDeadline {
    var continuation: CheckedContinuation<ContextSnapshot, Error>?
    var worker: Task<Void, Never>?
    var deadline: Task<Void, Never>?

    func finish(_ result: Result<ContextSnapshot, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        worker?.cancel(); deadline?.cancel()
        worker = nil; deadline = nil
        continuation.resume(with: result)
    }
}

/// Unlike a task-group timeout, this returns without waiting for an uncooperative SDK request.
@MainActor private func boundedCurrentWorkCapture(seconds: Double, operation: @escaping @MainActor () async throws -> ContextSnapshot) async throws -> ContextSnapshot {
    let gate = CurrentWorkCaptureDeadline()
    return try await withTaskCancellationHandler(operation: {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            gate.continuation = continuation
            gate.worker = Task {
                do { try Task.checkCancellation(); gate.finish(.success(try await operation())) }
                catch { gate.finish(.failure(error)) }
            }
            gate.deadline = Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                gate.finish(.failure(AppError("Current screen capture took too long. Ask again to retry.")))
            }
        }
    }, onCancel: { Task { @MainActor in gate.finish(.failure(CancellationError())) } })
}

@MainActor final class CurrentWorkContext: NSObject, ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var screenAuthorized = false
    @Published private(set) var selectionAuthorized = false
    @Published private(set) var hasSelectionText = false
    @Published private(set) var sourceName: String?
    @Published private(set) var status = "Automatic context is off"
    @Published private(set) var capturing = false
    private(set) var generation = UUID()

    private struct Source: Equatable {
        var processID: pid_t
        var bundleIdentifier: String?
        var name: String
    }
    private let testing: Bool
    private var source: Source?
    private var displayID: CGDirectDisplayID?
    private var selectedText: String?
    private var inFlight: Task<ContextSnapshot, Error>?
    private var fixtureSelection: (() -> FixtureSelection)?
    private var fixtureCapture: (() async throws -> ContextSnapshot)?
    private var captureTimeout = 6.0
    private static let preferenceKey = "valeAutomaticContextEnabled"
    private static let selectionLimit = 16_000
    private static var isHarness: Bool {
        CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test")
    }

    init(isTesting: Bool = false) {
        testing = isTesting || Self.isHarness || CommandLine.arguments.contains("--verify-release-feed")
        enabled = testing ? false : (UserDefaults.standard.object(forKey: Self.preferenceKey) as? Bool ?? true)
        super.init()
        guard !testing else { return }
        refreshPermissions()
        // Identity only: no selected-text reads, screen capture, or permission prompts here.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if !testing { UserDefaults.standard.set(value, forKey: Self.preferenceKey) }
        suspend()
        updateStatus()
    }

    /// Call before activating Vale so the source app's actual selection remains available.
    func prepareInvocation(screen: NSScreen? = nil) {
        guard enabled else { return }
        if testing {
            guard fixtureSelection != nil else { return }
        } else {
            refreshPermissions()
            rememberFrontmostApplication()
            let chosen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
            let chosenID = (chosen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            if chosenID != displayID { invalidate(); displayID = chosenID }
        }
        selectedText = readSelection()
        hasSelectionText = selectedText != nil
        updateStatus()
    }

    func refreshPermissions() {
        guard !testing else { return }
        screenAuthorized = CGPreflightScreenCaptureAccess()
        selectionAuthorized = AXIsProcessTrusted()
        if !selectionAuthorized { clearSelection() }
        updateStatus()
    }

    /// These are the only permission-prompting methods; UI calls them from explicit user actions.
    func requestScreenAccess() {
        guard !testing else { return }
        _ = CGRequestScreenCaptureAccess()
        refreshPermissions()
        if !screenAuthorized { openPrivacyPane("Privacy_ScreenCapture") }
    }

    func requestSelectionAccess() {
        guard !testing else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissions()
        if !selectionAuthorized { openPrivacyPane("Privacy_Accessibility") }
    }

    func captureForQuestion(includeScreen: Bool = true) async throws -> CurrentWorkSnapshot {
        try Task.checkCancellation()
        guard enabled else { return CurrentWorkSnapshot(screen: nil, selectedText: nil, generation: generation, notice: nil) }
        if !testing {
            refreshPermissions()
            rememberFrontmostApplication()
            if displayID == nil { prepareInvocation() }
        }
        invalidate()
        let expected = generation
        selectedText = readSelection()
        hasSelectionText = selectedText != nil
        let questionSelection = selectedText
        var completed = false
        // Keep no selection buffer after this operation; the caller owns the one-question value.
        defer { if generation == expected { clearSelection(); if completed { updateStatus() } } }
        guard includeScreen else {
            completed = true
            return CurrentWorkSnapshot(screen: nil, selectedText: questionSelection, generation: expected, notice: nil)
        }
        guard screenAuthorized else {
            completed = true
            status = "Screen access is off; you can still ask"
            return CurrentWorkSnapshot(screen: nil, selectedText: questionSelection, generation: expected, notice: "Screen not included. Allow Screen Recording in Settings.")
        }
        guard let requestedDisplay = displayID else {
            status = "Current display unavailable"
            return CurrentWorkSnapshot(screen: nil, selectedText: questionSelection, generation: expected, notice: "Current display unavailable. You can still ask.")
        }
        let fixture = fixtureCapture
        let timeout = captureTimeout
        let task = Task { [weak self] () async throws -> ContextSnapshot in
            try await boundedCurrentWorkCapture(seconds: timeout) { [weak self] in
                guard let self, self.enabled, self.generation == expected else { throw CancellationError() }
                var snapshot: ContextSnapshot
                if let fixture { snapshot = try await fixture() }
                else {
                    guard !self.testing else { throw AppError("Generated screen context is unavailable.") }
                    snapshot = try await self.captureDisplay(requestedDisplay, generation: expected)
                }
                try Task.checkCancellation()
                guard self.enabled, self.generation == expected else { throw CancellationError() }
                snapshot.generation = expected
                snapshot.windowID = nil
                snapshot.capturedAt = Date()
                return snapshot
            }
        }
        inFlight = task; capturing = true; status = "Reading current screen…"
        defer { if generation == expected { inFlight = nil; capturing = false } }
        do {
            let screen = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try Task.checkCancellation()
            guard enabled, generation == expected else { throw CancellationError() }
            completed = true
            return CurrentWorkSnapshot(screen: screen, selectedText: questionSelection, generation: expected, notice: nil)
        } catch {
            guard enabled, generation == expected, !Task.isCancelled else { throw CancellationError() }
            refreshPermissions()
            if !screenAuthorized {
                completed = true
                status = "Screen access is off; you can still ask"
                return CurrentWorkSnapshot(screen: nil, selectedText: questionSelection, generation: expected, notice: "Screen not included. Allow Screen Recording in Settings.")
            }
            status = "Screen unavailable. Ask again to retry."
            if error is CancellationError { throw error }
            throw AppError("Couldn’t read the current screen. Ask again to retry, or turn off automatic context.")
        }
    }

    /// Preserve only source/display identity so showing Vale again can refresh selection.
    func suspend() {
        invalidate()
        status = enabled ? "Automatic context paused" : "Automatic context is off"
    }

    func isCurrent(_ candidate: UUID) -> Bool { generation == candidate }

    private func invalidate() {
        generation = UUID()
        inFlight?.cancel(); inFlight = nil; capturing = false
        clearSelection()
    }

    private func clearSelection() { selectedText = nil; hasSelectionText = false }

    @objc private func applicationActivated(_ notification: Notification) {
        guard !testing, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        remember(app)
    }

    private func rememberFrontmostApplication() {
        guard !testing, let app = NSWorkspace.shared.frontmostApplication else { return }
        remember(app)
    }

    private func remember(_ app: NSRunningApplication) {
        guard !app.isTerminated else { return }
        remember(Source(processID: app.processIdentifier, bundleIdentifier: app.bundleIdentifier, name: app.localizedName ?? "Current app"))
    }

    private func remember(_ next: Source) {
        guard !Self.isVale(processID: next.processID, bundleIdentifier: next.bundleIdentifier, name: next.name) else { return }
        if source != next { invalidate(); source = next }
        sourceName = next.name
    }

    private static func isVale(processID: pid_t, bundleIdentifier: String?, name: String) -> Bool {
        if processID == ProcessInfo.processInfo.processIdentifier { return true }
        if let id = bundleIdentifier?.lowercased(), [Bundle.main.bundleIdentifier?.lowercased(), "local.lilt.companion", "local.vale.companion"].compactMap({ $0 }).contains(id) { return true }
        return ["vale", "lilt"].contains(name.lowercased())
    }

    private func readSelection() -> String? {
        guard enabled, selectionAuthorized, let source,
              !Self.isVale(processID: source.processID, bundleIdentifier: source.bundleIdentifier, name: source.name) else { return nil }
        if testing {
            guard let fixtureSelection else { return nil }
            let selection = fixtureSelection()
            return Self.safeSelection(selection.text, role: selection.role, subrole: selection.subrole)
        }
        guard let app = NSRunningApplication(processIdentifier: source.processID), !app.isTerminated else { return nil }
        let application = AXUIElementCreateApplication(source.processID)
        AXUIElementSetMessagingTimeout(application, 0.15)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }
        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(focused, 0.15)
        guard let role = stringAttribute(kAXRoleAttribute as CFString, of: focused) else { return nil }
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, of: focused)
        guard !Self.isSecure(role: role, subrole: subrole) else { return nil }
        // Never read AXValue, traverse text, simulate Copy, or consult the clipboard.
        return Self.safeSelection(stringAttribute(kAXSelectedTextAttribute as CFString, of: focused), role: role, subrole: subrole)
    }

    private func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private static func isSecure(role: String?, subrole: String?) -> Bool {
        [role, subrole].compactMap { $0?.lowercased() }.contains { $0.contains("secure") || $0.contains("password") }
    }

    private static func safeSelection(_ text: String?, role: String?, subrole: String?) -> String? {
        guard !isSecure(role: role, subrole: subrole), let text else { return nil }
        // Bound UTF-16 storage as well as ordinary character count.
        let bounded = String(decoding: text.utf16.prefix(selectionLimit), as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return bounded.isEmpty ? nil : bounded
    }

    private func captureDisplay(_ requestedID: CGDirectDisplayID, generation: UUID) async throws -> ContextSnapshot {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard self.generation == generation, enabled,
              let display = content.displays.first(where: { $0.displayID == requestedID }) else { throw AppError("Current display unavailable. Ask again to retry.") }
        let excluded = content.applications.filter { Self.isVale(processID: $0.processID, bundleIdentifier: $0.bundleIdentifier, name: $0.applicationName) }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let longest = Double(max(display.width, display.height))
        guard longest > 0 else { throw AppError("Current display unavailable. Ask again to retry.") }
        let scale = min(1, 1600 / longest)
        configuration.width = max(2, Int((Double(display.width) * scale).rounded(.down)) / 2 * 2)
        configuration.height = max(2, Int((Double(display.height) * scale).rounded(.down)) / 2 * 2)
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        guard self.generation == generation, enabled else { throw CancellationError() }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw AppError("Couldn’t read current screen. Ask again to retry.") }
        return ContextSnapshot(data: data, image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)), windowID: nil, frame: display.frame, generation: generation, capturedAt: Date())
    }

    private func updateStatus() {
        if !enabled { status = "Automatic context is off" }
        else if screenAuthorized { status = hasSelectionText ? "Current screen and selected text" : "Current screen on questions" }
        else if hasSelectionText { status = "Selected text ready · screen access off" }
        else { status = "Screen access is off; you can still ask" }
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    // Generated fixtures only. isTesting alone never grants access to real desktop/AX APIs.
    struct FixtureSelection {
        var text: String?
        var role: String? = "AXTextArea"
        var subrole: String?
    }

    func installFixture(screenAuthorized: Bool = true, selectionAuthorized: Bool = true, timeout: Double = 6,
                        selection: @escaping () -> FixtureSelection = { FixtureSelection(text: nil) },
                        capture: @escaping () async throws -> ContextSnapshot) {
        guard testing, Self.isHarness else { return }
        suspend(); enabled = true
        self.screenAuthorized = screenAuthorized; self.selectionAuthorized = selectionAuthorized
        fixtureSelection = selection; fixtureCapture = capture
        captureTimeout = max(0.05, min(6, timeout)); displayID = 73
        remember(Source(processID: 2_000_073, bundleIdentifier: "generated.vale.contextsource", name: "Generated source"))
        updateStatus()
    }

    /// Exercises activation identity changes without observing or reading the actual desktop.
    func activateFixtureSource(processID: pid_t, bundleIdentifier: String? = "generated.vale.contextsource", name: String = "Generated source") {
        guard testing, Self.isHarness, fixtureSelection != nil else { return }
        remember(Source(processID: processID, bundleIdentifier: bundleIdentifier, name: name))
    }
}
