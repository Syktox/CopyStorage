import SwiftUI
import UniformTypeIdentifiers

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    let entries: [ClipboardEntry]

    init(entries: [ClipboardEntry]) {
        self.entries = entries
    }

    init(configuration: ReadConfiguration) throws {
        // Not needed for export-only
        self.entries = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryExport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let persistence = try? DiskHistoryPersistence()

        let metadata = entries.map { entry -> [String: Any] in
            let dict: [String: Any] = [
                "id": entry.id.uuidString,
                "createdAt": ISO8601DateFormatter().string(from: entry.createdAt),
                "lastUsedAt": ISO8601DateFormatter().string(from: entry.lastUsedAt),
                "kind": entry.kind.rawValue,
                "preview": entry.preview,
                "availableTypes": entry.availableTypes,
                "fileNames": entry.fileNames,
                "byteCount": entry.byteCount,
                "contentHash": entry.contentHash,
                "isPinned": entry.isPinned
            ]
            return dict
        }

        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        let metadataURL = tempDir.appendingPathComponent("metadata.json")
        try metadataData.write(to: metadataURL)

        if let persistence {
            for entry in entries {
                let itemDir = tempDir.appendingPathComponent("Items").appendingPathComponent(entry.id.uuidString)
                try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)

                for descriptor in entry.payloads {
                    let data = try persistence.data(for: descriptor, in: entry)
                    let fileURL = itemDir.appendingPathComponent(descriptor.filename)
                    try data.write(to: fileURL)
                }

                if let thumbnail = persistence.loadThumbnail(for: entry) {
                    let thumbURL = itemDir.appendingPathComponent("thumbnail.png")
                    if let tiffData = thumbnail.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        try pngData.write(to: thumbURL)
                    }
                }
            }
        }

        let zipURL = tempDir.appendingPathExtension("zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", tempDir.path, zipURL.path]
        try process.run()
        process.waitUntilExit()

        let fileWrapper = try FileWrapper(url: zipURL, options: .immediate)
        try FileManager.default.removeItem(at: tempDir)
        return fileWrapper
    }
}
