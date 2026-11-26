import SwiftUI

struct FileRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(item.kind.tint)
                .frame(width: 34, height: 34)
                .background(item.kind.tint.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 16))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        if item.isDirectory { return "文件夹" }
        let date = item.modified.formatted(date: .numeric, time: .shortened)
        return "\(item.displaySize) · \(date)"
    }
}
