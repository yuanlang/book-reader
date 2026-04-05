import SwiftUI

struct ReaderView: View {
    let book: Book

    @State private var viewModel = ReaderViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            viewModel.navigatorView
                .ignoresSafeArea()

            VStack {
                Spacer()
                TTSControlPanel(viewModel: viewModel)
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("返回") { dismiss() }
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
