import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let historyStore = ClipboardHistoryStore()
    let shortcutPreferences = ShortcutPreferences()
    let privacyManager = PrivacyManager()
    let launchAtLoginManager = LaunchAtLoginManager()

    private let snapshotter = ClipboardSnapshotter()
    private var monitor: ClipboardMonitor?
    private var panelCoordinator: HistoryPanelCoordinator?
    private var globalShortcutManager: GlobalShortcutManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        PermissionManager.requestAccessibilityPermission()

        panelCoordinator = HistoryPanelCoordinator(historyStore: historyStore)
        monitor = ClipboardMonitor(shouldCapture: { [weak self] in
            self?.shouldCaptureClipboard() ?? true
        }) { [weak self] in
            self?.captureCurrentPasteboard()
        }
        historyStore.didRestorePasteboard = { [weak self] in
            self?.monitor?.ignoreCurrentPasteboardChange()
        }

        do {
            let manager = try GlobalShortcutManager { [weak self] in
                self?.toggleHistory()
            }
            globalShortcutManager = manager
            shortcutPreferences.connect(to: manager)
        } catch {
            shortcutPreferences.reportServiceFailure(error)
        }

        // Start watching from the current change count. The existing item on
        // the pasteboard was copied before this app started and must not be
        // added to the history retroactively.
        monitor?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    func toggleHistory() {
        let targetApplication = panelCoordinator?.isVisible == true
            ? nil
            : NSWorkspace.shared.frontmostApplication
        panelCoordinator?.toggle(targetApplication: targetApplication)
    }

    func clearClipboard() {
        NSPasteboard.general.clearContents()
        monitor?.ignoreCurrentPasteboardChange()
    }

    private func shouldCaptureClipboard() -> Bool {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmostApp?.bundleIdentifier
        let stringContent = NSPasteboard.general.string(forType: .string)
        return !privacyManager.shouldExcludeClipboardContent(from: bundleID, content: stringContent)
    }

    private func captureCurrentPasteboard() {
        Task { @MainActor in
            guard let captured = await snapshotter.snapshot() else { return }
            historyStore.ingest(captured)
        }
    }
}
