import SwiftUI
import Combine
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel

    init(
        preferences: ShortcutPreferences,
        privacyManager: PrivacyManager,
        launchAtLoginManager: LaunchAtLoginManager,
        historyStore: ClipboardHistoryStore
    ) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(
            preferences: preferences,
            privacyManager: privacyManager,
            launchAtLoginManager: launchAtLoginManager,
            historyStore: historyStore
        ))
    }

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            GeneralSettingsView(viewModel: viewModel.generalVM)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            ClipboardSettingsView(viewModel: viewModel.clipboardVM)
                .tabItem { Label("Clipboard", systemImage: "clipboard") }
                .tag(SettingsTab.clipboard)

            StorageSettingsView(viewModel: viewModel.storageVM)
                .tabItem { Label("Storage", systemImage: "externaldrive") }
                .tag(SettingsTab.storage)

            PrivacySettingsView(viewModel: viewModel.privacyVM)
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
                .tag(SettingsTab.privacy)

            ShortcutsSettingsView(viewModel: viewModel.shortcutsVM)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            AdvancedSettingsView(viewModel: viewModel.advancedVM)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.advanced)
        }
        .frame(width: 580, height: 420)
        .padding(20)
    }
}

enum SettingsTab: String, CaseIterable {
    case general, clipboard, storage, privacy, shortcuts, advanced
}

@MainActor
final class SettingsViewModel: ObservableObject {
    let preferences: ShortcutPreferences
    let privacyManager: PrivacyManager
    let launchAtLoginManager: LaunchAtLoginManager
    let historyStore: ClipboardHistoryStore

    @Published var selectedTab: SettingsTab = .general

    let generalVM: GeneralSettingsViewModel
    let clipboardVM: ClipboardSettingsViewModel
    let storageVM: StorageSettingsViewModel
    let privacyVM: PrivacySettingsViewModel
    let shortcutsVM: ShortcutsSettingsViewModel
    let advancedVM: AdvancedSettingsViewModel

    init(
        preferences: ShortcutPreferences,
        privacyManager: PrivacyManager,
        launchAtLoginManager: LaunchAtLoginManager,
        historyStore: ClipboardHistoryStore
    ) {
        self.preferences = preferences
        self.privacyManager = privacyManager
        self.launchAtLoginManager = launchAtLoginManager
        self.historyStore = historyStore

        self.generalVM = GeneralSettingsViewModel(launchAtLoginManager: launchAtLoginManager, historyStore: historyStore)
        self.clipboardVM = ClipboardSettingsViewModel(historyStore: historyStore)
        self.storageVM = StorageSettingsViewModel(historyStore: historyStore)
        self.privacyVM = PrivacySettingsViewModel(privacyManager: privacyManager, historyStore: historyStore)
        self.shortcutsVM = ShortcutsSettingsViewModel(preferences: preferences)
        self.advancedVM = AdvancedSettingsViewModel(historyStore: historyStore)
    }
}

// MARK: - General

@MainActor
final class GeneralSettingsViewModel: ObservableObject {
    let launchAtLoginManager: LaunchAtLoginManager
    let historyStore: ClipboardHistoryStore

    init(launchAtLoginManager: LaunchAtLoginManager, historyStore: ClipboardHistoryStore) {
        self.launchAtLoginManager = launchAtLoginManager
        self.historyStore = historyStore
    }

    var isLaunchAtLoginEnabled: Bool {
        get { launchAtLoginManager.isEnabled }
        set { launchAtLoginManager.setEnabled(newValue) }
    }

    var isLaunchAtLoginSupported: Bool { launchAtLoginManager.isSupported }
}

struct GeneralSettingsView: View {
    @StateObject var viewModel: GeneralSettingsViewModel

    init(viewModel: GeneralSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    init(launchAtLoginManager: LaunchAtLoginManager, historyStore: ClipboardHistoryStore) {
        _viewModel = StateObject(wrappedValue: GeneralSettingsViewModel(launchAtLoginManager: launchAtLoginManager, historyStore: historyStore))
    }

    var body: some View {
        Form {
            Section("Application") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { viewModel.isLaunchAtLoginEnabled },
                    set: { viewModel.isLaunchAtLoginEnabled = $0 }
                ))
                .disabled(!viewModel.isLaunchAtLoginSupported)

                Toggle("Show in Menu Bar", isOn: .constant(true))
                Toggle("Keep Clipboard History", isOn: .constant(true))
            }

