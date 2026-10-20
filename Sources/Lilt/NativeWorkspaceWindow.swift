import AppKit
import SwiftUI

/// The runtime and disposable native render harness use this exact window path.
/// Constructing a window does not install menus, hotkeys or activate the app.
@MainActor final class NativeWorkspaceWindow: NSWindow {
    static let minimumFrameSize = NSSize(width: 740, height: 560)
    private(set) var chrome: NativeWorkspaceToolbar!

    /// Keep AppKit responsible for window constraints; a top-level NSHostingView updates them itself.
    static func contentContainer<Content: View>(for rootView: Content, size: NSSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = []; host.frame = container.bounds; host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        return container
    }

    init(model: AppModel, rememberFrame: Bool = false) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        title = "New chat"; titleVisibility = .visible
        backgroundColor = Theme.windowBackground; isReleasedWhenClosed = false
        identifier = NSUserInterfaceItemIdentifier("vale.workspace")
        chrome = NativeWorkspaceToolbar(window: self, model: model)
        contentView = Self.contentContainer(for: WorkspaceView(model: model), size: NSSize(width: 1040, height: 740))
        minSize = Self.minimumFrameSize
        // The instance conversion includes this window's native toolbar. Content minimum takes
        // precedence over minSize; its effective frame may exceed the intended frame floor.
        contentMinSize = contentRect(forFrameRect: NSRect(origin: .zero, size: Self.minimumFrameSize)).size
        setContentSize(NSSize(width: 1040, height: 740)); center()
        if rememberFrame { setFrameAutosaveName("ValeWorkspace") }
    }
}
