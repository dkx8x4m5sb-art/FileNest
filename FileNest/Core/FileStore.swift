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
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let target = uniqueDestination(for: url.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: url, to: target)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        reload()
    }

    func uniqueDestination(for name: String) -> URL {
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
}
