import Foundation

extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> Int {
        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey, .totalFileAllocatedSizeKey]
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles])
        var totalSize = 0

        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if values.isDirectory != true {
                totalSize += values.totalFileAllocatedSize ?? values.fileSize ?? 0
            }
        }
        return totalSize
    }
}