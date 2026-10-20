import AppKit
import SwiftUI

/// The runtime and disposable native render harness use this exact window path.
/// Constructing a window does not install menus, hotkeys or activate the app.
@MainActor final class NativeWorkspaceWindow: NSWindow {
    private(set) var chrome: NativeWorkspaceToolbar!

    init(model: AppModel, rememberFrame: Bool = false) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        title = "New chat"; titleVisibility = .visible
        backgroundColor = Theme.windowBackground; isReleasedWhenClosed = false
        identifier = NSUserInterfaceItemIdentifier("vale.workspace")
        minSize = NSSize(width: 740, height: 560)
        chrome = NativeWorkspaceToolbar(window: self, model: model)
        let host = NSHostingView(rootView: WorkspaceView(model: model))
        host.sizingOptions = []; host.autoresizingMask = [.width, .height]
        contentView = host; setContentSize(NSSize(width: 1040, height: 740)); center()
        if rememberFrame { setFrameAutosaveName("ValeWorkspace") }
    }
}
