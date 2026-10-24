import AppKit
import Foundation

/// Keeps metadata separate from pasteboard bytes so history can survive app and
/// system restarts without loading all copied data into memory.
final class DiskHistoryPersistence {
    private let fileManager: FileManager
    let rootURL: URL
    private let blobsURL: URL
    private let thumbnailsURL: URL
    private let indexURL: URL

    init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = appSupport
                .appendingPathComponent("ClipboardHistory", isDirectory: true)
        }
        blobsURL = self.rootURL.appendingPathComponent("Items", isDirectory: true)
        thumbnailsURL = self.rootURL.appendingPathComponent("Thumbnails", isDirectory: true)
        indexURL = self.rootURL.appendingPathComponent("history.json")

        try fileManager.createDirectory(at: blobsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
    }

    func loadEntries() throws -> [ClipboardEntry] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        return try JSONDecoder.history.decode([ClipboardEntry].self, from: data)
    }

    func savePayloads(for captured: CapturedClipboardContent) throws {
        let itemURL = blobsURL.appendingPathComponent(captured.entry.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: itemURL, withIntermediateDirectories: true)

        for payload in captured.payloads {
            let destination = itemURL.appendingPathComponent(payload.descriptor.filename)
            try payload.data.write(to: destination, options: .atomic)
        }
    }

    func saveEntries(_ entries: [ClipboardEntry]) throws {
        let data = try JSONEncoder.history.encode(entries)
        try data.write(to: indexURL, options: .atomic)
    }

    func data(for descriptor: ClipboardPayloadDescriptor, in entry: ClipboardEntry) throws -> Data {
        let url = blobsURL
            .appendingPathComponent(entry.id.uuidString, isDirectory: true)
            .appendingPathComponent(descriptor.filename)
        return try Data(contentsOf: url)
    }

    func removePayloads(for entry: ClipboardEntry) throws {
        let itemURL = blobsURL.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: itemURL.path) else { return }
        try fileManager.removeItem(at: itemURL)

        let thumbURL = thumbnailsURL.appendingPathComponent("\(entry.id.uuidString).png")
        if fileManager.fileExists(atPath: thumbURL.path) {
            try fileManager.removeItem(at: thumbURL)
        }
    }

    func thumbnailURL(for entry: ClipboardEntry) -> URL {
        thumbnailsURL.appendingPathComponent("\(entry.id.uuidString).png")
    }

    func saveThumbnail(_ image: NSImage, for entry: ClipboardEntry) throws {
        let url = thumbnailURL(for: entry)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        try pngData.write(to: url, options: .atomic)
    }

    func loadThumbnail(for entry: ClipboardEntry) -> NSImage? {
        let url = thumbnailURL(for: entry)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    func calculateTotalStorageSize() throws -> Int64 {
        var totalSize: Int64 = 0
        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]

        for directory in [blobsURL, thumbnailsURL] {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                if values.isDirectory != true {
                    totalSize += Int64(values.fileSize ?? 0)
                }
            }
        }
        return totalSize
    }
}

private extension JSONEncoder {
    static let history: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let history: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
