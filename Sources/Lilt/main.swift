import AppKit
import Darwin
signal(SIGPIPE, SIG_IGN)
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    withExtendedLifetime(controller) { app.run() }
}
