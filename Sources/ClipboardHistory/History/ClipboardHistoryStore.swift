import Combine
import AppKit
import Foundation

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var selectedEntryID: ClipboardEntry.ID?
    @Published private(set) var lastErrorMessage: String?

    private let persistence: DiskHistoryPersistence?
    private let writer: ClipboardWriter
    let maximumEntries: Int
    let maximumStorageBytes: Int64

    init(
        persistence: DiskHistoryPersistence? = nil,
        writer: ClipboardWriter = ClipboardWriter(),
        maximumEntries: Int = 250,
        maximumStorageBytes: Int64 = 1_000_000_000
    ) {
        self.persistence = persistence ?? (try? DiskHistoryPersistence())
        self.writer = writer
        self.maximumEntries = maximumEntries
        self.maximumStorageBytes = maximumStorageBytes

        if let persistence = self.persistence {
            do {
                entries = Self.sorted(try persistence.loadEntries())
            } catch {
                lastErrorMessage = "Saved clipboard history could not be loaded."
            }
        } else {
            lastErrorMessage = "Clipboard history could not be stored locally."
        }
    }

    func ingest(_ captured: CapturedClipboardContent) {
        if let duplicateIndex = entries.firstIndex(where: { $0.contentHash == captured.entry.contentHash }) {
            var duplicate = entries.remove(at: duplicateIndex)
            duplicate.lastUsedAt = .now
            entries.insert(duplicate, at: 0)
            selectedEntryID = duplicate.id
            saveIndex()
            return
        }

        guard let persistence else {
            lastErrorMessage = "Clipboard history could not be stored locally."
            return
        }

        do {
            try persistence.savePayloads(for: captured)
            if let thumbnail = captured.thumbnail {
                try persistence.saveThumbnail(thumbnail, for: captured.entry)
            }
            entries.insert(captured.entry, at: 0)
            selectedEntryID = captured.entry.id
            enforceEntryLimit()
            enforceStorageLimit()
            saveIndex()
        } catch {
            lastErrorMessage = "This clipboard item could not be saved."
        }
    }

    func restore(_ entry: ClipboardEntry) {
        guard let persistence else {
            lastErrorMessage = "Clipboard history is not available locally."
            return
        }

        do {
            try writer.restore(entry, from: persistence)
            touch(entry.id)
        } catch {
            lastErrorMessage = "This clipboard item could not be restored."
        }
    }

    func thumbnail(for entry: ClipboardEntry) -> NSImage? {
        persistence?.loadThumbnail(for: entry)
    }

    func togglePin(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isPinned.toggle()
        entries = Self.sorted(entries)
        saveIndex()
    }

    func delete(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        selectedEntryID = entries.first?.id
        do {
            try persistence?.removePayloads(for: entry)
        } catch {
            lastErrorMessage = "The saved data for this item could not be removed."
        }
        saveIndex()
    }

    func clearUnpinned() {
        let removed = entries.filter { !$0.isPinned }
        entries.removeAll { !$0.isPinned }
        selectedEntryID = entries.first?.id
        for entry in removed {
            try? persistence?.removePayloads(for: entry)
        }
        saveIndex()
    }

    func clearEntries(olderThan date: Date, includePinned: Bool = false) {
        let toRemove = entries.filter { entry in
            entry.createdAt < date && (includePinned || !entry.isPinned)
        }
        entries.removeAll { toRemove.contains($0) }
        selectedEntryID = entries.first?.id
        for entry in toRemove {
            try? persistence?.removePayloads(for: entry)
        }
        saveIndex()
    }

    func clearAll(includePinned: Bool = false) {
        let toRemove = entries.filter { includePinned || !$0.isPinned }
        entries.removeAll { toRemove.contains($0) }
        selectedEntryID = entries.first?.id
        for entry in toRemove {
            try? persistence?.removePayloads(for: entry)
        }
        saveIndex()
    }

    func focusLatest() {
        selectedEntryID = entries.first?.id
    }

    func moveSelection(by offset: Int, among visibleEntries: [ClipboardEntry]) {
        guard !visibleEntries.isEmpty else {
            selectedEntryID = nil
            return
        }
        guard let selectedEntryID,
              let currentIndex = visibleEntries.firstIndex(where: { $0.id == selectedEntryID })
        else {
            self.selectedEntryID = visibleEntries[0].id
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), visibleEntries.count - 1)
        self.selectedEntryID = visibleEntries[nextIndex].id
    }

    func selectedEntry(in visibleEntries: [ClipboardEntry]) -> ClipboardEntry? {
        visibleEntries.first { $0.id == selectedEntryID }
    }

    func setLimits(maximumEntries: Int, maximumStorageBytes: Int64) {
        // Note: These are immutable after init. For runtime changes, recreate the store.
        enforceEntryLimit()
        enforceStorageLimit()
    }

    private func touch(_ id: ClipboardEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries.remove(at: index)
        entry.lastUsedAt = .now
        entries.insert(entry, at: 0)
        entries = Self.sorted(entries)
        selectedEntryID = entry.id
        saveIndex()
    }

    private func enforceEntryLimit() {
        guard maximumEntries > 0 else { return }
        while entries.count > maximumEntries,
              let oldestUnpinnedIndex = entries.indices
                .filter({ !entries[$0].isPinned })
                .min(by: { entries[$0].lastUsedAt < entries[$1].lastUsedAt })
        {
            let removed = entries.remove(at: oldestUnpinnedIndex)
            try? persistence?.removePayloads(for: removed)
        }
        entries = Self.sorted(entries)
    }

    private func enforceStorageLimit() {
        guard maximumStorageBytes > 0, let persistence else { return }
        Task.detached { [weak self, maximumStorageBytes] in
            await self?.cleanupIfOverLimit(persistence: persistence, maxBytes: maximumStorageBytes)
        }
    }

    private func cleanupIfOverLimit(persistence: DiskHistoryPersistence, maxBytes: Int64) async {
        do {
            let currentSize = try await Task.detached(priority: .utility) {
                try persistence.calculateTotalStorageSize()
            }.value

            guard currentSize > maxBytes else { return }

            let sortedEntries = entries
                .filter { !$0.isPinned }
                .sorted { $0.lastUsedAt < $1.lastUsedAt }

            var currentSizeMutable = currentSize
            for entry in sortedEntries {
                guard currentSizeMutable > maxBytes else { break }
                let itemURL = persistence.rootURL
                    .appendingPathComponent("Items", isDirectory: true)
                    .appendingPathComponent(entry.id.uuidString, isDirectory: true)
                if let size = try? FileManager.default.allocatedSizeOfDirectory(at: itemURL) {
                    try? persistence.removePayloads(for: entry)
                    currentSizeMutable -= Int64(size)
                }
            }

            await MainActor.run {
                self.entries.removeAll { sortedEntries.contains($0) }
                self.selectedEntryID = self.entries.first?.id
                self.saveIndex()
            }
        } catch {
            await MainActor.run {
                self.lastErrorMessage = "Storage cleanup failed."
            }
        }
    }

    private func saveIndex() {
        do {
            try persistence?.saveEntries(entries)
        } catch {
            lastErrorMessage = "Clipboard history could not be updated."
        }
    }

    private static func sorted(_ entries: [ClipboardEntry]) -> [ClipboardEntry] {
        entries.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.lastUsedAt > $1.lastUsedAt
        }
    }
}
