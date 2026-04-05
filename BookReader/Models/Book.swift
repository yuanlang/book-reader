import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var filePath: String
    var coverImageData: Data?
    var addedDate: Date
    var lastOpenedDate: Date?

    init(
        id: UUID = UUID(),
        title: String,
        author: String = "",
        filePath: String,
        coverImageData: Data? = nil,
        addedDate: Date = Date(),
        lastOpenedDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.filePath = filePath
        self.coverImageData = coverImageData
        self.addedDate = addedDate
        self.lastOpenedDate = lastOpenedDate
    }
}
