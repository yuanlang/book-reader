import SwiftUI
import SwiftData
import ReadiumShared
import ReadiumStreamer

@Observable
final class LibraryViewModel {
    var isLoading = false
    var errorMessage: String?

    // Readium components — ignored from observation to avoid @Observable macro issues
    @ObservationIgnored
    private lazy var httpClient = DefaultHTTPClient()
    @ObservationIgnored
    private lazy var assetRetriever = AssetRetriever(httpClient: httpClient)
    @ObservationIgnored
    private lazy var publicationOpener = PublicationOpener(
        parser: DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: assetRetriever,
            pdfFactory: DefaultPDFDocumentFactory()
        )
    )
    @ObservationIgnored
    private let storage = BookStorageService.shared

    func importBook(from url: URL, context: ModelContext) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let destinationURL = try await storage.importBook(from: url)
            let relativePath = await storage.relativePath(for: destinationURL)

            // Parse metadata from the EPUB
            let (title, author) = await parseMetadata(at: destinationURL)

            let book = Book(
                title: title,
                author: author,
                filePath: relativePath
            )
            context.insert(book)
            try context.save()
        } catch {
            errorMessage = "导入失败: \(error.localizedDescription)"
        }
    }

    func deleteBook(_ book: Book, context: ModelContext) {
        do {
            Task {
                try await storage.deleteBook(filePath: book.filePath)
            }
            context.delete(book)
            try context.save()
        } catch {
            errorMessage = "删除失败: \(error.localizedDescription)"
        }
    }

    private func parseMetadata(at url: URL) async -> (String, String) {
        do {
            guard let fileURL = FileURL(url: url) else {
                return (url.deletingPathExtension().lastPathComponent, "")
            }
            let asset = try await assetRetriever.retrieve(url: fileURL).get()
            let publication = try await publicationOpener.open(
                asset: asset,
                allowUserInteraction: false
            ).get()

            let title = publication.metadata.title ?? url.deletingPathExtension().lastPathComponent
            let author = publication.metadata.authors.map(\.name).joined(separator: ", ")
            return (title, author)
        } catch {
            return (url.deletingPathExtension().lastPathComponent, "")
        }
    }
}
