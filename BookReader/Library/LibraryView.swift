import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastOpenedDate, order: .reverse) private var books: [Book]
    @Query private var readingProgresses: [ReadingProgress]
    @State private var viewModel = LibraryViewModel()
    @State private var selectedBook: Book?
    @State private var showImporter = false
    @State private var searchText = ""
    @State private var showError = false

    private var progressMap: [UUID: Double] {
        var map = [UUID: Double]()
        for p in readingProgresses {
            map[p.bookId] = p.progress
        }
        return map
    }

    private var filteredBooks: [Book] {
        if searchText.isEmpty {
            return books
        }
        return books.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.author.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if books.isEmpty {
                emptyState
            } else if filteredBooks.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                bookGrid
            }
        }
        .navigationTitle("书架")
        .searchable(text: $searchText, prompt: "搜索书名或作者")
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
        .fullScreenCover(item: $selectedBook) { book in
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
            await scanForUnregisteredBooks(context: modelContext)
        }
        .alert("错误", isPresented: $showError) {
            Button("确定") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if newValue != nil {
                showError = true
            }
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
            LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                ForEach(filteredBooks) { book in
                    BookCardView(book: book, progress: progressMap[book.id] ?? 0) {
                        book.lastOpenedDate = Date()
                        selectedBook = book
                    } onDelete: {
                        viewModel.deleteBook(book, context: modelContext)
                    }
                }
            }
            .padding()
        }
    }

    private var adaptiveColumns: [GridItem] {
        let columnCount: Int
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            columnCount = 4
        } else {
            columnCount = 2
        }
        #else
        columnCount = 2
        #endif
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
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
                await viewModel.registerBook(at: url, fileName: fileName, context: context)
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
