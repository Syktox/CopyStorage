import AppKit
import AVFoundation
import CryptoKit
import Foundation
import UniformTypeIdentifiers

final class ClipboardSnapshotter {
    /// A capture that exceeds this limit is ignored rather than retaining an
    /// unbounded amount of memory while another application owns the pasteboard.
    private let maximumCaptureBytes: Int
    private let maximumThumbnailSize = CGSize(width: 256, height: 256)

    init(maximumCaptureBytes: Int = 100 * 1_024 * 1_024) {
        self.maximumCaptureBytes = maximumCaptureBytes
    }

    func snapshot(from pasteboard: NSPasteboard = .general) async -> CapturedClipboardContent? {
        var pasteboardItems = pasteboard.pasteboardItems ?? []

        // A few applications expose copied text through `string(forType:)`
        // without providing a usable pasteboardItems array. Preserve that
        // text instead of treating the clipboard as empty.
        if pasteboardItems.isEmpty,
           let text = pasteboard.string(forType: .string),
           !text.isEmpty {
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            pasteboardItems = [item]
        }

        guard !pasteboardItems.isEmpty else { return nil }

        var capturedPayloads: [CapturedClipboardPayload] = []
        var availableTypes = Set<String>()
        var totalBytes = 0
        var hasher = SHA256()
        var thumbnail: NSImage? = nil
        var mediaMetadata: MediaMetadata? = nil

        for (itemIndex, item) in pasteboardItems.enumerated() {
            for type in item.types.sorted(by: { $0.rawValue < $1.rawValue }) {
                let data = item.data(forType: type)
                    ?? textData(for: item, type: type)
                guard let data, !data.isEmpty else { continue }
                guard totalBytes + data.count <= maximumCaptureBytes else { continue }

                let filename = "\(itemIndex)-\(capturedPayloads.count).bin"
                let descriptor = ClipboardPayloadDescriptor(
                    itemIndex: itemIndex,
                    pasteboardType: type.rawValue,
                    filename: filename,
                    byteCount: data.count
                )
                capturedPayloads.append(CapturedClipboardPayload(descriptor: descriptor, data: data))
                availableTypes.insert(type.rawValue)
                totalBytes += data.count

                hasher.update(data: Data(type.rawValue.utf8))
                hasher.update(data: data)

                if thumbnail == nil {
                    if isImageType(type.rawValue), let image = NSImage(data: data) {
                        thumbnail = makeThumbnail(from: image)
                    } else if isVideoType(type.rawValue), mediaMetadata == nil {
                        mediaMetadata = await extractVideoMetadata(from: data)
                    }
                }
            }
        }

        guard !capturedPayloads.isEmpty else { return nil }

        let fileURLs = readFileURLs(from: pasteboard)
        let kind = detectKind(types: availableTypes, fileURLs: fileURLs)
        let preview = makePreview(from: pasteboard, kind: kind, fileURLs: fileURLs, mediaMetadata: mediaMetadata)
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let now = Date()
        let entry = ClipboardEntry(
            createdAt: now,
            lastUsedAt: now,
            kind: kind,
            preview: preview,
            availableTypes: availableTypes.sorted(),
            payloads: capturedPayloads.map(\.descriptor),
            fileNames: fileURLs.map(\.lastPathComponent),
            byteCount: totalBytes,
            contentHash: hash
        )
        return CapturedClipboardContent(entry: entry, payloads: capturedPayloads, thumbnail: thumbnail)
    }

    private func textData(for item: NSPasteboardItem, type: NSPasteboard.PasteboardType) -> Data? {
        guard type == .string || type.rawValue == "public.utf8-plain-text",
              let text = item.string(forType: type),
              !text.isEmpty else { return nil }
        return text.data(using: .utf8)
    }

    private func isImageType(_ type: String) -> Bool {
        let imageTypes = [
            "public.png", "public.jpeg", "public.tiff", "com.compuserve.gif",
            "public.heic", "public.heif", "public.bmp", "public.ico",
            "com.apple.icns", "com.microsoft.bmp", "com.adobe.pdf"
        ]
        return imageTypes.contains(type) || type.hasPrefix("public.image")
    }

    private func isVideoType(_ type: String) -> Bool {
        return type.hasPrefix("public.movie") ||
               type.hasPrefix("public.video") ||
               type.hasPrefix("public.audio") ||
               type == "com.compuserve.gif" ||
               type == "com.apple.quicktime-movie" ||
               type == "com.microsoft.waveform-audio" ||
               type == "public.mpeg-4" ||
               type == "public.3gpp" ||
               type == "public.mpeg"
    }

