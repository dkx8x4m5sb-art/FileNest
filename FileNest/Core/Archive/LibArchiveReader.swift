import Foundation

/// libarchive 的最小封装。负责 ZIP（含加密）、RAR / RAR5、ISO、CAB。
///
/// libarchive 的常量宏（`ARCHIVE_OK` / `ARCHIVE_EOF`）不会导入到 Swift，
/// 这里直接用字面量：0 = OK，1 = EOF，负数 = 错误。
final class LibArchiveReader {
    private var handle: OpaquePointer?

    init(path: String, password: String?) throws {
        guard let archive = archive_read_new() else {
            throw ArchiveError.engine("无法初始化解压器")
        }
        archive_read_support_filter_all(archive)
        archive_read_support_format_all(archive)
        if let password = password, !password.isEmpty {
            archive_read_add_passphrase(archive, password)
        }

        let status = archive_read_open_filename(archive, path, 64 * 1024)
        guard status == 0 else {
            let message = LibArchiveReader.message(of: archive)
            archive_read_free(archive)
            throw LibArchiveReader.translate(message, suppliedPassword: password?.isEmpty == false)
        }
        self.handle = archive
    }

    deinit { close() }

    func close() {
        guard let archive = handle else { return }
        archive_read_close(archive)
        archive_read_free(archive)
        handle = nil
    }

    func forEachEntry(_ body: (ArchiveEntry) -> Void) throws {
        guard let archive = handle else { return }
        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(archive, &entry)
            if status == 1 { return }
            if status < 0 {
                throw LibArchiveReader.translate(LibArchiveReader.message(of: archive), suppliedPassword: false)
            }
            guard let entry = entry else { return }
            body(LibArchiveReader.makeEntry(entry))
            _ = archive_read_data_skip(archive)
        }
    }

    func extract(to destination: URL, total: Int, progress: (Double, String) -> Void) throws {
        guard let archive = handle else { return }
        let fileManager = FileManager.default
        var entry: OpaquePointer?
        var index = 0

        while true {
            let status = archive_read_next_header(archive, &entry)
            if status == 1 { return }
            if status < 0 {
                throw LibArchiveReader.translate(LibArchiveReader.message(of: archive), suppliedPassword: false)
            }
            guard let entry = entry else { return }

            let info = LibArchiveReader.makeEntry(entry)
            index += 1
            let target = try ArchivePathResolver.resolve(info.path, in: destination)

            if info.isDirectory {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else if !info.path.isEmpty {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: target.path) {
                    try? fileManager.removeItem(at: target)
                }
                fileManager.createFile(atPath: target.path, contents: nil)
                let output = try FileHandle(forWritingTo: target)
                defer { try? output.close() }

                var buffer = [UInt8](repeating: 0, count: 128 * 1024)
                while true {
                    let read = buffer.withUnsafeMutableBytes { raw -> Int in
                        guard let base = raw.baseAddress else { return 0 }
                        return Int(archive_read_data(archive, base, raw.count))
                    }
                    if read < 0 {
                        throw LibArchiveReader.translate(LibArchiveReader.message(of: archive),
                                                         suppliedPassword: false)
                    }
                    if read == 0 { break }
                    try output.write(contentsOf: Data(bytes: buffer, count: read))
                }
            }

            let fraction = total > 0 ? Double(index) / Double(total) : 0
            progress(min(max(fraction, 0), 1), info.name)
        }
    }

    // MARK: - Helpers

    private static func makeEntry(_ entry: OpaquePointer) -> ArchiveEntry {
        let path = archive_entry_pathname(entry).map { String(cString: $0) } ?? ""
        let mode = Int(archive_entry_filetype(entry))
        let isDirectory = (mode & 0o170000) == 0o040000
        let size = archive_entry_size(entry)
        let mtime = archive_entry_mtime(entry)
        let modified = mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil
        return ArchiveEntry(path: path,
                            isDirectory: isDirectory,
                            size: size > 0 ? size : 0,
                            modified: modified)
    }

    private static func message(of archive: OpaquePointer) -> String {
        guard let pointer = archive_error_string(archive) else { return "解压失败" }
        return String(cString: pointer)
    }

    private static func translate(_ message: String, suppliedPassword: Bool) -> ArchiveError {
        let lower = message.lowercased()
        let mentionsPassword = lower.contains("passphrase") || lower.contains("password")
            || lower.contains("encrypted")
        if mentionsPassword {
            if suppliedPassword || lower.contains("incorrect") || lower.contains("invalid") {
                return .wrongPassword
            }
            return .needPassword
        }
        return .engine(message)
    }
}
