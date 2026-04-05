import SwiftUI

struct BookCardView: View {
    let book: Book
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Cover image or placeholder
                Group {
                    if let coverData = book.coverImageData,
                       let uiImage = UIImage(data: coverData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            VStack(spacing: 4) {
                                Image(systemName: "book.closed")
                                    .font(.title)
                                    .foregroundStyle(.white)
                                Text(String(book.title.prefix(4)))
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(2)
                            }
                            .padding(8)
                        }
                    }
                }
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                // Title and author
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    if !book.author.isEmpty {
                        Text(book.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                // Delete handled by parent
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
