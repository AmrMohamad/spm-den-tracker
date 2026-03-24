import AppKit

@MainActor
/// Owns the macOS app lifecycle and presents the main tracker window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Retains the main window controller for the lifetime of the app session.
    private var windowController: MainWindowController?

    /// Creates the view model and window controller once AppKit finishes launching.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewModel = TrackerViewModel(service: LiveDependencyTrackingService())
        let windowController = MainWindowController(viewModel: viewModel)
        self.windowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Mirrors the common single-window macOS utility behavior by quitting after the last window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
