import SwiftUI
import UIKit
import PDFKit
import AVKit
import QuickLook
import CoreFoundation

/// 自带关闭按钮的预览容器。
///
/// 之前把 `QLPreviewController` 直接塞进 `.sheet`，它没有导航控制器，
/// 就不会生成自己的「完成」按钮；页面又是全屏黑底，于是只能杀进程退出。
/// 现在的做法是：外层由我们自己画顶栏，任何格式都保证有一个关闭入口。
struct PreviewView: View {
    let item: FileItem

    @Environment(\.dismiss) private var dismiss

    @State private var text: String?
    @State private var textNote: String?
    @State private var image: UIImage?
    @State private var failed = false
    @State private var loaded = false

    private var mode: PreviewMode { PreviewMode(item: item) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                content
            }
        }
        .preferredColorScheme(.dark)
        .task { load() }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭预览")

            Text(item.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            ShareLink(item: item.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .image:
            if let image = image {
                ZoomableImageView(image: image)
                    .ignoresSafeArea(edges: .bottom)
            } else if failed {
                unsupported
            } else {
                loading
            }

        case .text:
            textContent

        case .pdf:
            PDFKitContainer(url: item.url)
                .ignoresSafeArea(edges: .bottom)

        case .media:
            PlayerContainer(url: item.url)
                .ignoresSafeArea(edges: .bottom)

        case .quickLook:
            QuickLookContainer(url: item.url)

        case .unsupported:
            unsupported
        }
    }

    private var textDesign: Font.Design {
        if case .code = item.kind { return .monospaced }
        return .default
    }

    private var loading: some View {
        ProgressView()
            .tint(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var textContent: some View {
        Group {
            if let text = text {
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let note = textNote {
                            Label(note, systemImage: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.horizontal, 16)
                        }

                        Text(text)
                            .font(.system(size: 13, weight: .regular, design: textDesign))
                            .foregroundStyle(.white.opacity(0.92))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 28)
                    }
                    .padding(.top, 4)
                }
            } else if failed {
                unsupported
            } else {
                loading
            }
        }
    }

    private var unsupported: some View {
        VStack(spacing: 14) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.35))

            Text("这个格式暂时无法预览")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text("\(item.displaySize) · \(item.url.pathExtension.uppercased())")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))

            ShareLink(item: item.url) {
                Label("分享到其他 App 打开", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.14), in: Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    // MARK: - 载入

    private func load() {
        guard !loaded else { return }
        loaded = true

        switch mode {
        case .image:
            image = UIImage(contentsOfFile: item.url.path)
            failed = (image == nil)
        case .text:
            loadText()
        default:
            break
        }
    }

    private func loadText() {
        let limit = 4 * 1024 * 1024
        guard let handle = try? FileHandle(forReadingFrom: item.url) else {
            failed = true
            return
        }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: limit)) ?? Data()
        guard let decoded = Self.decode(data) else {
            failed = true
            return
        }
        text = decoded
        textNote = item.size > Int64(limit) ? "文件较大，仅显示前 4 MB" : nil
    }

    /// Windows 上打的文本常是 GBK/GB18030，直接按 UTF-8 读会全是问号。
    private static func decode(_ data: Data) -> String? {
        if data.isEmpty { return "" }
        if let value = String(data: data, encoding: .utf8) { return value }

        let gb = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let value = String(data: data, encoding: String.Encoding(rawValue: gb)) { return value }

        if let value = String(data: data, encoding: .utf16) { return value }
        return String(data: data, encoding: .isoLatin1)
    }
}

// MARK: - 预览模式判定

private enum PreviewMode {
    case image, text, pdf, media, quickLook, unsupported

    init(item: FileItem) {
        let ext = item.url.pathExtension.lowercased()

        switch item.kind {
        case .image:
            // SVG 是文本，交回给系统渲染
            self = (ext == "svg") ? .quickLook : .image
        case .pdf:
            self = .pdf
        case .video, .audio:
            self = .media
        case .code, .text:
            self = .text
        case .folder, .archive:
            self = .unsupported
        case .other:
            let textLike: Set<String> = [
                "plist", "conf", "config", "ini", "cfg", "env", "strings",
                "entitlements", "pbxproj", "gradle", "lock", "rst", "tex",
                "srt", "vtt", "diff", "patch"
            ]
            self = textLike.contains(ext) ? .text : .quickLook
        }
    }
}

// MARK: - 图片（可缩放）

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .clear
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.delegate = context.coordinator
        scroll.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])

        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5,
                                  height: scroll.bounds.height / 2.5)
                let rect = CGRect(x: point.x - size.width / 2,
                                  y: point.y - size.height / 2,
                                  width: size.width,
                                  height: size.height)
                scroll.zoom(to: rect, animated: true)
            }
        }
    }
}

// MARK: - PDF

struct PDFKitContainer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = .black
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - 音视频

struct PlayerContainer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

// MARK: - QuickLook（Office 等）

struct QuickLookContainer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
