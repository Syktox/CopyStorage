@testable import ClipboardHistory
import Carbon.HIToolbox
import XCTest

final class KeyboardShortcutTests: XCTestCase {
    func testControlCommandVIsTheDefaultShortcut() {
        XCTAssertEqual(KeyboardShortcut.controlCommandV.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(KeyboardShortcut.controlCommandV.carbonModifiers, UInt32(controlKey | cmdKey))
        XCTAssertEqual(KeyboardShortcut.controlCommandV.displayString, "⌃⌘ V")
    }

    func testShortcutWithoutModifierIsRejected() {
        XCTAssertFalse(KeyboardShortcut(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: 0).isUsable)
    }
}

@MainActor
final class ClipboardHistoryStoreTests: XCTestCase {
    func testDuplicateMovesExistingEntryToTheTopWithoutCreatingAnotherPayload() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = try DiskHistoryPersistence(rootURL: root)
        let store = ClipboardHistoryStore(persistence: persistence)

        let first = capturedContent(preview: "first", hash: "same")
        store.ingest(first)
        let duplicate = capturedContent(preview: "duplicate", hash: "same")
        store.ingest(duplicate)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.id, first.entry.id)
        XCTAssertEqual(store.entries.first?.preview, "first")
    }

    func testPersistenceRoundTripKeepsEntryAndPayload() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = try DiskHistoryPersistence(rootURL: root)
        let captured = capturedContent(preview: "Saved text", hash: "hash")

        try persistence.savePayloads(for: captured)
        try persistence.saveEntries([captured.entry])

        XCTAssertEqual(try persistence.loadEntries(), [captured.entry])
        let saved = try persistence.data(for: captured.entry.payloads[0], in: captured.entry)
        XCTAssertEqual(saved, Data("Saved text".utf8))
    }

    func testMultipleTextEntriesAreStoredAndRestored() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = try DiskHistoryPersistence(rootURL: root)
        let store = ClipboardHistoryStore(persistence: persistence)

        let text1 = "First copied text"
        let text2 = "Second copied text"
        let text3 = "Third copied text"

        let captured1 = capturedContent(preview: text1, hash: "hash1")
        let captured2 = capturedContent(preview: text2, hash: "hash2")
        let captured3 = capturedContent(preview: text3, hash: "hash3")

        store.ingest(captured1)
        store.ingest(captured2)
        store.ingest(captured3)

        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries[0].preview, text3)
        XCTAssertEqual(store.entries[1].preview, text2)
        XCTAssertEqual(store.entries[2].preview, text1)

        store.restore(store.entries[1])
        store.restore(store.entries[0])
        store.restore(store.entries[2])

        XCTAssertEqual(store.entries[0].preview, text1)
        XCTAssertEqual(store.entries[1].preview, text3)
        XCTAssertEqual(store.entries[2].preview, text2)
    }

    func testSearchFiltersEntriesCorrectly() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = try DiskHistoryPersistence(rootURL: root)
        let store = ClipboardHistoryStore(persistence: persistence)

        let captured1 = capturedContent(preview: "Hello World", hash: "hash1")
        let captured2 = capturedContent(preview: "Swift Programming", hash: "hash2")
        let captured3 = capturedContent(preview: "Xcode Development", hash: "hash3")

        store.ingest(captured1)
        store.ingest(captured2)
        store.ingest(captured3)

        let viewModel = ClipboardHistoryViewModel(historyStore: store, onClose: {})
        viewModel.searchText = "Swift"
        XCTAssertEqual(viewModel.visibleEntries.count, 1)
        XCTAssertEqual(viewModel.visibleEntries.first?.preview, "Swift Programming")

        viewModel.searchText = "Develop"
        XCTAssertEqual(viewModel.visibleEntries.count, 1)
        XCTAssertEqual(viewModel.visibleEntries.first?.preview, "Xcode Development")

        viewModel.searchText = ""
        XCTAssertEqual(viewModel.visibleEntries.count, 3)
    }

    func testPinKeepsEntryAtTop() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = try DiskHistoryPersistence(rootURL: root)
        let store = ClipboardHistoryStore(persistence: persistence)

        let captured1 = capturedContent(preview: "First", hash: "hash1")
        let captured2 = capturedContent(preview: "Second", hash: "hash2")
        let captured3 = capturedContent(preview: "Third", hash: "hash3")

        store.ingest(captured1)
        store.ingest(captured2)
        store.ingest(captured3)

        let firstEntry = store.entries[2]
        store.togglePin(firstEntry)

        XCTAssertEqual(store.entries[0].id, firstEntry.id)
        XCTAssertTrue(store.entries[0].isPinned)

        let captured4 = capturedContent(preview: "Fourth", hash: "hash4")
        store.ingest(captured4)

        XCTAssertEqual(store.entries[0].id, firstEntry.id)
        XCTAssertEqual(store.entries[1].preview, "Fourth")
    }

    func testImageEntryShowsFilenameInPreview() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = try DiskHistoryPersistence(rootURL: root)
        let store = ClipboardHistoryStore(persistence: persistence)

        let descriptor = ClipboardPayloadDescriptor(
            itemIndex: 0,
            pasteboardType: "public.png",
            filename: "image.png",
            byteCount: 1024
        )
        let entry = ClipboardEntry(
            createdAt: Date(timeIntervalSince1970: 1_000),
            lastUsedAt: Date(timeIntervalSince1970: 1_000),
            kind: .image,
            preview: "Image",
            availableTypes: ["public.png"],
            payloads: [descriptor],
            fileNames: ["screenshot.png"],
            byteCount: 1024,
            contentHash: "imagehash"
        )
        let captured = CapturedClipboardContent(
            entry: entry,
            payloads: [CapturedClipboardPayload(descriptor: descriptor, data: Data())],
            thumbnail: nil
        )

        store.ingest(captured)

        let viewModel = ClipboardHistoryViewModel(historyStore: store, onClose: {})
        let rowVM = ClipboardEntryRowViewModel(entry: store.entries[0], isLatest: true, isSelected: false, action: {})

        XCTAssertEqual(rowVM.previewText, "screenshot.png")
    }

    func testMediaEntryShowsFilenameInPreview() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = try DiskHistoryPersistence(rootURL: root)
        let store = ClipboardHistoryStore(persistence: persistence)

        let descriptor = ClipboardPayloadDescriptor(
            itemIndex: 0,
            pasteboardType: "public.mpeg-4",
            filename: "video.mp4",
            byteCount: 2048
        )
        let entry = ClipboardEntry(
            createdAt: Date(timeIntervalSince1970: 1_000),
            lastUsedAt: Date(timeIntervalSince1970: 1_000),
            kind: .media,
            preview: "Media",
            availableTypes: ["public.mpeg-4"],
            payloads: [descriptor],
            fileNames: ["recording.mp4"],
            byteCount: 2048,
            contentHash: "mediahash"
        )
        let captured = CapturedClipboardContent(
            entry: entry,
            payloads: [CapturedClipboardPayload(descriptor: descriptor, data: Data())],
            thumbnail: nil
        )

        store.ingest(captured)

        let rowVM = ClipboardEntryRowViewModel(entry: store.entries[0], isLatest: true, isSelected: false, action: {})

        XCTAssertEqual(rowVM.previewText, "recording.mp4")
    }

    func testEntryKindIndicatorLetters() {
        XCTAssertEqual(ClipboardEntryKind.text.indicatorLetter, "T")
        XCTAssertEqual(ClipboardEntryKind.image.indicatorLetter, "I")
        XCTAssertEqual(ClipboardEntryKind.file.indicatorLetter, "F")
        XCTAssertEqual(ClipboardEntryKind.link.indicatorLetter, "L")
        XCTAssertEqual(ClipboardEntryKind.media.indicatorLetter, "M")
        XCTAssertEqual(ClipboardEntryKind.data.indicatorLetter, "D")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func capturedContent(preview: String, hash: String) -> CapturedClipboardContent {
        let descriptor = ClipboardPayloadDescriptor(
            itemIndex: 0,
            pasteboardType: "public.utf8-plain-text",
            filename: "0-0.bin",
            byteCount: preview.utf8.count
        )
        let entry = ClipboardEntry(
            createdAt: Date(timeIntervalSince1970: 1_000),
            lastUsedAt: Date(timeIntervalSince1970: 1_000),
            kind: .text,
            preview: preview,
            availableTypes: [descriptor.pasteboardType],
            payloads: [descriptor],
            byteCount: descriptor.byteCount,
            contentHash: hash
        )
        return CapturedClipboardContent(
            entry: entry,
            payloads: [CapturedClipboardPayload(descriptor: descriptor, data: Data(preview.utf8))]
        )
    }
}
