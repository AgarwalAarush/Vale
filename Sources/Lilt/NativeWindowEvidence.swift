import AppKit
import CryptoKit

/// App-owned, in-process rendering of the complete native view hierarchy.
/// This deliberately makes no compositor, physical-input or hardware claim.
@MainActor enum NativeWindowEvidence {
    enum Provenance: String {
        case unknown = "unknown-potentially-personal"
        case generatedAccountlessHarness = "generated-accountless-harness"
        case generatedDisposableFixture = "generated-disposable-fixture"
        var generatedOnly: Bool { self != .unknown }

        /// Generated view data alone is insufficient if a saved account can appear in Settings.
        @MainActor static func generatedHarness(account: ChatGPTAccount) -> Self {
            let harness = CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") || CommandLine.arguments.contains("--verify-release-feed")
            return classify(harness: harness, disposable: account.isDisposableFixture, accountless: account.accounts.isEmpty && account.activeAccountID == nil && !account.isSignedIn && !account.isSigningIn && account.error == nil)
        }
        static func classify(harness: Bool, disposable: Bool, accountless: Bool) -> Self {
            guard harness else { return .unknown }
            if disposable { return .generatedDisposableFixture }
            return accountless ? .generatedAccountlessHarness : .unknown
        }
    }
    static func capture(_ window: NSWindow, to file: URL, provenance: Provenance = .unknown) throws {
        guard window.isVisible, let content = window.contentView else {
            throw AppError("Full-window evidence requires a visible app window")
        }
        var frameView = content
        while let parent = frameView.superview { frameView = parent }
        let companion = window is NativeWorkspaceWindow && window is NSPanel &&
            window.identifier?.rawValue == "vale.workspace" && window.styleMask == .borderless &&
            content is NativeCompanionMaterial && !window.isOpaque
        var controlsInHierarchy = false
        if let close = window.standardWindowButton(.closeButton) {
            var ancestor: NSView? = close
            while let current = ancestor, current !== frameView { ancestor = current.superview }
            controlsInHierarchy = ancestor === frameView
        }
        guard (companion || controlsInHierarchy),
              abs(frameView.bounds.width - window.frame.width) < 1,
              abs(frameView.bounds.height - window.frame.height) < 1 else {
            throw AppError("Full-window evidence does not include the complete native window root")
        }
        if companion {
            guard abs(content.bounds.width - window.frame.width) < 1,
                  abs(content.bounds.height - window.frame.height) < 1,
                  content.layer?.masksToBounds == true, (content.layer?.cornerRadius ?? 0) > 0 else {
                throw AppError("Companion evidence requires its complete clipped production material root")
            }
        }
        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            throw AppError("Couldn’t render the native window frame")
        }
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        let radius = companion ? content.layer?.cornerRadius ?? 0 : 0
        // cacheDisplay does not consistently apply a layer's mask. Reapply only the
        // actual production root's rounded clip, preserving the native raster and
        // full frame. This is disclosed metadata, never compositor/shadow proof.
        let raster = companion ? try roundedRaster(bitmap, radius: radius, logicalSize: content.bounds.size) : bitmap
        let cornerAlpha = companion && raster.hasAlpha &&
            [(0, 0), (raster.pixelsWide - 1, 0), (0, raster.pixelsHigh - 1), (raster.pixelsWide - 1, raster.pixelsHigh - 1)].allSatisfy { point in
                (raster.colorAt(x: point.0, y: point.1)?.alphaComponent ?? 1) < 0.01
            }
        guard !companion || cornerAlpha else { throw AppError("Companion raster did not preserve rounded-corner alpha") }
        guard let png = raster.representation(using: .png, properties: [:]) else {
            throw AppError("Couldn’t encode the native window frame")
        }
        try writePrivate(png, to: file)
        let metadata: [String: Any] = [
            "method": "in-process-full-window-raster",
            "pngSHA256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
            "limitations": ["Not a window-server compositor screenshot", "Not physical-input or hardware evidence", "Materials and shadows may differ from compositor output"],
            "state": file.deletingPathExtension().lastPathComponent,
            "sourceRevision": ProcessInfo.processInfo.environment["VALE_EVIDENCE_HEAD"] ?? "unrecorded-working-source",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unpackaged",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unpackaged",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "logicalFrame": ["x": window.frame.minX, "y": window.frame.minY, "width": window.frame.width, "height": window.frame.height, "maxX": window.frame.maxX, "maxY": window.frame.maxY],
            "logicalContent": ["width": content.bounds.width, "height": content.bounds.height],
            "pixels": ["width": raster.pixelsWide, "height": raster.pixelsHigh],
            "backingScale": window.backingScaleFactor,
            "appearance": window.effectiveAppearance.name.rawValue,
            "windowClass": String(describing: type(of: window)),
            "windowIdentifier": window.identifier?.rawValue ?? "none",
            "chromeKind": companion ? "borderless-companion" : "standard-titled-window",
            "completeRootMatchesWindowFrame": true,
            "includesWindowControlsInHierarchy": controlsInHierarchy,
            "rootCornerRadius": radius,
            "rasterHasAlpha": raster.hasAlpha,
            "roundedCornerAlphaVerified": cornerAlpha,
            "roundedCornerRasterMethod": companion ? "native-root-cache-display-clipped-to-production-layer-radius" : "native-full-frame-cache-display",
            "toolbarPresent": window.toolbar != nil,
            "toolbarStyle": String(describing: window.toolbarStyle),
            "captureProvenance": provenance.rawValue,
            "publicArchiveEligible": provenance.generatedOnly,
            "generatedTestDataOnly": provenance.generatedOnly
        ]
        try writePrivate(JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]), to: file.appendingPathExtension("json"))
    }
    private static func roundedRaster(_ source: NSBitmapImageRep, radius: CGFloat, logicalSize: NSSize) throws -> NSBitmapImageRep {
        guard let image = source.cgImage, logicalSize.width > 0, logicalSize.height > 0,
              let context = CGContext(data: nil, width: source.pixelsWide, height: source.pixelsHigh,
                bitsPerComponent: 8, bytesPerRow: source.pixelsWide * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw AppError("Couldn’t preserve companion raster alpha") }
        let rect = CGRect(x: 0, y: 0, width: CGFloat(source.pixelsWide), height: CGFloat(source.pixelsHigh))
        context.addPath(CGPath(roundedRect: rect,
            cornerWidth: radius * CGFloat(source.pixelsWide) / logicalSize.width,
            cornerHeight: radius * CGFloat(source.pixelsHigh) / logicalSize.height, transform: nil))
        context.clip(); context.draw(image, in: rect)
        guard let clipped = context.makeImage() else { throw AppError("Couldn’t encode companion rounded root") }
        return NSBitmapImageRep(cgImage: clipped)
    }
    private static func writePrivate(_ data: Data, to file: URL) throws {
        let temporary = file.deletingLastPathComponent().appendingPathComponent(".native-evidence-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw AppError("Couldn’t create private native evidence") }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: data); try handle.close() }
        catch { try? handle.close(); throw error }
        if FileManager.default.fileExists(atPath: file.path) { _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary, options: .usingNewMetadataOnly) }
        else { try FileManager.default.moveItem(at: temporary, to: file) }
    }
}
