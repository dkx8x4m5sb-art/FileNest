import SwiftUI

// MARK: - 设置

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var appSize: Int64 = 0
    @State private var cacheSize: Int64 = 0
    @State private var freeSpace: Int64 = 0
    @State private var isScanning = true
    @State private var showClearCache = false
    @State private var tip: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    storageRow("应用文件", value: StorageInspector.format(appSize),
                               symbol: "folder.fill", tint: .blue)
                    storageRow("缓存与临时文件", value: StorageInspector.format(cacheSize),
                               symbol: "internaldrive.fill", tint: .orange)
                    storageRow("设备可用空间", value: StorageInspector.format(freeSpace),
                               symbol: "iphone", tint: .green)
                } header: {
                    Text("存储")
                } footer: {
                    Text("应用文件包含你导入的压缩包与解压出的内容。")
                }

                Section {
                    Button(role: .destructive) {
                        showClearCache = true
                    } label: {
                        HStack {
                            Label("清除缓存", systemImage: "trash")
                            Spacer()
                            if isScanning {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isScanning || cacheSize == 0)
                } footer: {
                    Text("只清理临时文件与缓存目录，不会删除你的文件。")
                }

                Section("关于") {
                    LabeledContent("版本", value: versionText)
                    LabeledContent("解压引擎", value: "libarchive + SWCompression")
                    NavigationLink {
                        FormatSupportView()
                    } label: {
                        Label("格式支持", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task { refresh() }
            .confirmationDialog("清除缓存？", isPresented: $showClearCache, titleVisibility: .visible) {
                Button("清除", role: .destructive) { clearCache() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("不会影响已导入的文件")
            }
            .alert("已清除", isPresented: Binding(
                get: { tip != nil },
                set: { if !$0 { tip = nil } }
            )) {
                Button("好", role: .cancel) { tip = nil }
            } message: {
                Text(tip ?? "")
            }
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func storageRow(_ title: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(title)

            Spacer(minLength: 8)

            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func refresh() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let app = StorageInspector.size(at: FileManager.default.documentsURL)
            let cache = StorageInspector.cacheSize()
            let free = StorageInspector.freeSpace()
            DispatchQueue.main.async {
                self.appSize = app
                self.cacheSize = cache
                self.freeSpace = free
                self.isScanning = false
            }
        }
    }

    private func clearCache() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let freed = StorageInspector.clearCache()
            let app = StorageInspector.size(at: FileManager.default.documentsURL)
            let cache = StorageInspector.cacheSize()
            let free = StorageInspector.freeSpace()
            DispatchQueue.main.async {
                self.appSize = app
                self.cacheSize = cache
                self.freeSpace = free
                self.isScanning = false
                self.tip = "已释放 \(StorageInspector.format(freed))"
            }
        }
    }
}

// MARK: - 存储统计

enum StorageInspector {
    /// 目录的递归占用（按磁盘实际分配大小，和系统「设置」里的数字口径一致）。
    static func size(at url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: nil
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func cacheSize() -> Int64 {
        let fm = FileManager.default
        var total = size(at: fm.temporaryDirectory)
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            total += size(at: caches)
        }
        return total
    }

    /// 清空 tmp 与 Caches 下的内容，返回释放的字节数。
    @discardableResult
    static func clearCache() -> Int64 {
        let fm = FileManager.default
        var freed: Int64 = 0

        var dirs: [URL] = [fm.temporaryDirectory]
        dirs.append(contentsOf: fm.urls(for: .cachesDirectory, in: .userDomainMask))

        for dir in dirs {
            let children = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: []
            )) ?? []
            for child in children {
                freed += size(at: child)
                try? fm.removeItem(at: child)
            }
        }
        return freed
    }

    static func freeSpace() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - 格式支持

struct FormatSupportView: View {
    private struct Row: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
    }

    private let extraction: [Row] = [
        Row(name: "ZIP", detail: "zip · cbz，支持 ZipCrypto / AES 加密"),
        Row(name: "RAR / RAR5", detail: "rar · cbr，密码已透传"),
        Row(name: "7-Zip", detail: "7z，不支持加密包"),
        Row(name: "TAR", detail: "tar"),
        Row(name: "GZip", detail: "gz · tgz，内层 tar 自动展开"),
        Row(name: "BZip2", detail: "bz2 · tbz · tbz2"),
        Row(name: "XZ", detail: "xz · txz"),
        Row(name: "ISO / CAB", detail: "iso · cab")
    ]

    private let preview: [Row] = [
        Row(name: "图片", detail: "jpg · png · gif · heic · webp · tiff · bmp，可缩放"),
        Row(name: "PDF", detail: "PDFKit 连续滚动"),
        Row(name: "文本 / 代码", detail: "txt · md · json · xml · swift · py 等，自动识别 GB18030"),
        Row(name: "音频 / 视频", detail: "mp3 · m4a · wav · flac · mp4 · mov"),
        Row(name: "Office", detail: "docx · xlsx · pptx，经系统 QuickLook")
    ]

    var body: some View {
        List {
            Section {
                ForEach(extraction) { row in
                    LabeledContent(row.name, value: row.detail)
                        .font(.system(size: 14))
                }
            } header: {
                Text("可解压")
            } footer: {
                Text("格式靠文件头魔数识别，改扩展名也能认出来。")
            }

            Section("可预览") {
                ForEach(preview) { row in
                    LabeledContent(row.name, value: row.detail)
                        .font(.system(size: 14))
                }
            }

            Section {
                Text("DMG、ARJ、LZH、ACE、Z、分卷压缩包、加密 7z，以及老版 doc/xls、CAD、加密 PDF、DRM 音视频。遇到这些会明确提示，不会静默失败。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } header: {
                Text("暂不支持")
            }
        }
        .navigationTitle("格式支持")
        .navigationBarTitleDisplayMode(.inline)
    }
}
