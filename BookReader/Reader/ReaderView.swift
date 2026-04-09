import SwiftUI

struct ReaderView: View {
    let book: Book

    @State private var viewModel = ReaderViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showTTSPanel = false
    @State private var showTOC = false

    var body: some View {
        VStack(spacing: 0) {
            // EPUB 内容视图
            viewModel.navigatorView

            // TTS 控制面板
            if showTTSPanel || viewModel.isPlaying {
                TTSControlPanel(viewModel: viewModel)
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: TTSPanelHeightPreferenceKey.self,
                            value: geo.size.height
                        )
                    })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onPreferenceChange(TTSPanelHeightPreferenceKey.self) { height in
            viewModel.ttsPanelHeight = height
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showTOC = true
                } label: {
                    Image(systemName: "list.bullet")
                }

                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        showTTSPanel.toggle()
                    }
                } label: {
                    Image(systemName: viewModel.isPlaying ? "waveform" : "speaker.wave.2")
                }
            }
        }
        .sheet(isPresented: $showTOC) {
            TOCView(items: viewModel.tableOfContents) { item in
                viewModel.navigateToTOCItem(item)
                showTOC = false
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("加载中...")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task {
            await viewModel.open(book: book, context: modelContext)
        }
    }
}

// MARK: - Table of Contents View

private struct TOCView: View {
    let items: [TOCItem]
    let onSelect: (TOCItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                TOCSection(items: items, level: 0, onSelect: onSelect)
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct TOCSection: View {
    let items: [TOCItem]
    let level: Int
    let onSelect: (TOCItem) -> Void

    var body: some View {
        ForEach(items) { item in
            Button {
                onSelect(item)
            } label: {
                HStack {
                    if level > 0 {
                        Spacer()
                            .frame(width: CGFloat(level) * 16)
                    }
                    Text(item.title)
                        .foregroundStyle(.primary)
                        .font(level == 0 ? .body : .subheadline)
                    Spacer()
                }
            }
            .accessibilityLabel(item.title)

            if !item.children.isEmpty {
                TOCSection(items: item.children, level: level + 1, onSelect: onSelect)
            }
        }
    }
}

// MARK: - Preference Keys

private struct TTSPanelHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
