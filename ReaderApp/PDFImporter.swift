import Foundation
import PDFKit
import AppKit

enum PDFImporter {
    static func unpack(_ source:URL,to folder:URL) throws -> ImportedEPUB {
        let target=folder.appendingPathComponent("content.pdf")
        try FileManager.default.copyItem(at:source,to:target)
        guard let doc=PDFDocument(url:target) else {throw ReaderError.message("PDF 文件已损坏或格式无效，无法导入。")};guard !doc.isLocked else {throw ReaderError.message("PDF 已加密锁定，当前版本暂不提供密码解锁。")};guard doc.pageCount>0,doc.page(at:0) != nil else{throw ReaderError.message("PDF 没有可阅读的页面。")}
        guard doc.pageCount<=20_000 else {throw ReaderError.message("PDF 超过 20,000 页处理上限。")}
        let attributes=doc.documentAttributes ?? [:]
        let rawTitle=(attributes[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in:.whitespacesAndNewlines)
        let title=rawTitle?.isEmpty==false ? rawTitle!:source.deletingPathExtension().lastPathComponent
        let rawAuthor=attributes[PDFDocumentAttribute.authorAttribute] as? String
        let author=rawAuthor?.isEmpty==false ? rawAuthor!:"未知作者"
        var titles:[Int:String]=[:]
        func visit(_ outline:PDFOutline){if let page=outline.destination?.page {let index=doc.index(for:page);if index != NSNotFound,let label=outline.label,!label.isEmpty {titles[index]=label}};for i in 0..<outline.numberOfChildren {if let child=outline.child(at:i){visit(child)}}}
        if let outline=doc.outlineRoot {visit(outline)}
        let chapters=(0..<doc.pageCount).map{Chapter(path:"pdf:\($0)",title:"第 \($0+1) 页")}
        // Assign outline labels without confusing page numbers and closure shadowing.
        let labeled=chapters.enumerated().map{index,ch in Chapter(path:ch.path,title:titles[index].map{"\($0) · 第 \(index+1) 页"} ?? ch.title)}
        var cover:String?
        if let page=doc.page(at:0),let rep=NSBitmapImageRep(data:page.thumbnail(of:NSSize(width:350,height:470),for:.cropBox).tiffRepresentation!),let png=rep.representation(using:.png,properties:[:]) {try png.write(to:folder.appendingPathComponent("cover.png"));cover="cover.png"}
        return ImportedEPUB(title:title,author:author,cover:cover,chapters:labeled)
    }
}
