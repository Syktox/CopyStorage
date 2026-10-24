import Combine
import Foundation

@MainActor
final class ShortcutPreferences: ObservableObject {
    @Published private(set) var shortcut: KeyboardShortcut
    @Published private(set) var registrationError: String?

    private static let shortcutDefaultsKey = "openClipboardHistoryShortcut"
    private let defaults: UserDefaults
    private weak var shortcutManager: GlobalShortcutManager?
    private var recordingGeneration = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.shortcutDefaultsKey),
           let decoded = try? JSONDecoder().decode(KeyboardShortcut.self, from: data),
           decoded.isUsable {
            shortcut = decoded
        } else {
            shortcut = .controlCommandV
        }
    }

    func connect(to manager: GlobalShortcutManager) {
        shortcutManager = manager
        registerCurrentShortcut()
    }

    func updateShortcut(to candidate: KeyboardShortcut) {
        guard let shortcutManager else {
            registrationError = "The shortcut service is not available."
            return
        }

        do {
            try shortcutManager.register(candidate)
            shortcut = candidate
            registrationError = nil
            persistShortcut()
        } catch let error as GlobalShortcutError {
            registrationError = error.localizedDescription
        } catch {
            registrationError = "macOS could not register this shortcut."
        }
    }

    func resetToDefault() {
        updateShortcut(to: .controlCommandV)
    }

    func setShortcutRecording(_ isRecording: Bool) {
        recordingGeneration &+= 1
        let generation = recordingGeneration
        if isRecording {
            shortcutManager?.suppressActions = true
            return
        }

        // Carbon delivers the global notification asynchronously. Keep it
        // suppressed long enough for the keystroke used by the recorder to be
        // consumed instead of also toggling the history panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.recordingGeneration == generation else { return }
            self.shortcutManager?.suppressActions = false
        }
    }

    func reportServiceFailure(_ error: Error) {
        registrationError = error.localizedDescription
    }

    private func registerCurrentShortcut() {
        guard let shortcutManager else { return }

        do {
            try shortcutManager.register(shortcut)
            registrationError = nil
        } catch let error as GlobalShortcutError {
            registrationError = error.localizedDescription
        } catch {
            registrationError = "macOS could not register this shortcut."
        }
    }

    private func persistShortcut() {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: Self.shortcutDefaultsKey)
    }
}
