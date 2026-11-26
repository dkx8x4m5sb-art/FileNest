import SwiftUI

/// 快捷指令风格的网格卡片：彩色渐变底 + 半透明图标块 + 底部两行文字
struct FileCard: View {
    let item: FileItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(0.20))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: item.kind.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                Spacer(minLength: 4)

                Circle()
                    .fill(.white.opacity(0.20))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
            }

            Spacer(minLength: 8)

            Text(item.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .padding(.top, 3)
        }
        .padding(12)
        .frame(height: 136, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(
                    colors: item.kind.gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 底部压暗，保证白色文字在浅色渐变上依然可读
                LinearGradient(
                    colors: [.clear, .black.opacity(0.28)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var subtitle: String {
        if item.isDirectory { return "文件夹" }
        return item.displaySize
    }
}
