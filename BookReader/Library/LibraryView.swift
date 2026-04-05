import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastOpenedDate, order: .reverse) private var books: [Book]
    @State private var viewModel = LibraryViewModel()
    @State private var selectedBook: Book?
    @State private var showImporter = false

    var body: some View {
        Group {
            if books.isEmpty {
                emptyState
            } else {
                bookGrid
            }
        }
        .navigationTitle("书架")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.epub],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .sheet(item: $selectedBook) { book in
            NavigationStack {
                ReaderView(book: book)
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("导入中...")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task {
            // Auto-scan Books directory for any unregistered EPUBs
            await scanForUnregisteredBooks(context: modelContext)
        }
        .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("确定") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("书架空空如也", systemImage: "books.vertical")
        } description: {
            Text("点击右上角 + 导入 EPUB 电子书")
        }
    }

    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ], spacing: 16) {
                ForEach(books) { book in
                    BookCardView(book: book) {
                        book.lastOpenedDate = Date()
                        selectedBook = book
                    }
                }
            }
            .padding()
        }
    }

    private func scanForUnregisteredBooks(context: ModelContext) async {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let booksDir = docs.appendingPathComponent("Books", isDirectory: true)

        guard let contents = try? fm.contentsOfDirectory(at: booksDir, includingPropertiesForKeys: nil) else {
            return
        }

        let registeredPaths = Set(books.map(\.filePath))

        for url in contents where url.pathExtension == "epub" {
            let fileName = url.lastPathComponent
            if !registeredPaths.contains(fileName) {
                await viewModel.importBook(from: url, context: context)
            }
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await viewModel.importBook(from: url, context: modelContext)
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - UTType for EPUB

extension UTType {
    static var epub: UTType {
        UTType(filenameExtension: "epub") ?? .data
    }
}