            Section("History Display") {
                Text("Your clipboard history is stored locally on this Mac.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Clipboard

@MainActor
final class ClipboardSettingsViewModel: ObservableObject {
    let historyStore: ClipboardHistoryStore

    init(historyStore: ClipboardHistoryStore) {
        self.historyStore = historyStore
    }

    var maximumEntries: Int {
        get { historyStore.maximumEntries }
        set { historyStore.setLimits(maximumEntries: newValue, maximumStorageBytes: historyStore.maximumStorageBytes) }
    }
}

struct ClipboardSettingsView: View {
    @StateObject var viewModel: ClipboardSettingsViewModel

    init(viewModel: ClipboardSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    init(historyStore: ClipboardHistoryStore) {
        _viewModel = StateObject(wrappedValue: ClipboardSettingsViewModel(historyStore: historyStore))
    }

    var body: some View {
        Form {
            Section("Content Types to Save") {
                Toggle("Text", isOn: .constant(true))
                Toggle("Images", isOn: .constant(true))
                Toggle("Files", isOn: .constant(true))
                Toggle("Videos & Audio", isOn: .constant(true))
            }

            Section("History Limits") {
                HStack {
                    Text("Maximum Entries")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { viewModel.maximumEntries },
                        set: { viewModel.maximumEntries = $0 }
                    )) {
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("250").tag(250)
                        Text("500").tag(500)
                        Text("1,000").tag(1000)
                        Text("Unlimited").tag(-1)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Storage

@MainActor
final class StorageSettingsViewModel: ObservableObject {
    let historyStore: ClipboardHistoryStore

    @Published var storageSize: String = "Calculating..."
    @Published var showClearConfirmation = false
    @Published var clearScope: ClearScope = .unpinned

    enum ClearScope { case today, thisWeek, unpinned, all }

    init(historyStore: ClipboardHistoryStore) {
        self.historyStore = historyStore
        calculateStorageSize()
    }

    var maximumStorageBytes: Int64 {
        get { historyStore.maximumStorageBytes }
        set { historyStore.setLimits(maximumEntries: historyStore.maximumEntries, maximumStorageBytes: newValue) }
    }

    var entryCount: Int { historyStore.entries.count }

    func calculateStorageSize() {
        Task.detached(priority: .utility) { [weak self] in
            let viewModel = self
            if let persistence = try? DiskHistoryPersistence() {
                let size = try? persistence.calculateTotalStorageSize()
                await MainActor.run {
                    if let size, let viewModel = viewModel {
                        viewModel.storageSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                    } else {
                        viewModel?.storageSize = "Unknown"
                    }
                }
            }
        }
    }

    func requestClear(_ scope: ClearScope) {
        clearScope = scope
        showClearConfirmation = true
    }

    func performClear() {
        let calendar = Calendar.current
        let now = Date()

        switch clearScope {
        case .unpinned:
            historyStore.clearUnpinned()
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            historyStore.clearEntries(olderThan: startOfDay, includePinned: false)
        case .thisWeek:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            historyStore.clearEntries(olderThan: startOfWeek, includePinned: false)
        case .all:
            historyStore.clearAll(includePinned: true)
        }
        calculateStorageSize()
    }

    func confirmationMessage(for scope: ClearScope) -> String {
        switch scope {
        case .unpinned: return "This will remove all unpinned clipboard history items. Pinned items will be kept."
        case .today: return "This will remove all clipboard history items from today (except pinned items)."
        case .thisWeek: return "This will remove all clipboard history items from this week (except pinned items)."
        case .all: return "This will permanently delete ALL clipboard history including pinned items. This cannot be undone."
        }
    }
}

struct StorageSettingsView: View {
    @StateObject var viewModel: StorageSettingsViewModel

    init(viewModel: StorageSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    init(historyStore: ClipboardHistoryStore) {
        _viewModel = StateObject(wrappedValue: StorageSettingsViewModel(historyStore: historyStore))
    }

    var body: some View {
        Form {
            Section("Storage Limit") {
                HStack {
                    Text("Maximum Storage")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { viewModel.maximumStorageBytes },
                        set: { viewModel.maximumStorageBytes = $0 }
                    )) {
                        Text("100 MB").tag(100_000_000)
                        Text("500 MB").tag(500_000_000)
                        Text("1 GB").tag(1_000_000_000)
                        Text("5 GB").tag(5_000_000_000)
                        Text("Unlimited").tag(Int64(-1))
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }

            Section("Current Usage") {
                HStack {
                    Text("History Items")
                    Spacer()
                    Text("\(viewModel.entryCount)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Disk Usage")
                    Spacer()
                    Text(viewModel.storageSize)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Section("Maintenance") {
                Button("Clear Unpinned Items") { viewModel.requestClear(.unpinned) }
                Button("Clear Today's Items") { viewModel.requestClear(.today) }
                Button("Clear This Week's Items") { viewModel.requestClear(.thisWeek) }
                Button("Clear All History", role: .destructive) { viewModel.requestClear(.all) }
            }
        }
        .formStyle(.grouped)
        .onAppear { viewModel.calculateStorageSize() }
        .alert("Clear Clipboard History?", isPresented: $viewModel.showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { viewModel.performClear() }
        } message: {
            Text(viewModel.confirmationMessage(for: viewModel.clearScope))
        }
    }
}

// MARK: - Privacy

@MainActor
final class PrivacySettingsViewModel: ObservableObject {
    let privacyManager: PrivacyManager
    let historyStore: ClipboardHistoryStore

    @Published var newAppBundleID = ""

    init(privacyManager: PrivacyManager, historyStore: ClipboardHistoryStore) {
        self.privacyManager = privacyManager
        self.historyStore = historyStore
    }

    var excludedAppBundleIDs: [String] {
        Array(privacyManager.excludedAppBundleIDs).sorted()
    }

    var excludeSensitiveContent: Bool {
        get { privacyManager.excludeSensitiveContent }
        set { privacyManager.setExcludeSensitiveContent(newValue) }
    }

    var excludePasswords: Bool {
        get { privacyManager.excludePasswords }
        set { privacyManager.setExcludePasswords(newValue) }
    }

    var excludePasswordManagers: Bool {
        get { privacyManager.excludePasswordManagers }
        set { privacyManager.setExcludePasswordManagers(newValue) }
    }

    func addExcludedApp() {
        guard !newAppBundleID.isEmpty else { return }
        privacyManager.addExcludedApp(newAppBundleID)
        newAppBundleID = ""
    }

    func removeExcludedApp(_ bundleID: String) {
        privacyManager.removeExcludedApp(bundleID)
    }

    func appName(for bundleID: String) -> String? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app.localizedName
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            return bundle.localizedInfoDictionary?["CFBundleName"] as? String ?? bundle.infoDictionary?["CFBundleName"] as? String
        }
        return nil
    }

    func appIcon(for bundleID: String) -> NSImage? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app.icon
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let iconName = bundle.infoDictionary?["CFBundleIconFile"] as? String {
            return NSImage(named: iconName)
        }
        return nil
    }
}

struct PrivacySettingsView: View {
    @StateObject var viewModel: PrivacySettingsViewModel

    init(viewModel: PrivacySettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    init(privacyManager: PrivacyManager, historyStore: ClipboardHistoryStore) {
        _viewModel = StateObject(wrappedValue: PrivacySettingsViewModel(privacyManager: privacyManager, historyStore: historyStore))
    }

    var body: some View {
        Form {
            Section("Content Filtering") {
                Toggle("Don't save sensitive clipboard content", isOn: Binding(
                    get: { viewModel.excludeSensitiveContent },
                    set: { viewModel.excludeSensitiveContent = $0 }
                ))

                Toggle("Don't save passwords", isOn: Binding(
                    get: { viewModel.excludePasswords },
                    set: { viewModel.excludePasswords = $0 }
                ))

                Toggle("Don't save items from password managers", isOn: Binding(
                    get: { viewModel.excludePasswordManagers },
                    set: { viewModel.excludePasswordManagers = $0 }
                ))
            }

            Section("Excluded Applications") {
                Text("Clipboard content copied from these applications will not be saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.excludedAppBundleIDs.isEmpty {
                    Text("No excluded applications")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(viewModel.excludedAppBundleIDs, id: \.self) { bundleID in
                        HStack {
                            if let icon = viewModel.appIcon(for: bundleID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "app")
                                    .foregroundStyle(.secondary)
                            }
                            Text(viewModel.appName(for: bundleID) ?? bundleID)
                            Spacer()
                            Button("Remove") { viewModel.removeExcludedApp(bundleID) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                        }
                    }
                }

                HStack {
                    TextField("Bundle ID (e.g., com.example.app)", text: $viewModel.newAppBundleID)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") { viewModel.addExcludedApp() }
                        .disabled(viewModel.newAppBundleID.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

@MainActor
final class ShortcutsSettingsViewModel: ObservableObject {
    let preferences: ShortcutPreferences

    init(preferences: ShortcutPreferences) {
        self.preferences = preferences
    }

    var shortcut: KeyboardShortcut { preferences.shortcut }
    var registrationError: String? { preferences.registrationError }

    func updateShortcut(_ shortcut: KeyboardShortcut) {
        preferences.updateShortcut(to: shortcut)
    }

    func setShortcutRecording(_ isRecording: Bool) {
        preferences.setShortcutRecording(isRecording)
    }

    func resetToDefault() {
        preferences.resetToDefault()
    }
}

struct ShortcutsSettingsView: View {
    @StateObject var viewModel: ShortcutsSettingsViewModel

    init(viewModel: ShortcutsSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    init(preferences: ShortcutPreferences) {
        _viewModel = StateObject(wrappedValue: ShortcutsSettingsViewModel(preferences: preferences))
    }

    var body: some View {
        Form {
            Section("Global Shortcuts") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Open Clipboard History")
                        Text("Works globally, even when Clipboard History is not active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShortcutRecorder(
                        shortcut: viewModel.shortcut,
                        onShortcut: viewModel.updateShortcut,
                        onRecordingChanged: viewModel.setShortcutRecording
                    )
                    .frame(width: 150, height: 28)
                }

                if let registrationError = viewModel.registrationError {
                    Label(registrationError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button("Restore Default (⌥ C)") { viewModel.resetToDefault() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

@MainActor
final class AdvancedSettingsViewModel: ObservableObject {
    let historyStore: ClipboardHistoryStore

    @Published var showExportPanel = false
    @Published var showImportPanel = false

    init(historyStore: ClipboardHistoryStore) {
        self.historyStore = historyStore
    }

    func revealStorageInFinder() {
        if let persistence = try? DiskHistoryPersistence() {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: persistence.rootURL.path)
        }
    }
}

struct AdvancedSettingsView: View {
    @StateObject var viewModel: AdvancedSettingsViewModel

    init(viewModel: AdvancedSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    init(historyStore: ClipboardHistoryStore) {
        _viewModel = StateObject(wrappedValue: AdvancedSettingsViewModel(historyStore: historyStore))
    }

    var body: some View {
        Form {
            Section("Import / Export") {
                Button("Export Clipboard History…") {
                // Export handled by fileExporter
                viewModel.showExportPanel = true
            }
                Button("Import Clipboard History…") { viewModel.showImportPanel = true }
            }

            Section("Diagnostics") {
                Button("Reveal Clipboard Storage in Finder") { viewModel.revealStorageInFinder() }
                Button("Reset All Settings") { }
                    .foregroundStyle(.red)
            }

            Section("About") {
                HStack { Text("Version"); Spacer(); Text("1.0.0").foregroundStyle(.secondary) }
                HStack { Text("Build"); Spacer(); Text("2026.09.02").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .fileExporter(
            isPresented: $viewModel.showExportPanel,
            document: ExportDocument(entries: viewModel.historyStore.entries),
            contentType: .zip,
            defaultFilename: "ClipboardHistory-\(DateFormatter.exportDate.string(from: Date()))"
        ) { _ in }
        .fileImporter(isPresented: $viewModel.showImportPanel, allowedContentTypes: [.zip]) { _ in }
    }
}

private extension DateFormatter {
    static let exportDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}