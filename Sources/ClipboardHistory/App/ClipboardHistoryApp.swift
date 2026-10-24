import SwiftUI

@main
struct ClipboardHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Clipboard History", systemImage: "clipboard") {
            Button("Open Clipboard History") {
                appDelegate.toggleHistory()
            }

            Divider()

            Button("Clear Unpinned History") {
                appDelegate.historyStore.clearUnpinned()
            }

            Button("Clear Clipboard History", role: .destructive) {
                appDelegate.historyStore.clearAll(includePinned: true)
            }

            Button("Clear Clipboard") {
                appDelegate.clearClipboard()
            }

            SettingsLink()

            Divider()

            Button("Quit Clipboard History") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                preferences: appDelegate.shortcutPreferences,
                privacyManager: appDelegate.privacyManager,
                launchAtLoginManager: appDelegate.launchAtLoginManager,
                historyStore: appDelegate.historyStore
            )
        }
    }
}
