import AppKit

/// `NSPasteboard` has no push notification. A low-frequency change-count check
/// is the supported lightweight way to observe it.
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let onChange: () -> Void
    private var timer: Timer?
    private var lastChangeCount: Int
    private var shouldCapture: () -> Bool

    init(
        pasteboard: NSPasteboard = .general,
        interval: TimeInterval = 0.5,
        shouldCapture: @escaping () -> Bool = { true },
        onChange: @escaping () -> Void
    ) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.shouldCapture = shouldCapture
        self.onChange = onChange
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForChange()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call immediately after the app writes a restored history item, preventing
    /// that write from being captured as a new item on the next timer tick.
    func ignoreCurrentPasteboardChange() {
        lastChangeCount = pasteboard.changeCount
    }

    private func checkForChange() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if shouldCapture() {
            onChange()
        }
    }

    deinit { stop() }
}
