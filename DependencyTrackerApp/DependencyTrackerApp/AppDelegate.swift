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
        installMenus(windowController: windowController)
        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(self)
        windowController.window?.makeMain()
        windowController.window?.makeKeyAndOrderFront(self)
        windowController.window?.orderFrontRegardless()
    }

    /// Mirrors the common single-window macOS utility behavior by quitting after the last window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Installs a minimal app menu so standard keyboard shortcuts work.
    private func installMenus(windowController: MainWindowController) {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.title = "DependencyTrackerApp"
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit SPM Dependency Tracker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        fileMenuItem.title = "File"
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        let openItem = NSMenuItem(title: "Open…", action: #selector(MainWindowController.openProjectFromMenu(_:)), keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = [.command]
        openItem.target = windowController
        fileMenu.addItem(openItem)

        let rerunItem = NSMenuItem(title: "Re-run", action: #selector(MainWindowController.rerunAnalysisFromMenu(_:)), keyEquivalent: "r")
        rerunItem.keyEquivalentModifierMask = [.command]
        rerunItem.target = windowController
        fileMenu.addItem(rerunItem)

        NSApp.mainMenu = mainMenu
    }
}
