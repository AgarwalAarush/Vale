import AppKit
@preconcurrency import ScreenCaptureKit

struct ContextSnapshot {
    var data: Data
    var image: NSImage
    var windowID: CGWindowID?
    var frame: CGRect?
    var generation: UUID
    var capturedAt: Date
}

@MainActor final class WindowContext: NSObject, ObservableObject, SCContentSharingPickerObserver {
    @Published var title: String?
    @Published var lastCapture: Date?
    @Published var preview: NSImage?
    private(set) var filter: SCContentFilter?
    private(set) var generation = UUID()
    private(set) var windowID: CGWindowID?
    var changed: (() -> Void)?
    var failed: ((String) -> Void)?
    override init() { super.init(); SCContentSharingPicker.shared.add(self) }
    func choose() {
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleWindow]
        config.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "local.lilt.companion"]
        SCContentSharingPicker.shared.defaultConfiguration = config
        SCContentSharingPicker.shared.isActive = true
        SCContentSharingPicker.shared.present()
    }
    func stop() {
        filter = nil; title = nil; preview = nil; lastCapture = nil; windowID = nil; generation = UUID()
        SCContentSharingPicker.shared.isActive = false; changed?()
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {}
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async { self.failed?("Couldn’t open window sharing. You can still type or paste your context.") }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        DispatchQueue.main.async {
            self.filter = filter; self.generation = UUID(); self.preview = nil; self.lastCapture = nil
            if #available(macOS 15.2, *), let window = filter.includedWindows.first {
                self.windowID = window.windowID
                if let name = window.owningApplication?.applicationName { self.title = "\(name) window" } else { self.title = "Selected window" }
            } else { self.windowID = nil; self.title = "Selected window" }
            self.changed?()
        }
    }
    func capture() async throws -> ContextSnapshot {
        guard let filter else { throw AppError("Choose a window to share first.") }
        let expected = generation
        let config = SCStreamConfiguration()
        let rect = filter.contentRect
        guard rect.width > 1, rect.height > 1 else { throw AppError("That window is unavailable. Choose another window.") }
        let scale = min(2.0, 1600.0 / max(rect.width, rect.height))
        config.width = max(2, Int(rect.width * scale)); config.height = max(2, Int(rect.height * scale))
        config.showsCursor = false; config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard expected == generation else { throw AppError("Sharing changed. Ask again with the new window.") }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw AppError("Couldn’t capture the selected window.") }
        let preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        self.preview = preview; lastCapture = Date()
        return ContextSnapshot(data: data, image: preview, windowID: windowID, frame: currentFrame(), generation: generation, capturedAt: Date())
    }
    func currentFrame() -> CGRect? {
        guard let windowID, let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]], let row = entries.first,
              let bounds = row[kCGWindowBounds as String] as? [String: Any], let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }
}
