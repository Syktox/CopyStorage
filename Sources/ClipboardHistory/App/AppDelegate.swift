import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let historyStore = ClipboardHistoryStore()
    let shortcutPreferences = ShortcutPreferences()
    let privacyManager = PrivacyManager()
    let launchAtLoginManager = LaunchAtLoginManager()

    private var panelCoordinator: HistoryPanelCoordinator?
    private var globalShortcutManager: GlobalShortcutManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        PermissionManager.requestAccessibilityPermission()

        panelCoordinator = HistoryPanelCoordinator(historyStore: historyStore)
        do {
            let manager = try GlobalShortcutManager { [weak self] in
                self?.toggleHistory()
            }
            globalShortcutManager = manager
            shortcutPreferences.connect(to: manager)
        } catch {
            shortcutPreferences.reportServiceFailure(error)
        }
    }

    func toggleHistory() {
        let targetApplication = panelCoordinator?.isVisible == true
            ? nil
            : NSWorkspace.shared.frontmostApplication
        panelCoordinator?.toggle(targetApplication: targetApplication)
    }

    func clearClipboard() {
        NSPasteboard.general.clearContents()
    }
}
