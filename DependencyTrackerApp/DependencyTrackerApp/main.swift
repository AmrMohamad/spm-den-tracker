import AppKit

/// Shared `NSApplication` instance for the macOS app process.
let application = NSApplication.shared
/// App delegate that owns the main window lifecycle.
let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
