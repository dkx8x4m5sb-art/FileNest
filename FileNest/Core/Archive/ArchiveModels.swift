import Foundation
import SWCompression

enum ArchiveFormat: String {
    case zip, rar, sevenZip, tar, gzip, bzip2, xz, iso, cab, unknown

    var displayName: String {
        switch self {
        case .zip: return "ZIP"
        case .rar: return "RAR"
        case .sevenZip: return "7-Zip"
        case .tar: return "TAR"
        case .gzip: return "GZip"
        case .bzip2: return "BZip2"
        case .xz: return "XZ"
        case .iso: return "ISO"
        case .cab: return "CAB"
        case .unknown: return "未知格式"
        }
    }

    var isSupported: Bool { self != .unknown }

    /// 只能由 libarchive 处理的格式（SWCompression 不覆盖）。
    var requiresLibArchive: Bool {
        switch self {
        case .rar, .iso, .cab: return true
        default: return false
        }
    }

    static func detect(url: URL) -> ArchiveFormat {
        let head = readHead(url: url, length: 512)
        if let format = sniff(head) { return format }
        return byExtension(url.pathExtension.lowercased())
    }

    private static func readHead(url: URL, length: Int) -> [UInt8] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: length) else { return [] }
        return [UInt8](data)
    }

    private static func sniff(_ bytes: [UInt8]) -> ArchiveFormat? {
        guard bytes.count >= 4 else { return nil }

        if bytes[0] == 0x50, bytes[1] == 0x4B,
           bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07 {
            return .zip
        }
        if bytes.count >= 7, bytes[0] == 0x52, bytes[1] == 0x61, bytes[2] == 0x72,
           bytes[3] == 0x21, bytes[4] == 0x1A, bytes[5] == 0x07 {
            return .rar
        }
        if bytes.count >= 6, bytes[0] == 0x37, bytes[1] == 0x7A, bytes[2] == 0xBC,
           bytes[3] == 0xAF, bytes[4] == 0x27, bytes[5] == 0x1C {
            return .sevenZip
        }
        if bytes[0] == 0x1F, bytes[1] == 0x8B { return .gzip }
        if bytes.count >= 3, bytes[0] == 0x42, bytes[1] == 0x5A, bytes[2] == 0x68 { return .bzip2 }
        if bytes.count >= 6, bytes[0] == 0xFD, bytes[1] == 0x37, bytes[2] == 0x7A,
           bytes[3] == 0x58, bytes[4] == 0x5A, bytes[5] == 0x00 {
            return .xz
        }
        if bytes.count >= 262, bytes[257] == 0x75, bytes[258] == 0x73,
           bytes[259] == 0x74, bytes[260] == 0x61, bytes[261] == 0x72 {
            return .tar
        }
        if bytes[0] == 0x4D, bytes[1] == 0x53, bytes[2] == 0x43, bytes[3] == 0x46 { return .cab }
        return nil
    }

    static func byExtension(_ ext: String) -> ArchiveFormat {
        switch ext {
        case "zip", "cbz": return .zip
        case "rar", "cbr": return .rar
        case "7z": return .sevenZip
        case "tar": return .tar
        case "gz", "tgz": return .gzip
        case "bz2", "tbz", "tbz2": return .bzip2
        case "xz", "txz": return .xz
        case "iso": return .iso
        case "cab": return .cab
        default: return .unknown
        }
    }
}

struct ArchiveEntry: Identifiable, Hashable {
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date?

    var id: String { path }

    var name: String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let last = (trimmed as NSString).lastPathComponent
        return last.isEmpty ? trimmed : last
    }

    var depth: Int {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return max(0, parts.count - 1)
    }

    var kind: FileKind {
        FileKind.detect(name: name, isDirectory: isDirectory)
    }

    var displaySize: String {
        isDirectory ? "--" : FileItem.sizeFormatter.string(fromByteCount: size)
    }

    static func from<Info: ContainerEntryInfo>(_ info: Info) -> ArchiveEntry {
        ArchiveEntry(
            path: info.name,
            isDirectory: info.type == .directory,
            size: Int64(info.size ?? 0),
            modified: info.modificationTime
        )
    }
}

enum ArchiveError: LocalizedError {
    case unsupportedFormat
    case needPassword
    case wrongPassword
    case unsafePath(String)
    case engine(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "无法识别这个压缩包的格式"
        case .needPassword:
            return "这个压缩包被密码保护，请输入密码"
        case .wrongPassword:
            return "密码不正确"
        case .unsafePath(let path):
            return "压缩包内含可疑路径，已阻止解压：\(path)"
        case .engine(let message):
            return message
        }
    }
}
