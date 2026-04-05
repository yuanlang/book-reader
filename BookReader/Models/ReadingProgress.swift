import Foundation
import SwiftData

@Model
final class ReadingProgress {
    var bookId: UUID
    var locatorJSON: String
    var progress: Double
    var lastUpdated: Date

    init(
        bookId: UUID,
        locatorJSON: String = "",
        progress: Double = 0.0,
        lastUpdated: Date = Date()
    ) {
        self.bookId = bookId
        self.locatorJSON = locatorJSON
        self.progress = progress
        self.lastUpdated = lastUpdated
    }
}
