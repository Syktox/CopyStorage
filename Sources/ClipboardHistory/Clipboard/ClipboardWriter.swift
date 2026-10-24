import AppKit

final class ClipboardWriter {
    func restore(_ entry: ClipboardEntry, from persistence: DiskHistoryPersistence) throws {
        let groupedPayloads = Dictionary(grouping: entry.payloads, by: \.itemIndex)
        let pasteboardItems = try groupedPayloads.keys.sorted().map { itemIndex -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for descriptor in groupedPayloads[itemIndex] ?? [] {
                let data = try persistence.data(for: descriptor, in: entry)
                item.setData(data, forType: NSPasteboard.PasteboardType(descriptor.pasteboardType))
            }

            // Some applications only accept TIFF when pasting an image,
            // even if the original clipboard item only exposed PNG/JPEG.
            if entry.kind == .image,
               item.data(forType: .tiff) == nil,
               let imageDescriptor = (groupedPayloads[itemIndex] ?? []).first(where: {
                   $0.pasteboardType.hasPrefix("public.image") ||
                   $0.pasteboardType == "public.png" ||
                   $0.pasteboardType == "public.jpeg"
               }),
               let imageData = try? persistence.data(for: imageDescriptor, in: entry),
               let image = NSImage(data: imageData),
               let tiffData = image.tiffRepresentation {
                item.setData(tiffData, forType: .tiff)
            }
            return item
        }

        guard !pasteboardItems.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects(pasteboardItems) else {
            throw ClipboardWriterError.writeFailed
        }
    }
}

private enum ClipboardWriterError: Error {
    case writeFailed
}
