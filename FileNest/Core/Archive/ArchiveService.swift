import Foundation
import SWCompression

enum ArchiveService {

    /// 列出条目。加密 ZIP 与 RAR 走 libarchive，其余走纯 Swift 实现。
    static func entries(of url: URL, password: String? = nil) throws -> [ArchiveEntry] {
        switch ArchiveFormat.detect(url: url) {
        case .zip, .rar, .iso, .cab:
            return try libarchiveEntries(url, password: password)
        case .sevenZip:
            let data = try Data(contentsOf: url)
            return try SevenZipContainer.open(container: data).map { ArchiveEntry.from($0.info) }
        case .tar:
            let data = try Data(contentsOf: url)
            return try TarContainer.open(container: data).map { ArchiveEntry.from($0.info) }
        case .gzip, .bzip2, .xz:
            return [singleEntry(url)]
        case .unknown:
            throw ArchiveError.unsupportedFormat
        }
    }

    static func extract(_ url: URL,
                        to destination: URL,
                        password: String?,
                        progress: (Double, String) -> Void) throws {
        let format = ArchiveFormat.detect(url: url)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        switch format {
        case .zip, .rar, .iso, .cab:
            let total = (try? libarchiveEntries(url, password: password).count) ?? 0
            let reader = try LibArchiveReader(path: url.path, password: password)
            defer { reader.close() }
            try reader.extract(to: destination, total: total, progress: progress)

        case .sevenZip:
            let data = try Data(contentsOf: url)
            let items = try SevenZipContainer.open(container: data)
            let pairs = items.map { (ArchiveEntry.from($0.info), $0.data) }
            try write(pairs, to: destination, progress: progress)

        case .tar:
            let data = try Data(contentsOf: url)
            let items = try TarContainer.open(container: data)
            let pairs = items.map { (ArchiveEntry.from($0.info), $0.data) }
            try write(pairs, to: destination, progress: progress)

        case .gzip, .bzip2, .xz:
            let data = try Data(contentsOf: url)
            let payload: Data
            switch format {
            case .gzip: payload = try GzipArchive.unarchive(archive: data)
            case .bzip2: payload = try BZip2.decompress(data: data)
            default: payload = try XZArchive.unarchive(archive: data)
            }
            let entry = singleEntry(url)
            let target = try ArchivePathResolver.resolve(entry.path, in: destination)
            try payload.write(to: target)
            progress(1, entry.name)

        case .unknown:
            throw ArchiveError.unsupportedFormat
        }
    }

    // MARK: - Helpers

    private static func libarchiveEntries(_ url: URL, password: String?) throws -> [ArchiveEntry] {
        let reader = try LibArchiveReader(path: url.path, password: password)
        defer { reader.close() }
        var result: [ArchiveEntry] = []
        try reader.forEachEntry { result.append($0) }
        return result
    }

    private static func singleEntry(_ url: URL) -> ArchiveEntry {
        var name = url.lastPathComponent
        for ext in ["gz", "bz2", "xz"] where name.lowercased().hasSuffix("." + ext) {
            name = String(name.dropLast(ext.count + 1))
            break
        }
        return ArchiveEntry(path: name, isDirectory: false, size: 0, modified: nil)
    }

    private static func write(_ items: [(ArchiveEntry, Data?)],
                              to destination: URL,
                              progress: (Double, String) -> Void) throws {
        let fileManager = FileManager.default
        for (index, item) in items.enumerated() {
            let entry = item.0
            let payload = item.1
            guard !entry.path.isEmpty else { continue }
            let target = try ArchivePathResolver.resolve(entry.path, in: destination)
            if entry.isDirectory {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else if let payload = payload {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                try payload.write(to: target)
            }
            let fraction = Double(index + 1) / Double(max(items.count, 1))
            progress(min(fraction, 1), entry.name)
        }
    }
}
