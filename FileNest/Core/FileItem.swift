import Foundation
import SwiftUI

struct FileItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let modified: Date

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var kind: FileKind { FileKind.detect(name: name, isDirectory: isDirectory) }

    init(url: URL) {
        self.url = url
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let values = try? url.resourceValues(forKeys: keys)
        self.isDirectory = values?.isDirectory ?? false
        self.size = Int64(values?.fileSize ?? 0)
        self.modified = values?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
    }

    static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()

    var displaySize: String {
        isDirectory ? "文件夹" : FileItem.sizeFormatter.string(fromByteCount: size)
    }
}

extension FileManager {
    var documentsURL: URL {
        urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

enum FileKind {
    case folder, archive, image, video, audio, pdf, code, text, other

    static func detect(name: String, isDirectory: Bool) -> FileKind {
        if isDirectory { return .folder }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "tbz2",
             "xz", "txz", "cab", "iso", "lz", "lzma", "zst":
            return .archive
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp", "svg":
            return .image
        case "mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm":
            return .video
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "aiff", "caf":
            return .audio
        case "pdf":
            return .pdf
        case "swift", "js", "ts", "py", "java", "kt", "c", "h", "m", "mm",
             "cpp", "hpp", "go", "rs", "rb", "php", "cs", "sh", "json",
             "yml", "yaml", "xml", "html", "css", "scss", "sql", "toml":
            return .code
        case "txt", "md", "log", "csv", "tsv", "rtf":
            return .text
        default:
            return .other
        }
    }

    var symbol: String {
        switch self {
        case .folder: return "folder.fill"
        case .archive: return "archivebox.fill"
        case .image: return "photo.fill"
        case .video: return "play.rectangle.fill"
        case .audio: return "waveform"
        case .pdf: return "doc.text.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "doc.plaintext.fill"
        case .other: return "doc.fill"
        }
    }
}

extension FileKind {
    var tint: Color {
        switch self {
        case .folder: return .blue
        case .archive: return .orange
        case .image: return .green
        case .video: return .pink
        case .audio: return .purple
        case .pdf: return .red
        case .code: return .indigo
        case .text: return .gray
        case .other: return .secondary
        }
    }

    /// 卡片渐变：沿用「快捷指令」按类别着色的语义，颜色与文件类型一一对应
    var gradient: [Color] {
        switch self {
        case .folder:  return [Color(hex: 0x3FA9F5), Color(hex: 0x0066CC)]
        case .archive: return [Color(hex: 0xFFB340), Color(hex: 0xE0590A)]
        case .image:   return [Color(hex: 0x4ADE80), Color(hex: 0x129C46)]
        case .video:   return [Color(hex: 0xFF7A94), Color(hex: 0xD3244A)]
        case .audio:   return [Color(hex: 0xC77DFF), Color(hex: 0x8A3FD1)]
        case .pdf:     return [Color(hex: 0xFF8079), Color(hex: 0xC4302A)]
        case .code:    return [Color(hex: 0x8B88FF), Color(hex: 0x4A47D6)]
        case .text:    return [Color(hex: 0x9A9AA1), Color(hex: 0x5C5C63)]
        case .other:   return [Color(hex: 0x8E8E93), Color(hex: 0x48484C)]
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
