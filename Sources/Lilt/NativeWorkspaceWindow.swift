import AppKit
import Combine
import SwiftUI

/// A single keyboard-summoned companion. No separate coach, titlebar, toolbar,
/// or assistant workspace is created when this panel expands.
@MainActor final class NativeWorkspaceWindow: NSPanel {
    static let minimumFrameSize = CompanionPresentation.idleSize
    private(set) var chrome: NativeWorkspaceToolbar!
    private let model: AppModel
    private var observations: [AnyCancellable] = []
    private var layoutQueued = false
    private var anchor: NSPoint?
    private weak var anchorScreen: NSScreen?
    private var materialView: NativeCompanionMaterial?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var presentationTargetSize: NSSize { CompanionPresentation.targetSize(for: model) }

    static func contentContainer<Content: View>(for rootView: Content, size: NSSize) -> NSView {
        let material = NativeCompanionMaterial(frame: NSRect(origin: .zero, size: size))
        material.cornerRadius = size.height <= 45 ? 22.5 : 24
        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = []
        host.frame = material.bounds
        host.autoresizingMask = [.width, .height]
        material.installContentView(host)
        return material
    }

    init(model: AppModel, rememberFrame: Bool = false) {
        self.model = model
        super.init(contentRect: NSRect(origin: .zero, size: CompanionPresentation.idleSize), styleMask: [.borderless], backing: .buffered, defer: false)
        title = "Vale"; titleVisibility = .hidden
        backgroundColor = .clear; isOpaque = false; hasShadow = true
        isReleasedWhenClosed = false; hidesOnDeactivate = false; isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        identifier = NSUserInterfaceItemIdentifier("vale.workspace")
        chrome = NativeWorkspaceToolbar(window: self, model: model)
        contentView = Self.contentContainer(for: WorkspaceView(model: model), size: CompanionPresentation.idleSize)
        materialView = contentView as? NativeCompanionMaterial
        minSize = CompanionPresentation.idleSize
        maxSize = NSSize(width: 520, height: 650)
        model.objectWillChange.sink { [weak self] in self?.queueLayout() }.store(in: &observations)
        summon(on: NSScreen.main)
    }

    /// The mouse display is used by the shortcut; model-driven route changes
    /// retain this display and anchor rather than following pointer movement.
    func summon(on screen: NSScreen? = nil) {
        let chosen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        anchorScreen = chosen
        if let chosen { anchor = NSPoint(x: chosen.visibleFrame.maxX - 18, y: chosen.visibleFrame.maxY - 18) }
        applyCompanionLayout(animated: false)
    }
    private func queueLayout() {
        guard !layoutQueued else { return }; layoutQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.layoutQueued = false
            self.applyCompanionLayout(animated: self.isVisible)
        }
    }
    func applyCompanionLayout(animated: Bool = false) {
        var size = presentationTargetSize
        let visible = (anchorScreen ?? screen ?? NSScreen.main)?.visibleFrame
        if let visible { size.width = min(size.width, visible.width - 36); size.height = min(size.height, visible.height - 36) }
        let point = anchor ?? NSPoint(x: visible?.maxX ?? 800, y: visible?.maxY ?? 700)
        let target = NSRect(x: point.x - size.width, y: point.y - size.height, width: size.width, height: size.height)
        guard frame != target else { return }
        materialView?.cornerRadius = size.height <= 45 ? 22.5 : 24
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(target, display: true)
            }
        } else { setFrame(target, display: true) }
        invalidateShadow()
    }
}
