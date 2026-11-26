import Foundation

/// 把压缩包内的相对路径解析为安全的落地路径，阻止 `../` 逃逸与绝对路径写入。
enum ArchivePathResolver {
    static func resolve(_ path: String, in base: URL) throws -> URL {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !normalized.hasPrefix("/"), !parts.contains("..") else {
            throw ArchiveError.unsafePath(path)
        }
        var url = base
        for part in parts where part != "." && !part.isEmpty {
            url.appendPathComponent(part)
        }
        return url
    }
}
