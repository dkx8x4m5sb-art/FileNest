import XCTest
@testable import FileNest

final class ArchiveTests: XCTestCase {

    // MARK: - 样本

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        let bundle = Bundle(for: ArchiveTests.self)
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw XCTSkip("缺少测试样本 \(name).\(ext)")
        }
        return url
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - 格式嗅探

    func testDetectZip() throws {
        let url = try fixture("sample", "zip")
        XCTAssertEqual(ArchiveFormat.detect(url: url), .zip)
    }

    func testDetectTarGz() throws {
        let url = try fixture("sample", "tar.gz")
        XCTAssertEqual(ArchiveFormat.detect(url: url), .gzip)
    }

    // MARK: - 条目读取

    func testZipEntriesListed() throws {
        let url = try fixture("sample", "zip")
        let entries = try ArchiveService.entries(of: url)
        let names = entries.map { $0.name }
        XCTAssertTrue(names.contains("hello.txt"), "实际条目：\(names)")
        XCTAssertFalse(entries.contains { $0.isDirectory && $0.path.isEmpty })
    }

    // MARK: - 解压

    func testZipExtractRestoresContent() throws {
        let destination = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let source = try fixture("sample", "zip")
        try ArchiveService.extract(source, to: destination, password: nil) { _, _ in }

        let file = destination.appendingPathComponent("hello.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("hello filenest"), "实际内容：\(text)")
    }

    /// 中文文件名是最容易出问题的一环：Windows 打的包常用 GBK，
    /// 若解码路径不对会变成乱码目录。
    func testZipExtractKeepsChineseFilename() throws {
        let destination = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let source = try fixture("sample", "zip")
        try ArchiveService.extract(source, to: destination, password: nil) { _, _ in }

        let chinese = destination.appendingPathComponent("中文名.txt")
        let listing = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
        XCTAssertTrue(FileManager.default.fileExists(atPath: chinese.path),
                      "中文文件名未正确还原，实际目录：\(listing)")
        let text = try String(contentsOf: chinese, encoding: .utf8)
        XCTAssertTrue(text.contains("中文内容测试"))
    }

    func testZipExtractNestedDirectory() throws {
        let destination = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let source = try fixture("sample", "zip")
        try ArchiveService.extract(source, to: destination, password: nil) { _, _ in }

        let nested = destination.appendingPathComponent("sub/nested.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testTarGzExtract() throws {
        let destination = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let source = try fixture("sample", "tar.gz")
        try ArchiveService.extract(source, to: destination, password: nil) { _, _ in }

        let file = destination.appendingPathComponent("hello.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - 安全

    func testPathResolverBlocksTraversal() {
        let base = URL(fileURLWithPath: "/tmp/filenest-base")
        XCTAssertThrowsError(try ArchivePathResolver.resolve("../evil.txt", in: base))
        XCTAssertThrowsError(try ArchivePathResolver.resolve("a/../../evil.txt", in: base))
        XCTAssertThrowsError(try ArchivePathResolver.resolve("/etc/passwd", in: base))
        XCTAssertThrowsError(try ArchivePathResolver.resolve("a\\..\\..\\evil.txt", in: base))
        XCTAssertNoThrow(try ArchivePathResolver.resolve("a/b/c.txt", in: base))
    }

    func testPathResolverKeepsSubdirectory() throws {
        let base = URL(fileURLWithPath: "/tmp/filenest-base")
        let resolved = try ArchivePathResolver.resolve("sub/nested.txt", in: base)
        XCTAssertEqual(resolved.path, "/tmp/filenest-base/sub/nested.txt")
    }
}