    private struct MediaMetadata {
        let duration: TimeInterval?
        let dimensions: CGSize?
        let codec: String?
    }

    private func extractVideoMetadata(from data: Data) async -> MediaMetadata? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-media-\(UUID().uuidString)")

        do {
            try data.write(to: tempURL)
            let asset = AVAsset(url: tempURL)

            let duration = try? await asset.load(.duration)
            let durationSeconds = duration?.seconds ?? 0
            
            let tracks = try? await asset.loadTracks(withMediaType: .video)
            let firstTrack = tracks?.first
            
            let dimensions = try? await firstTrack?.load(.naturalSize)
            let formatDescriptions = try? await firstTrack?.load(.formatDescriptions)
            
            let codec = formatDescriptions?.first.flatMap { formatDesc in
                CMFormatDescriptionGetMediaSubType(formatDesc).fourCharCodeString
            }

            try? FileManager.default.removeItem(at: tempURL)

            return MediaMetadata(
                duration: durationSeconds.isFinite ? durationSeconds : nil,
                dimensions: dimensions,
                codec: codec
            )
        } catch {
            return nil
        }
    }

    private func makeThumbnail(from image: NSImage) -> NSImage {
        let thumbnailSize = maximumThumbnailSize
        let ratio = min(thumbnailSize.width / image.size.width, thumbnailSize.height / image.size.height)
        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)

        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0)
        thumbnail.unlockFocus()
        return thumbnail
    }

    private func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []

        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )?.compactMap({ $0 as? URL }), !fileURLs.isEmpty {
            urls.append(contentsOf: fileURLs)
        }

        if let urlObjects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.compactMap({ $0 as? URL }) {
            for url in urlObjects where url.isFileURL {
                if !urls.contains(where: { $0.path == url.path }) {
                    urls.append(url)
                }
            }
        }

        if urls.isEmpty,
           let fileNames = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            for fileName in fileNames {
                let url = URL(fileURLWithPath: fileName)
                if !urls.contains(where: { $0.path == url.path }) {
                    urls.append(url)
                }
            }
        }

        if urls.isEmpty,
           let fileContents = pasteboard.propertyList(forType: .fileContents) as? [String] {
            for fileName in fileContents {
                let url = URL(fileURLWithPath: fileName)
                if !urls.contains(where: { $0.path == url.path }) {
                    urls.append(url)
                }
            }
        }

        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func detectKind(types: Set<String>, fileURLs: [URL]) -> ClipboardEntryKind {
        if !fileURLs.isEmpty { return .file }
        if types.contains(where: isImageType) { return .image }
        if types.contains(where: isVideoType) { return .media }
        if types.contains(NSPasteboard.PasteboardType.URL.rawValue) || types.contains("public.url") {
            return .link
        }
        if types.contains(NSPasteboard.PasteboardType.string.rawValue) {
            return .text
        }
        return .data
    }

    private func makePreview(
        from pasteboard: NSPasteboard,
        kind: ClipboardEntryKind,
        fileURLs: [URL],
        mediaMetadata: MediaMetadata?
    ) -> String {
        if !fileURLs.isEmpty {
            if fileURLs.count == 1 { return fileURLs[0].lastPathComponent }
            return "\(fileURLs.count) files"
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return String(text.prefix(2_000))
        }
        if let url = pasteboard.string(forType: .URL), !url.isEmpty { return url }
        switch kind {
        case .image: return "Image"
        case .media:
            if let metadata = mediaMetadata {
                var parts: [String] = []
                if let duration = metadata.duration {
                    parts.append(formatDuration(duration))
                }
                if let dimensions = metadata.dimensions {
                    parts.append("\(Int(dimensions.width))×\(Int(dimensions.height))")
                }
                if let codec = metadata.codec {
                    parts.append(codec)
                }
                return parts.joined(separator: " • ")
            }
            return "Media"
        case .data: return "Clipboard data"
        case .text, .file, .link: return "Clipboard item"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) % 3600 / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

private extension FourCharCode {
    var fourCharCodeString: String {
        let bytes: [UInt8] = [
            UInt8(self >> 24 & 0xFF),
            UInt8(self >> 16 & 0xFF),
            UInt8(self >> 8 & 0xFF),
            UInt8(self & 0xFF)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? ""
    }
}
