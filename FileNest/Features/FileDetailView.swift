import SwiftUI
import QuickLook
import UIKit

struct FileDetailView: View {
    let item: FileItem
    @State private var showPreview = false

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    Image(systemName: item.kind.symbol)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(item.kind.tint)
                        .frame(width: 84, height: 84)
                        .background(item.kind.tint.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("文件信息") {
                infoRow("名称", item.name)
                infoRow("大小", item.displaySize)
                infoRow("修改时间", item.modified.formatted(date: .numeric, time: .shortened))
                infoRow("路径", item.url.deletingLastPathComponent().path)
            }

            Section {
                Button {
                    showPreview = true
                } label: {
                    Label("预览", systemImage: "eye")
                }
                ShareLink(item: item.url) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPreview) {
            QuickLookView(url: item.url)
                .ignoresSafeArea()
        }
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 15))
    }
}

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
