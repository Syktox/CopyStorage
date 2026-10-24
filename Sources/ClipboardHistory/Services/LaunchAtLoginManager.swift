import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var isSupported: Bool = false

    private let defaults: UserDefaults
    private static let enabledKey = "launchAtLoginEnabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isSupported = true // SMAppService.mainApp is always available on macOS 13+

        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = defaults.bool(forKey: Self.enabledKey)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isSupported else {
            defaults.set(enabled, forKey: Self.enabledKey)
            return
        }

        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                isEnabled = SMAppService.mainApp.status == .enabled
            } catch {
                isEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }

    func toggle() {
        setEnabled(!isEnabled)
    }
}