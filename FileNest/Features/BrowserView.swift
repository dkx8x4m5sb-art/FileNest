import SwiftUI
import UniformTypeIdentifiers

struct BrowserView: View {
    @StateObject private var store: FileStore

    @State private var isImporting = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var pendingDelete: FileItem?
    @State private var showDeleteDialog = false

    init(folder: URL) {
        _store = StateObject(wrappedValue: FileStore(folder: folder))
    }

    var body: some View {
        List {
            ForEach(store.visibleItems) { item in
                row(for: item)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = item
                            showDeleteDialog = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .overlay { emptyState }
        .navigationTitle(store.title)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $store.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索文件")
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                store.importFiles(urls)
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .alert("新建文件夹", isPresented: $showNewFolder) {
            TextField("名称", text: $newFolderName)
            Button("取消", role: .cancel) { newFolderName = "" }
            Button("创建") {
                store.createFolder(named: newFolderName)
                newFolderName = ""
            }
        } message: {
            Text("在当前目录下创建一个新文件夹")
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
        .alert("出错了", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func row(for item: FileItem) -> some View {
        if item.isDirectory {
            NavigationLink {
                BrowserView(folder: item.url)
            } label: {
                FileRow(item: item)
            }
        } else {
            NavigationLink {
                FileDetailView(item: item)
            } label: {
                FileRow(item: item)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.visibleItems.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: store.searchText.isEmpty ? "tray" : "magnifyingglass")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(store.searchText.isEmpty ? "这里还没有文件" : "没有匹配的项目")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if store.searchText.isEmpty {
                    Text("点右下角「导入」从「文件」中添加")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Picker("排序方式", selection: $store.sortField) {
                    ForEach(SortField.allCases) { field in
                        Text(field.label).tag(field)
                    }
                }
                Button {
                    store.ascending.toggle()
                } label: {
                    Label(store.ascending ? "改为降序" : "改为升序",
                          systemImage: store.ascending ? "arrow.down" : "arrow.up")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showNewFolder = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
        }

        ToolbarItem(placement: .bottomBar) {
            HStack {
                Text("\(store.visibleItems.count) 项 · \(store.totalSizeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    Label("导入", systemImage: "plus")
                }
            }
        }
    }
}
