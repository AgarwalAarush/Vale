import AppKit

/// App-owned, in-process rendering of the complete native view hierarchy.
/// This deliberately makes no compositor, physical-input or hardware claim.
@MainActor enum NativeWindowEvidence {
    static func capture(_ window: NSWindow, to file: URL) throws {
        guard window.isVisible, let content = window.contentView,
              let close = window.standardWindowButton(.closeButton) else {
            throw AppError("Full-window evidence requires a visible standard app window")
        }
        var frameView = content
        while let parent = frameView.superview { frameView = parent }
        var ancestor: NSView? = close
        while let current = ancestor, current !== frameView { ancestor = current.superview }
        guard ancestor === frameView,
              abs(frameView.bounds.width - window.frame.width) < 1,
              abs(frameView.bounds.height - window.frame.height) < 1 else {
            throw AppError("Full-window evidence does not include the standard window controls and frame")
        }
        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            throw AppError("Couldn’t render the native window frame")
        }
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AppError("Couldn’t encode the native window frame")
        }
        try png.write(to: file, options: .atomic)
        let metadata: [String: Any] = [
            "method": "in-process-full-window-raster",
            "limitations": ["Not a window-server compositor screenshot", "Not physical-input or hardware evidence", "Materials and shadows may differ from compositor output"],
            "state": file.deletingPathExtension().lastPathComponent,
            "sourceRevision": ProcessInfo.processInfo.environment["VALE_EVIDENCE_HEAD"] ?? "unrecorded-working-source",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unpackaged",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unpackaged",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "logicalFrame": ["width": window.frame.width, "height": window.frame.height],
            "logicalContent": ["width": content.bounds.width, "height": content.bounds.height],
            "pixels": ["width": bitmap.pixelsWide, "height": bitmap.pixelsHigh],
            "backingScale": window.backingScaleFactor,
            "appearance": window.effectiveAppearance.name.rawValue,
            "includesWindowControlsInHierarchy": true,
            "toolbarPresent": window.toolbar != nil,
            "toolbarStyle": String(describing: window.toolbarStyle),
            "generatedTestDataOnly": true
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: file.appendingPathExtension("json"), options: .atomic)
    }
}
