import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

// Change this value to adjust the clipboard window width in one place.
let clipboardWindowWidth: CGFloat = 390

@MainActor
final class HistoryPanelCoordinator: NSObject, NSWindowDelegate {
    private let historyStore: ClipboardHistoryStore
    private var panel: HistoryPanel?
    private var targetApplication: NSRunningApplication?
    private var entriesCancellable: AnyCancellable? = nil
    // Event-monitor callbacks are not actor-isolated. Access is serialized by
    // the main-thread event loop, while this annotation also keeps teardown
    // safe when the coordinator is released during app shutdown.
    nonisolated(unsafe) private var localEventMonitor: Any?
    nonisolated(unsafe) private var globalEventMonitor: Any?

    var isVisible: Bool { panel?.isVisible == true }

    init(historyStore: ClipboardHistoryStore) {
        self.historyStore = historyStore
        super.init()
        entriesCancellable = historyStore.$entries.sink { [weak self] _ in
            self?.resizePanelToFitEntries()
        }
    }

    func toggle(targetApplication: NSRunningApplication? = nil) {
        guard let panel, panel.isVisible else {
            show(targetApplication: targetApplication)
            return
        }
        close()
    }

    func close() {
        panel?.orderOut(nil)
        removeDismissalMonitors()
    }

    private func show(targetApplication: NSRunningApplication?) {
        let panel = panel ?? makePanel()
        self.panel = panel
        self.targetApplication = targetApplication

        historyStore.focusLatest()
        resizePanelToFitEntries()
        position(panel)
        installDismissalMonitors()

        // The app is a menu-bar/accessory app, so merely ordering the panel
        // front is not enough when the hot key was pressed in another app.
        // Activate first, then explicitly order regardless of the current
        // key window. This also makes the panel work across Spaces/full-screen
        // apps.
        NSApp.activate()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> HistoryPanel {
        let panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: clipboardWindowWidth, height: 500),
            styleMask: [.borderless, .fullSizeContentView, .utilityWindow, .titled],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentViewController = NSHostingController(
            rootView: ClipboardHistoryView(
                historyStore: historyStore,
                onClose: { [weak self] in self?.close() },
                onRestore: { [weak self] entry in self?.restoreAndPaste(entry) },
                onUpdate: { [weak self] in self?.updateHistory() }
            )
        )
        return panel
    }

    private func resizePanelToFitEntries() {
        guard let panel else { return }

        let entriesToShow = min(historyStore.entries.count, 8)
        let categoryCount = Set(historyStore.entries.prefix(entriesToShow).map(\.kind)).count
        let headerHeight: CGFloat = 150
        let rowHeight: CGFloat = 48
        let categoryHeaderHeight: CGFloat = 24
        let minimumHeight: CGFloat = 420
        let maximumHeight: CGFloat = 760
        let desiredHeight = headerHeight
            + CGFloat(entriesToShow) * rowHeight
            + CGFloat(categoryCount) * categoryHeaderHeight
        let height = min(maximumHeight, max(minimumHeight, desiredHeight))

        panel.setContentSize(NSSize(width: clipboardWindowWidth, height: height))
    }

    private func restoreAndPaste(_ entry: ClipboardEntry) {
        historyStore.restore(entry)
        close()

        guard let targetApplication,
              targetApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        guard PermissionManager.hasAccessibilityPermission else {
            PermissionManager.requestAccessibilityPermission()
            return
        }

        // `activateIgnoringOtherApps` is deprecated on macOS 14. This
        // activation is already user-initiated by clicking a history item.
        targetApplication.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    private func updateHistory() {
        Task { @MainActor in
            let snapshotter = ClipboardSnapshotter()
            guard let captured = await snapshotter.snapshot() else { return }
            historyStore.ingest(captured)
        }
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 12
        let x = min(
            max(mouseLocation.x - size.width / 2, visibleFrame.minX + horizontalPadding),
            visibleFrame.maxX - size.width - horizontalPadding
        )
        let y = min(
            max(mouseLocation.y - size.height - verticalPadding, visibleFrame.minY + verticalPadding),
            visibleFrame.maxY - size.height - verticalPadding
        )
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installDismissalMonitors() {
        guard localEventMonitor == nil else { return }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                switch event.keyCode {
                case 53: // Escape
                    self.close()
                    return nil
                case 126: // Up Arrow
                    self.historyStore.moveSelection(by: -1, among: self.historyStore.entries)
                    return nil
                case 125: // Down Arrow
                    self.historyStore.moveSelection(by: 1, among: self.historyStore.entries)
                    return nil
                case 36, 76: // Return / keypad Enter
                    if let entry = self.historyStore.selectedEntry(in: self.historyStore.entries) {
                        self.restoreAndPaste(entry)
                        return nil
                    }
                case 49: // Space
                    if let _ = self.historyStore.selectedEntry(in: self.historyStore.entries) {
                        // Preview is handled by the view
                        return nil
                    }
                case 8: // C
                    if event.modifierFlags.contains(.command) {
                        if let entry = self.historyStore.selectedEntry(in: self.historyStore.entries) {
                            self.restoreAndPaste(entry)
                            return nil
                        }
                    }
                case 2: // D
                    if event.modifierFlags.contains(.command) {
                        if let entry = self.historyStore.selectedEntry(in: self.historyStore.entries) {
                            self.historyStore.delete(entry)
                            return nil
                        }
                    }
                default:
                    break
                }
            }

            if event.type != .keyDown,
               let panel = self.panel,
               event.window !== panel,
               !panel.frame.contains(NSEvent.mouseLocation) {
                self.close()
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                DispatchQueue.main.async { [weak self] in self?.close() }
            }
        }
    }

    private func removeDismissalMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    deinit {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
    }
}

private final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
