import Carbon.HIToolbox
import Foundation

enum GlobalShortcutError: LocalizedError, Equatable {
    case invalidShortcut
    case eventHandlerInstallationFailed(OSStatus)
    case alreadyInUse
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidShortcut:
            return "A global shortcut needs at least one modifier key."
        case .eventHandlerInstallationFailed:
            return "The global shortcut service could not be started."
        case .alreadyInUse:
            return "This shortcut is already reserved by another app. Choose a different shortcut."
        case .registrationFailed(let status):
            return "macOS could not register this shortcut (error \(status))."
        }
    }
}

/// Registers one process-exclusive Carbon hot key. Carbon remains the native
/// API for a global shortcut that must fire while this app is inactive.
final class GlobalShortcutManager {
    private static let signature: OSType = 0x43424853 // "CBHS"

    private let action: () -> Void
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var activeShortcut: KeyboardShortcut?
    private var nextIdentifier: UInt32 = 1
    var suppressActions = false

    init(action: @escaping () -> Void) throws {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalShortcutEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard status == noErr else {
            throw GlobalShortcutError.eventHandlerInstallationFailed(status)
        }
    }

    /// The prior hot key is kept until the replacement has registered, so an
    /// invalid/conflicting preference can never leave the app without a shortcut.
    func register(_ shortcut: KeyboardShortcut) throws {
        guard shortcut.isUsable else { throw GlobalShortcutError.invalidShortcut }
        guard shortcut != activeShortcut else { return }

        var replacement: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: nextIdentifier)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &replacement
        )

        guard status == noErr, let replacement else {
            if status == eventHotKeyExistsErr { throw GlobalShortcutError.alreadyInUse }
            throw GlobalShortcutError.registrationFailed(status)
        }

        let previous = hotKeyRef
        hotKeyRef = replacement
        activeShortcut = shortcut
        nextIdentifier &+= 1
        if let previous { UnregisterEventHotKey(previous) }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        activeShortcut = nil
    }

    fileprivate func fireAction() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.suppressActions else { return }
            self.action()
        }
    }

    deinit {
        unregister()
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}

private func globalShortcutEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
    manager.fireAction()
    return noErr
}
