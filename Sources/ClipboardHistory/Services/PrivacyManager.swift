import Foundation
import AppKit

@MainActor
final class PrivacyManager: ObservableObject {
    @Published var excludedAppBundleIDs: Set<String> = []
    @Published var excludeSensitiveContent: Bool = false
    @Published var excludePasswords: Bool = false
    @Published var excludePasswordManagers: Bool = false

    private let defaults: UserDefaults
    private static let excludedAppsKey = "excludedAppBundleIDs"
    private static let excludeSensitiveKey = "excludeSensitiveContent"
    private static let excludePasswordsKey = "excludePasswords"
    private static let excludePasswordManagersKey = "excludePasswordManagers"

    private let knownPasswordManagerBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword8",
        "com.bitwarden.desktop",
        "com.keepassxc.keepassxc",
        "com.keepassx.keepassx",
        "com.lastpass.lastpass",
        "com.dashlane.dashlane",
        "com.nordpass.nordpass",
        "com.proton.pass",
        "com.roboform.roboform",
        "com.kaspersky.password-manager",
        "com.enycrptr.enycrptr",
        "com.strongbox.strongbox",
        "com.macpaw.strongbox",
        "com.secrets.secrets",
        "com.chris-hulbert.secrets",
        "com.towerpasswords.tower"
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.excludedAppsKey),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            excludedAppBundleIDs = Set(array)
        }

        excludeSensitiveContent = defaults.bool(forKey: Self.excludeSensitiveKey)
        excludePasswords = defaults.bool(forKey: Self.excludePasswordsKey)
        excludePasswordManagers = defaults.bool(forKey: Self.excludePasswordManagersKey)
    }

    func setExcludedApps(_ bundleIDs: Set<String>) {
        excludedAppBundleIDs = bundleIDs
        persistExcludedApps()
    }

    func addExcludedApp(_ bundleID: String) {
        excludedAppBundleIDs.insert(bundleID)
        persistExcludedApps()
    }

    func removeExcludedApp(_ bundleID: String) {
        excludedAppBundleIDs.remove(bundleID)
        persistExcludedApps()
    }

    func setExcludeSensitiveContent(_ enabled: Bool) {
        excludeSensitiveContent = enabled
        defaults.set(enabled, forKey: Self.excludeSensitiveKey)
    }

    func setExcludePasswords(_ enabled: Bool) {
        excludePasswords = enabled
        defaults.set(enabled, forKey: Self.excludePasswordsKey)
    }

    func setExcludePasswordManagers(_ enabled: Bool) {
        excludePasswordManagers = enabled
        defaults.set(enabled, forKey: Self.excludePasswordManagersKey)
    }

    func shouldExcludeClipboardContent(from bundleID: String?, content: String?) -> Bool {
        if let bundleID = bundleID {
            if excludedAppBundleIDs.contains(bundleID) { return true }
            if excludePasswordManagers && knownPasswordManagerBundleIDs.contains(bundleID) { return true }
        }

        guard let content = content, !content.isEmpty else { return false }

        if excludeSensitiveContent && containsSensitivePatterns(content) { return true }
        if excludePasswords && looksLikePassword(content) { return true }

        return false
    }

    private func containsSensitivePatterns(_ text: String) -> Bool {
        let patterns = [
            #"api[_-]?key\s*[:=]\s*[a-zA-Z0-9_-]{20,}"#,
            #"secret[_-]?key\s*[:=]\s*[a-zA-Z0-9_-]{20,}"#,
            #"access[_-]?token\s*[:=]\s*[a-zA-Z0-9_-]{20,}"#,
            #"auth[_-]?token\s*[:=]\s*[a-zA-Z0-9_-]{20,}"#,
            #"bearer\s+[a-zA-Z0-9_-]{20,}"#,
            #"password\s*[:=]\s*\S{8,}"#,
            #"passwd\s*[:=]\s*\S{8,}"#,
            #"private[_-]?key\s*[:=]\s*[a-zA-Z0-9/+=]{40,}"#,
            #"ssh[_-]?rsa\s+[a-zA-Z0-9/+=]{40,}"#,
            #"-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----"#,
            #"\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b"#,
            #"\b\d{3}[- ]?\d{2}[- ]?\d{4}\b"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) != nil {
                return true
            }
        }
        return false
    }

    private func looksLikePassword(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8, trimmed.count <= 128 else { return false }
        guard trimmed.rangeOfCharacter(from: .newlines) == nil else { return false }
        guard trimmed.rangeOfCharacter(from: .whitespaces) == nil else { return false }
        let hasUpper = trimmed.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLower = trimmed.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasDigit = trimmed.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSymbol = trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?")) != nil
        return (hasUpper && hasLower && hasDigit) || (hasUpper && hasLower && hasSymbol)
    }

    private func persistExcludedApps() {
        guard let data = try? JSONEncoder().encode(Array(excludedAppBundleIDs)) else { return }
        defaults.set(data, forKey: Self.excludedAppsKey)
    }
}