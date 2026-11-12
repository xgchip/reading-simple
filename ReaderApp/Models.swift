import Foundation
import SwiftData

struct Chapter: Codable, Identifiable, Hashable {
    var id: String { path }
    var path: String
    var title: String
    var fragment: String?
}
enum ReaderSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Book.self, Annotation.self] }
    @Model final class Book {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var contentHash: String
        var title: String
        var author: String
        var folder: String
        var cover: String?
        var chaptersData: Data
        var chapterPath: String
        var progressOffset: Int
        var fontSize: Double
        var updatedAt: Date
        init(hash: String, title: String, author: String, folder: String, cover: String?, chapters: [Chapter]) throws {
            id = UUID(); self.contentHash = hash; self.title = title; self.author = author; self.folder = folder; self.cover = cover
            chaptersData = try JSONEncoder().encode(chapters); chapterPath = chapters.first?.path ?? ""; progressOffset = 0; fontSize = 19; updatedAt = .now
        }
        var chapters: [Chapter] { (try? JSONDecoder().decode([Chapter].self, from: chaptersData)) ?? [] }
    }
    @Model final class Annotation {
        @Attribute(.unique) var id: UUID
        var bookID: UUID
        var chapter: String
        var anchorVersion: Int
        var start: Int
        var end: Int
        var quote: String
        var prefix: String
        var suffix: String
        var note: String
        var draft: String?
        var createdAt: Date
        var updatedAt: Date
        init(bookID: UUID, chapter: String, anchor: TextAnchor) {
            id = UUID(); self.bookID = bookID; self.chapter = chapter; anchorVersion = 1
            start = anchor.start; end = anchor.end; quote = anchor.quote; prefix = anchor.prefix; suffix = anchor.suffix
            note = ""; draft = nil; createdAt = .now; updatedAt = .now
        }
        var anchor: TextAnchor { TextAnchor(start: start, end: end, quote: quote, prefix: prefix, suffix: suffix) }
    }
}
enum ReaderSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Book.self, Annotation.self] }
    @Model final class Book {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var contentHash: String
        var title: String
        var author: String
        var folder: String
        var cover: String?
        var chaptersData: Data
        var chapterPath: String
        var progressOffset: Int
        var fontSize: Double
        var updatedAt: Date
        var format: String = "epub"
        var pdfPageCount: Int = 0
        var pdfScale: Double = 0
        var pdfProgressX: Double = 0
        var pdfProgressY: Double = 0
        var pdfRotation: Int = 0
        init(hash: String, title: String, author: String, folder: String, cover: String?, chapters: [Chapter]) throws {
            id = UUID(); self.contentHash = hash; self.title = title; self.author = author; self.folder = folder; self.cover = cover
            chaptersData = try JSONEncoder().encode(chapters); chapterPath = chapters.first?.path ?? ""; progressOffset = 0; fontSize = 19; updatedAt = .now
        }
        var chapters: [Chapter] { (try? JSONDecoder().decode([Chapter].self, from: chaptersData)) ?? [] }
    }
    @Model final class Annotation {
        @Attribute(.unique) var id: UUID
        var bookID: UUID
        var chapter: String
        var anchorVersion: Int
        var start: Int
        var end: Int
        var quote: String
        var prefix: String
        var suffix: String
        var note: String
        var draft: String?
        var createdAt: Date
        var updatedAt: Date
        var pdfAnchorData: Data? = nil
        init(bookID: UUID, chapter: String, anchor: TextAnchor) {
            id = UUID(); self.bookID = bookID; self.chapter = chapter; anchorVersion = 1
            start = anchor.start; end = anchor.end; quote = anchor.quote; prefix = anchor.prefix; suffix = anchor.suffix
            note = ""; draft = nil; createdAt = .now; updatedAt = .now
        }
        var anchor: TextAnchor { TextAnchor(start: start, end: end, quote: quote, prefix: prefix, suffix: suffix) }
    }
}
enum ReaderMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ReaderSchemaV1.self, ReaderSchemaV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: ReaderSchemaV1.self, toVersion: ReaderSchemaV2.self)] }
}
typealias Book = ReaderSchemaV2.Book
typealias Annotation = ReaderSchemaV2.Annotation
struct TextAnchor: Codable, Equatable {
    var start: Int
    var end: Int
    var quote: String
    var prefix: String
    var suffix: String
    func valid() -> Bool { start >= 0 && end > start && end - start <= 200_000 && quote.utf16.count == end-start && prefix.utf16.count <= 64 && suffix.utf16.count <= 64 }
}
enum ReaderError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}

struct PDFBox: Codable, Hashable {
    var x: Double; var y: Double; var width: Double; var height: Double
    init(_ rect: CGRect) {x=rect.origin.x;y=rect.origin.y;width=rect.width;height=rect.height}
    var rect: CGRect {CGRect(x:x,y:y,width:width,height:height)}
}
struct PDFPiece: Codable, Equatable {
    var page: Int
    var start: Int
    var length: Int
    var quote: String
    var prefix: String
    var suffix: String
    var boxes: [PDFBox]
}
extension Annotation {
    var pdfPieces: [PDFPiece] { (try? pdfAnchorData.map { try JSONDecoder().decode([PDFPiece].self,from:$0) }) ?? [] }
}
