import SwiftUI
import UniformTypeIdentifiers

struct BrowserView: View {
    @StateObject private var store: FileStore
    @Environment(\.dismiss) private var dismiss

    /// 根目录没有上一级，不显示返回按钮
    private let isRoot: Bool

    @State private var isImporting = false

    @State private var promptMode: PromptMode = .newFolder
    @State private var showPrompt = false
    @State private var promptText = ""

    @State private var pendingDelete: FileItem?
    @State private var showDeleteDialog = false

    private enum PromptMode {
        case newFolder
        case rename(FileItem)
    }

    init(folder: URL, isRoot: Bool = false) {
        _store = StateObject(wrappedValue: FileStore(folder: folder))
        self.isRoot = isRoot
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                titleSection
                searchField
                content
            }

            // 底部渐隐，避免滚动内容直接怼在悬浮按钮下面
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 96)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 14) {
                if let error = store.errorMessage {
                    toast(error)
                }
                importButton
            }
            .padding(.bottom, 10)

            if store.isImportingFiles {
                importingOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isImportingFiles)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isImporting) {
            DocumentPicker(
                onPick: { urls in
                    isImporting = false
                    store.importFiles(urls)
                },
                onCancel: { isImporting = false }
            )
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "删除「\(pendingDelete?.name ?? "")」？",
            isPresented: $showDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let item = pendingDelete { store.delete(item) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("此操作不可撤销")
        }
        .alert(promptTitle, isPresented: $showPrompt) {
            TextField("名称", text: $promptText)
            Button("取消", role: .cancel) { promptText = "" }
            Button("确定") { commitPrompt() }
        } message: {
            Text(promptMessage)
        }
        .task(id: store.errorMessage) {
            guard store.errorMessage != nil else { return }
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            withAnimation(.easeOut(duration: 0.2)) { store.errorMessage = nil }
        }
    }

    // MARK: - 顶部

    private var topBar: some View {
        HStack(spacing: 12) {
            if isRoot {
                Color.clear.frame(width: 44, height: 42)
            } else {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 42)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Menu {
                    Picker("排序方式", selection: $store.sortField) {
                        ForEach(SortField.allCases) { field in
                            Text(field.label).tag(field)
                        }
                    }
                    Divider()
                    Button {
                        store.ascending.toggle()
                    } label: {
                        Label(store.ascending ? "改为降序" : "改为升序",
                              systemImage: store.ascending ? "arrow.down" : "arrow.up")
                    }
                } label: {
                    capsuleIcon("arrow.up.arrow.down")
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 20)

                Button {
                    promptMode = .newFolder
                    promptText = ""
                    showPrompt = true
                } label: {
                    capsuleIcon("folder.badge.plus")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建文件夹")
            }
            .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func capsuleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 46, height: 42)
    }

    private var titleSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(store.title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            Text("\(store.visibleItems.count) 项")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("搜索", text: $store.searchText)
                .font(.system(size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if store.visibleItems.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(store.visibleItems) { item in
                        cardLink(for: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func cardLink(for item: FileItem) -> some View {
        Group {
            if item.isDirectory {
                NavigationLink {
                    BrowserView(folder: item.url)
                } label: {
                    FileCard(item: item)
                }
            } else if item.kind == .archive {
                NavigationLink {
                    ArchiveBrowserView(item: item)
                } label: {
                    FileCard(item: item)
                }
            } else {
                NavigationLink {
                    FileDetailView(item: item)
                } label: {
                    FileCard(item: item)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                // 等长按菜单收起后再弹输入框，否则弹窗会被菜单的消失动画吞掉
                Task {
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    promptMode = .rename(item)
                    promptText = item.name
                    showPrompt = true
                }
            } label: {
                Label("重命名", systemImage: "pencil")
            }

            Button(role: .destructive) {
                Task {
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    pendingDelete = item
                    showDeleteDialog = true
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.searchText.isEmpty ? "square.stack.3d.up" : "magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.quaternary)

            Text(store.searchText.isEmpty ? "这里还没有文件" : "没有匹配的项目")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            if store.searchText.isEmpty {
                Text("点下方 ＋ 从「文件」导入压缩包")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 悬浮导入按钮

    private var importButton: some View {
        Button {
            isImporting = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 58, height: 58)
                .background(Color(.secondarySystemBackground), in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.28), radius: 14, y: 5)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("导入文件")
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .tint(.primary)
                Text("正在导入")
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color.red.opacity(0.92), in: Capsule())
            .padding(.horizontal, 32)
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - 命名弹窗

    private var promptTitle: String {
        switch promptMode {
        case .newFolder: return "新建文件夹"
        case .rename: return "重命名"
        }
    }

    private var promptMessage: String {
        switch promptMode {
        case .newFolder:
            return "在当前目录下创建一个新文件夹"
        case .rename(let item):
            return "为「\(item.name)」输入新名称"
        }
    }

    private func commitPrompt() {
        let text = promptText
        promptText = ""
        switch promptMode {
        case .newFolder:
            store.createFolder(named: text)
        case .rename(let item):
            store.rename(item, to: text)
        }
    }
}
