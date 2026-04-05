import Foundation

actor BookStorageService {
    static let shared = BookStorageService()

    private let fileManager = FileManager.default

    private var booksDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Books", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Import a book by copying it to the app's Books directory.
    func importBook(from url: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let destination = booksDirectory.appendingPathComponent(url.lastPathComponent)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: url, to: destination)
        return destination
    }

    /// Delete a book file.
    func deleteBook(filePath: String) throws {
        let url = booksDirectory.appendingPathComponent(filePath)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Get the full URL for a book given its relative file path.
    func bookURL(for filePath: String) -> URL {
        if filePath.hasPrefix("/") {
            return URL(fileURLWithPath: filePath)
        }
        return booksDirectory.appendingPathComponent(filePath)
    }

    /// Get a relative path from an absolute URL.
    func relativePath(for absoluteURL: URL) -> String {
        let base = booksDirectory.path
        let path = absoluteURL.path
        if path.hasPrefix(base) {
            let index = path.index(path.startIndex, offsetBy: base.count)
            return String(path[index...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return absoluteURL.lastPathComponent
    }
}
