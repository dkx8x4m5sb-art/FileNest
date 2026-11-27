import Foundation
import SwiftUI

enum SortField: String, CaseIterable, Identifiable {
    case name, size, date

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "名称"
        case .size: return "大小"
        case .date: return "修改日期"
        }
    }
}

final class FileStore: ObservableObject {
    @Published private(set) var items: [FileItem] = []
    @Published var searchText: String = ""
    @Published var sortField: SortField = .name
    @Published var ascending: Bool = true
    @Published var errorMessage: String?
    @Published var isImportingFiles: Bool = false

    let folder: URL

    init(folder: URL) {
        self.folder = folder
        reload()
    }

    var visibleItems: [FileItem] {
        let filtered: [FileItem]
        if searchText.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return filtered.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            switch sortField {
            case .name:
                let result = lhs.name.localizedStandardCompare(rhs.name)
                if result == .orderedSame { return false }
                return ascending ? result == .orderedAscending : result == .orderedDescending
            case .size:
                return ascending ? lhs.size < rhs.size : lhs.size > rhs.size
            case .date:
                return ascending ? lhs.modified < rhs.modified : lhs.modified > rhs.modified
            }
        }
    }

    var totalFileSize: Int64 {
        items.reduce(Int64(0)) { $0 + ($1.isDirectory ? 0 : $1.size) }
    }

    var totalSizeText: String {
        FileItem.sizeFormatter.string(fromByteCount: totalFileSize)
    }

    var title: String {
        let documents = FileManager.default.documentsURL.standardizedFileURL
        if folder.standardizedFileURL == documents { return "我的文件" }
        let name = folder.lastPathComponent
        return name.isEmpty ? "我的文件" : name
    }

    func reload() {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
            items = urls.map { FileItem(url: $0) }
            errorMessage = nil
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createFolder(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        let target = uniqueDestination(for: name)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ item: FileItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 批量删除。失败项会汇总成一条提示，不中断其余项目。
    func delete(items: [FileItem]) {
        guard !items.isEmpty else { return }
        var failures: [String] = []
        for item in items {
            do {
                try FileManager.default.removeItem(at: item.url)
            } catch {
                failures.append("\(item.name)：\(error.localizedDescription)")
            }
        }
        reload()
        if !failures.isEmpty {
            errorMessage = "\(items.count - failures.count) 个已删除，\(failures.count) 个失败\n"
                + failures.prefix(2).joined(separator: "\n")
        }
    }

    /// 批量移动。目标目录内同名时自动改名为「名称 2」。
    func move(items: [FileItem], to destination: URL) {
        guard !items.isEmpty else { return }
        let target = destination.standardizedFileURL
        var failures: [String] = []
        var moved = 0

        for item in items {
            // 已经在目标目录里，跳过
            if item.url.deletingLastPathComponent().standardizedFileURL == target { continue }
            // 不能把文件夹移进它自己或它的子目录
            let sourcePath = item.url.standardizedFileURL.path
            let targetPath = target.path
            if item.isDirectory, targetPath == sourcePath || targetPath.hasPrefix(sourcePath + "/") {
                failures.append("\(item.name)：不能移动到自身目录")
                continue
            }

            let newURL = Self.uniqueDestination(for: item.name, in: destination)
            do {
                try FileManager.default.moveItem(at: item.url, to: newURL)
                moved += 1
            } catch {
                failures.append("\(item.name)：\(error.localizedDescription)")
            }
        }

        reload()
        if !failures.isEmpty {
            errorMessage = "\(moved) 个已移动，\(failures.count) 个失败\n"
                + failures.prefix(2).joined(separator: "\n")
        }
    }

    @discardableResult
    func rename(_ item: FileItem, to rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != item.name else { return false }
        let target = folder.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            errorMessage = "已存在同名项目"
            return false
        }
        do {
            try FileManager.default.moveItem(at: item.url, to: target)
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImportingFiles = true
        errorMessage = nil

        let folder = self.folder
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var failures: [String] = []
            var succeeded = 0

            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }

                let target = Self.uniqueDestination(for: url.lastPathComponent, in: folder)
                do {
                    try fm.copyItem(at: url, to: target)
                    succeeded += 1
                } catch {
                    failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isImportingFiles = false
                self.reload()
                if !failures.isEmpty {
                    let head = failures.prefix(2).joined(separator: "\n")
                    self.errorMessage = failures.count == urls.count
                        ? "导入失败\n\(head)"
                        : "\(succeeded) 个成功，\(failures.count) 个失败\n\(head)"
                }
            }
        }
    }

    /// 避免同名覆盖：`名称 2.zip`、`名称 3.zip` …
    static func uniqueDestination(for name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = folder.appendingPathComponent(next)
            index += 1
        }
        return candidate
    }

    func uniqueDestination(for name: String) -> URL {
        Self.uniqueDestination(for: name, in: folder)
    }
}
