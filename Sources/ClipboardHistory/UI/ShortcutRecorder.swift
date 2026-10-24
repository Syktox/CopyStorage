import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyboardShortcut
    let onShortcut: (KeyboardShortcut) -> Void
    let onRecordingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onShortcut: onShortcut, onRecordingChanged: onRecordingChanged)
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.shortcut = shortcut
        button.onShortcut = context.coordinator.record
        button.onRecordingChanged = context.coordinator.recordingChanged
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        context.coordinator.onShortcut = onShortcut
        context.coordinator.onRecordingChanged = onRecordingChanged
        nsView.onShortcut = context.coordinator.record
        nsView.onRecordingChanged = context.coordinator.recordingChanged
        if !nsView.isRecording {
            nsView.shortcut = shortcut
        }
    }

    final class Coordinator {
        var onShortcut: (KeyboardShortcut) -> Void
        var onRecordingChanged: (Bool) -> Void

        init(
            onShortcut: @escaping (KeyboardShortcut) -> Void,
            onRecordingChanged: @escaping (Bool) -> Void
        ) {
            self.onShortcut = onShortcut
            self.onRecordingChanged = onRecordingChanged
        }

        func record(_ shortcut: KeyboardShortcut) {
            onShortcut(shortcut)
        }

        func recordingChanged(_ isRecording: Bool) {
            onRecordingChanged(isRecording)
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: KeyboardShortcut = .controlCommandV {
        didSet { refreshTitle() }
    }
    var onShortcut: ((KeyboardShortcut) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    private(set) var isRecording = false {
        didSet {
            refreshTitle()
            onRecordingChanged?(isRecording)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        refreshTitle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        target = self
        action = #selector(beginRecording)
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            isRecording = false
            return
        }

        guard let shortcut = KeyboardShortcut(event: event) else {
            NSSound.beep()
            return
        }
        self.shortcut = shortcut
        isRecording = false
        onShortcut?(shortcut)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { isRecording = false }
        return super.resignFirstResponder()
    }

    private func refreshTitle() {
        title = isRecording ? "Press shortcut" : shortcut.displayString
    }
}
