import SwiftUI

struct BookCardView: View {
    let book: Book
    let progress: Double
    let onTap: () -> Void
    let onDelete: () -> Void

    private var hasProgress: Bool { progress > 0 }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Cover image or placeholder
                ZStack(alignment: .bottom) {
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

                    // Progress bar overlay at bottom of cover
                    if hasProgress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(.black.opacity(0.3))
                                    .frame(height: 3)
                                Rectangle()
                                    .fill(.white.opacity(0.9))
                                    .frame(width: geo.size.width * min(progress, 1.0), height: 3)
                            }
                        }
                        .frame(height: 3)
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
                    }
                }
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

                    if hasProgress {
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
