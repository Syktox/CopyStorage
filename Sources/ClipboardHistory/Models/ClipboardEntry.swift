import AppKit
import Foundation

enum ClipboardEntryKind: String, Codable, CaseIterable, Sendable, Hashable {
    case text
    case image
    case file
    case link
    case media
    case data

    var title: String {
        switch self {
        case .text: "Text"
        case .image: "Image"
        case .file: "Files"
        case .link: "Link"
        case .media: "Media"
        case .data: "Data"
        }
    }

    var symbolName: String {
        switch self {
        case .text: "doc.text"
        case .image: "photo"
        case .file: "doc"
        case .link: "link"
        case .media: "play.rectangle"
        case .data: "doc.badge.gearshape"
        }
    }
}

struct ClipboardPayloadDescriptor: Codable, Hashable, Sendable {
    let itemIndex: Int
    let pasteboardType: String
    let filename: String
    let byteCount: Int
}

struct ClipboardEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    var lastUsedAt: Date
    let kind: ClipboardEntryKind
    let preview: String
    let availableTypes: [String]
    let payloads: [ClipboardPayloadDescriptor]
    let fileNames: [String]
    let byteCount: Int
    let contentHash: String
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        lastUsedAt: Date = .now,
        kind: ClipboardEntryKind,
        preview: String,
        availableTypes: [String],
        payloads: [ClipboardPayloadDescriptor],
        fileNames: [String] = [],
        byteCount: Int,
        contentHash: String,
        isPinned: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.kind = kind
        self.preview = preview
        self.availableTypes = availableTypes
        self.payloads = payloads
        self.fileNames = fileNames
        self.byteCount = byteCount
        self.contentHash = contentHash
        self.isPinned = isPinned
    }
}

struct CapturedClipboardPayload {
    let descriptor: ClipboardPayloadDescriptor
    let data: Data
}

struct CapturedClipboardContent {
    let entry: ClipboardEntry
    let payloads: [CapturedClipboardPayload]
    let thumbnail: NSImage?
}
