import SwiftUI

/// 移动目标选择器：从「我的文件」开始逐级下钻，选中的目录即目标。
/// 正在移动的文件夹本身及其子目录会被隐藏，避免把文件夹移进自己里面。
struct MoveDestinationsView: View {
    let items: [FileItem]
    let onMove: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    private let blocked: [String]

    init(items: [FileItem], onMove: @escaping (URL) -> Void) {
        self.items = items
        self.onMove = onMove
        self.blocked = items
            .filter { $0.isDirectory }
            .map { $0.url.standardizedFileURL.path }
    }

    var body: some View {
        NavigationStack {
            FolderLevel(
                folder: FileManager.default.documentsURL,
                blocked: blocked,
                onMove: { url in
                    onMove(url)
                    dismiss()
                }
            )
            .navigationTitle("移动到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct FolderLevel: View {
    let folder: URL
    let blocked: [String]
    let onMove: (URL) -> Void

    @State private var subfolders: [URL] = []

    var body: some View {
        List {
            Section {
                Button {
                    onMove(folder)
                } label: {
                    Label("移动到这里", systemImage: "arrow.down.to.line")
                        .font(.system(size: 16, weight: .medium))
                }
            } footer: {
                Text(displayPath)
            }

            Section("子文件夹") {
                if subfolders.isEmpty {
                    Text("没有子文件夹")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(subfolders, id: \.self) { url in
                        NavigationLink {
                            FolderLevel(folder: url, blocked: blocked, onMove: onMove)
                        } label: {
                            Label(url.lastPathComponent, systemImage: "folder.fill")
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.lastPathComponent.isEmpty ? "我的文件" : folder.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private var displayPath: String {
        let root = FileManager.default.documentsURL.standardizedFileURL.path
        let current = folder.standardizedFileURL.path
        guard current.hasPrefix(root) else { return current }
        let relative = String(current.dropFirst(root.count))
        return relative.isEmpty ? "/" : relative
    }

    private func load() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        subfolders = urls.filter { url in
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            return !isBlocked(url)
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func isBlocked(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return blocked.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
