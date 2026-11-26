import SwiftUI

struct ArchiveBrowserView: View {
    let item: FileItem

    @Environment(\.dismiss) private var dismiss

    @State private var entries: [ArchiveEntry] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var promptPassword = false
    @State private var password = ""
    @State private var passwordError: String?
    @State private var isExtracting = false
    @State private var progress: Double = 0
    @State private var currentEntry = ""
    @State private var resultText: String?
    @State private var showResult = false
    @State private var sourceRemoved = false

    private var format: ArchiveFormat { ArchiveFormat.detect(url: item.url) }

    var body: some View {
        List {
            Section {
                ForEach(entries) { entry in
                    row(entry)
                }
            } header: {
                Text("\(format.displayName) · \(entries.count) 项")
            }
        }
        .listStyle(.plain)
        .overlay {
            if isLoading {
                ProgressView("读取中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        extract(removingSource: false)
                    } label: {
                        Label("解压到此处", systemImage: "arrow.down.doc")
                    }

                    Button {
                        extract(removingSource: true)
                    } label: {
                        Label("解压并删除源压缩包", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "arrow.down.doc")
                }
                .disabled(isLoading || entries.isEmpty || isExtracting)
            }
        }
        .sheet(isPresented: $promptPassword) {
            passwordSheet
        }
        .overlay { extractingOverlay }
        .alert("已解压", isPresented: $showResult) {
            if !sourceRemoved {
                Button("删除源压缩包", role: .destructive) { removeSource() }
            }
            Button("完成", role: .cancel) { dismiss() }
        } message: {
            Text(resultText ?? "")
        }
        // 挂在独立的背景视图上，避免和上面的弹窗互相覆盖
        .background {
            Color.clear.alert("出错了", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
        .task { load() }
    }

    private func row(_ entry: ArchiveEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(entry.kind.tint)
                .frame(width: 26, height: 26)
                .background(entry.kind.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(entry.name)
                .font(.system(size: 15))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(entry.displaySize)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, CGFloat(min(entry.depth, 5)) * 14)
    }

    @ViewBuilder
    private var extractingOverlay: some View {
        if isExtracting {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 190)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(currentEntry)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 190)
                }
                .padding(24)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var passwordSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("密码", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("这个压缩包已加密，需要正确密码才能读取内容")
                }

                if let passwordError = passwordError {
                    Section {
                        Text(passwordError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("解锁") {
                        passwordError = nil
                        load()
                    }
                    .disabled(password.isEmpty || isLoading)
                }
            }
            .navigationTitle("输入密码")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(300)])
    }

    // MARK: - Actions

    private func load() {
        isLoading = true
        let url = item.url
        let pwd = password.isEmpty ? nil : password
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let list = try ArchiveService.entries(of: url, password: pwd)
                DispatchQueue.main.async {
                    self.entries = list
                    self.isLoading = false
                    self.promptPassword = false
                    self.passwordError = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let archiveError = error as? ArchiveError {
                        switch archiveError {
                        case .needPassword, .wrongPassword:
                            self.promptPassword = true
                            self.passwordError = archiveError.localizedDescription
                        default:
                            self.errorText = archiveError.localizedDescription
                        }
                    } else {
                        self.errorText = error.localizedDescription
                    }
                }
            }
        }
    }

    private func extract(removingSource: Bool) {
        isExtracting = true
        progress = 0
        currentEntry = ""
        sourceRemoved = false

        let url = item.url
        let pwd = password.isEmpty ? nil : password
        let destination = destinationURL()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try ArchiveService.extract(url, to: destination, password: pwd) { value, name in
                    DispatchQueue.main.async {
                        self.progress = value
                        self.currentEntry = name
                    }
                }

                var removed = false
                if removingSource {
                    removed = (try? FileManager.default.removeItem(at: url)) != nil
                }

                DispatchQueue.main.async {
                    self.isExtracting = false
                    self.sourceRemoved = removed
                    self.resultText = removed
                        ? "已解压到「\(destination.lastPathComponent)」，源压缩包已删除"
                        : "已解压到「\(destination.lastPathComponent)」"
                    self.showResult = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExtracting = false
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    private func removeSource() {
        do {
            try FileManager.default.removeItem(at: item.url)
            sourceRemoved = true
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func destinationURL() -> URL {
        let parent = item.url.deletingLastPathComponent()
        var base = item.url.lastPathComponent
        let strippable: Set<String> = ["tar", "gz", "bz2", "xz", "tgz", "tbz", "tbz2", "txz"]
        while let dot = base.lastIndex(of: "."), dot != base.startIndex {
            let ext = String(base[base.index(after: dot)...]).lowercased()
            guard strippable.contains(ext) else { break }
            base = String(base[..<dot])
        }
        if base.isEmpty { base = "解压结果" }

        var candidate = parent.appendingPathComponent(base, isDirectory: true)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(base) \(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }
}
