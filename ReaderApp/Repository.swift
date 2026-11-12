import Foundation
import SwiftData
import Observation
import PDFKit

@MainActor @Observable final class LibraryRepository {
    let container: ModelContainer
    let root: URL
    private let context: ModelContext
    var books: [Book] = []
    var annotations: [Annotation] = []
    var revision = 0
    init(root: URL? = nil) throws {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MarginReader", isDirectory: true)
        self.root = base
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Books"), withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: ReaderSchemaV2.self)
        container = try ModelContainer(for: schema, migrationPlan: ReaderMigration.self, configurations: ModelConfiguration(schema: schema, url: base.appendingPathComponent("Library.store")))
        context = ModelContext(container); context.autosaveEnabled = false
        try reload()
        // Only our incomplete staging directories are removed; imported books remain untouched.
        let staging = base.appendingPathComponent("Staging")
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    }
    func reload() throws {
        books = try context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        annotations = try context.fetch(FetchDescriptor<Annotation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        revision += 1
    }
    func commit() throws { do { try context.save(); try reload() } catch { context.rollback(); try? reload(); throw error } }
    func importBook(_ url: URL) throws -> (Book, Bool) {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let importer = EPUBImporter()
        let hash = try importer.hash(url)
        if let existing = books.first(where: { $0.contentHash == hash }) { return (existing, true) }
        let stage = root.appendingPathComponent("Staging/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        let isPDF=url.pathExtension.lowercased()=="pdf"
        let result = try isPDF ? PDFImporter.unpack(url,to:stage) : importer.unpack(url, to: stage)
        let folder = UUID().uuidString
        let destination = root.appendingPathComponent("Books/" + folder)
        try FileManager.default.moveItem(at: stage, to: destination)
        do {
            let book = try Book(hash: hash, title: result.title, author: result.author, folder: folder, cover: result.cover, chapters: result.chapters)
            if isPDF {book.format="pdf";book.pdfPageCount=result.chapters.count}
            context.insert(book); try commit(); return (book, false)
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    func directory(_ book: Book) -> URL { root.appendingPathComponent("Books/" + book.folder, isDirectory: true) }
    func marks(for book: Book, chapter: String? = nil) -> [Annotation] {
        annotations.filter { $0.bookID == book.id && (chapter == nil || $0.chapter == chapter) }
    }
    func mark(book: Book, chapter: String, anchor: TextAnchor) throws -> Annotation {
        guard anchor.valid(), book.chapters.contains(where: { $0.path == chapter }) else { throw ReaderError.message("选区已失效，请重新选择文字。") }
        if let existing = marks(for: book, chapter: chapter).first(where: { $0.start == anchor.start && $0.end == anchor.end && $0.quote == anchor.quote }) { return existing }
        let mark = Annotation(bookID: book.id, chapter: chapter, anchor: anchor); context.insert(mark); try commit(); return mark
    }
    func draft(_ mark: Annotation, text: String) throws { guard text.utf8.count <= 200_000 else { throw ReaderError.message("想法过长，请缩短后保存。") }; mark.draft = text; try commit() }
    func saveNote(_ mark: Annotation, text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReaderError.message("请先写下想法。") }
        mark.note = text; mark.draft = nil; mark.updatedAt = .now; try commit()
    }
    func deleteNote(_ mark: Annotation) throws { mark.note = ""; mark.draft = nil; mark.updatedAt = .now; try commit() }
    func deleteMark(_ mark: Annotation) throws { context.delete(mark); try commit() }
    func progress(_ book: Book, chapter: String, offset: Int) throws {
        guard book.chapters.contains(where: {$0.path == chapter}), offset >= 0 else { return }
        book.chapterPath = chapter; book.progressOffset = offset; book.updatedAt = .now; try commit()
    }
}

@MainActor extension LibraryRepository {
    func pdfMark(book:Book,pieces:[PDFPiece]) throws -> Annotation {
        guard let document=PDFDocument(url:directory(book).appendingPathComponent("content.pdf")),document.allowsCopying,document.allowsCommenting else {throw ReaderError.message("此 PDF 不允许提取文字或添加批注，无法创建摘录标记。 ")}
        guard book.format=="pdf",!pieces.isEmpty,pieces.count<=1000,pieces.allSatisfy({$0.page>=0 && $0.page<book.pdfPageCount && $0.start>=0 && $0.length>0 && $0.quote.utf16.count==$0.length && !$0.boxes.isEmpty}) else {throw ReaderError.message("PDF 选区无效，请重新选择。")} 
        if let old=marks(for:book).first(where:{$0.pdfPieces==pieces}) {return old}
        let quote=pieces.map(\.quote).joined(separator:"\n")
        let anchor=TextAnchor(start:pieces[0].start,end:pieces[0].start+quote.utf16.count,quote:quote,prefix:"",suffix:"")
        let mark=Annotation(bookID:book.id,chapter:"pdf:\(pieces[0].page)",anchor:anchor)
        mark.pdfAnchorData=try JSONEncoder().encode(pieces);context.insert(mark);try commit();return mark
    }
    func pdfProgress(_ book:Book,page:Int,point:CGPoint) throws {
        guard book.format=="pdf",page>=0,page<book.pdfPageCount,point.x.isFinite,point.y.isFinite else{return}
        book.chapterPath="pdf:\(page)";book.pdfProgressX=point.x;book.pdfProgressY=point.y;book.updatedAt = .now;try commit()
    }
}
