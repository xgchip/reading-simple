import Foundation
import CryptoKit
import ZIPFoundation

final class XMLNode {
    var name: String
    var attributes: [String: String]
    var children: [XMLNode] = []
    var text: String = ""
    weak var parent: XMLNode?
    init(_ name: String, _ attributes: [String:String] = [:]) { self.name = name; self.attributes = attributes }
    var allText: String { name == "#text" ? text : children.map(\.allText).joined() }
    func descendants(_ name: String) -> [XMLNode] { (self.name == name ? [self] : []) + children.flatMap { $0.descendants(name) } }
}
final class XMLTree: NSObject, XMLParserDelegate {
    let root = XMLNode("#document")
    var current: XMLNode!
    var count = 0
    override init() { super.init(); current = root }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        count += 1; if count > 200_000 { parser.abortParsing(); return }
        let node = XMLNode(elementName.components(separatedBy: ":").last!, attributeDict); node.parent = current; current.children.append(node); current = node
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { let n=XMLNode("#text"); n.text=string; current.children.append(n) }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if let s=String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: s) } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { current = current.parent ?? root }
    static func parse(_ data: Data) throws -> XMLNode {
        guard data.count <= 32*1024*1024, let text=String(data:data,encoding:.utf8), !text.localizedCaseInsensitiveContains("<!ENTITY") else { throw ReaderError.message("书籍 XML 内容不受支持或过大。") }
        let tree=XMLTree(), parser=XMLParser(data:data)
        parser.shouldResolveExternalEntities=false; parser.shouldProcessNamespaces=true; parser.delegate=tree
        guard parser.parse() else { throw ReaderError.message("EPUB 的目录或章节已损坏，无法解析。") }; return tree.root
    }
}
struct ImportedEPUB { var title: String; var author: String; var cover: String?; var chapters: [Chapter] }
final class EPUBImporter {
    static let maxFile = 256*1024*1024
    func hash(_ url: URL) throws -> String {
        guard ["epub","pdf"].contains(url.pathExtension.lowercased()) else { throw ReaderError.message("仅支持 EPUB 或 PDF 文件。") }
        let size = (try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
        guard size > 0, size <= Self.maxFile else { throw ReaderError.message("文件为空或超过 256 MB 导入上限。") }
        let file=try FileHandle(forReadingFrom:url); defer {try? file.close()}; var h=SHA256()
        while let chunk=try file.read(upToCount:1024*1024), !chunk.isEmpty { h.update(data:chunk) }
        return h.finalize().map{String(format:"%02x",$0)}.joined()
    }
    static func resolve(_ href: String, relativeTo base: String) throws -> String {
        let raw=href.components(separatedBy:"#")[0]
        guard let decoded=raw.removingPercentEncoding, !decoded.hasPrefix("/"), !decoded.contains("\\"), !decoded.contains(":"), !decoded.contains("\0"), !decoded.contains("?") else { throw ReaderError.message("书籍资源路径无效。") }
        var components=base.split(separator:"/").map(String.init); if !base.isEmpty { components.removeLast() }
        for part in decoded.split(separator:"/").map(String.init) {
            if part=="." {continue}; if part==".." { guard !components.isEmpty else {throw ReaderError.message("书籍包含越界资源路径。")};components.removeLast() } else {components.append(part)}
        }
        guard !components.isEmpty else {throw ReaderError.message("书籍资源路径为空。")};return components.joined(separator:"/")
    }
    func unpack(_ url: URL, to folder: URL) throws -> ImportedEPUB {
        let archive: Archive
        do { archive=try Archive(url:url,accessMode:.read) } catch { throw ReaderError.message("EPUB 压缩包已损坏，无法导入。") }
        var seen=Set<String>();var bytes:UInt64=0;var count=0
        let started=Date()
        for e in archive {
            count += 1
            guard count <= 10_000, Date().timeIntervalSince(started)<30 else {throw ReaderError.message("书籍资源过多或处理超时。")}
            let parts=e.path.split(separator:"/",omittingEmptySubsequences:true)
            guard !e.path.hasPrefix("/"), !e.path.contains("\\"), !e.path.contains(":"), !e.path.contains("\0"), !parts.contains(".."), e.type != .symlink else { throw ReaderError.message("书籍包含不安全的文件路径。") }
            let normalized=parts.joined(separator:"/")
            guard !normalized.isEmpty, !parts.contains("."), seen.insert(normalized.precomposedStringWithCanonicalMapping.lowercased()).inserted else {throw ReaderError.message("书籍包含重复或歧义资源路径。")}
            guard e.uncompressedSize <= 32*1024*1024 else {throw ReaderError.message("书籍单个资源超过 32 MB。")}
            bytes += e.uncompressedSize;guard bytes <= UInt64(Self.maxFile) else {throw ReaderError.message("书籍解压后超过 256 MB。")}
            let target=folder.appendingPathComponent(normalized)
            if e.type == .directory {try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true);continue}
            try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            FileManager.default.createFile(atPath:target.path,contents:nil)
            let handle=try FileHandle(forWritingTo:target);defer {try? handle.close()};var actual=0
            do { _=try archive.extract(e,consumer:{chunk in actual+=chunk.count;guard actual<=32*1024*1024 else {throw ReaderError.message("资源解压超限。")};try handle.write(contentsOf:chunk)}) }
            catch {throw ReaderError.message("EPUB 资源校验失败："+e.path)}
        }
        func data(_ path:String) throws -> Data {
            guard seen.contains(path.precomposedStringWithCanonicalMapping.lowercased()) else {throw ReaderError.message("书籍缺少资源："+path)}
            return try Data(contentsOf:folder.appendingPathComponent(path))
        }
        guard let mime=try? String(data:data("mimetype"),encoding:.utf8), mime.trimmingCharacters(in:.whitespacesAndNewlines)=="application/epub+zip" else {throw ReaderError.message("文件不是有效的 EPUB。")}
        if seen.contains("meta-inf/encryption.xml") {
            let encrypted=try XMLTree.parse(data("META-INF/encryption.xml"))
            let algorithms=encrypted.descendants("EncryptionMethod").compactMap{$0.attributes["Algorithm"]}
            let allowed=["http://www.idpf.org/2008/embedding","http://ns.adobe.com/pdf/enc#RC"]
            guard !algorithms.isEmpty, algorithms.allSatisfy({allowed.contains($0)}) else {throw ReaderError.message("此 EPUB 使用 DRM 或不支持的加密，无法导入。")}
            // Font obfuscation requires key handling; avoid silently rendering corrupted fonts.
            throw ReaderError.message("此 EPUB 使用字体混淆，当前版本暂不支持。请使用未加密版本。")
        }
        let container=try XMLTree.parse(data("META-INF/container.xml"))
        guard let opfRaw=container.descendants("rootfile").first?.attributes["full-path"] else {throw ReaderError.message("EPUB 缺少书籍描述文件。")}
        let opfPath=try Self.resolve(opfRaw,relativeTo:"")
        let opf=try XMLTree.parse(data(opfPath))
        guard let package=opf.descendants("package").first, ["2.0","3.0","3.1","3.2","3.3"].contains(package.attributes["version"] ?? "") else {throw ReaderError.message("不支持此 EPUB 版本。")}
        if opf.descendants("meta").contains(where:{$0.attributes["property"]=="rendition:layout" && $0.allText.trimmingCharacters(in:.whitespacesAndNewlines)=="pre-paginated"}) || opf.descendants("itemref").contains(where:{($0.attributes["properties"] ?? "").contains("pre-paginated")}) {throw ReaderError.message("暂不支持固定版式 EPUB，请导入可重排版本。")}
        let items=opf.descendants("item");var manifest:[String:XMLNode]=[:];var allowed:[String]=[]
        for item in items {
            guard let id=item.attributes["id"], let href=item.attributes["href"], manifest[id]==nil else {throw ReaderError.message("EPUB 资源清单无效。")}
            let path=try Self.resolve(href,relativeTo:opfPath);_=try data(path); manifest[id]=item;allowed.append(path)
        }
        var navigation:[String:String]=[:]
        if let nav=items.first(where:{($0.attributes["properties"] ?? "").split(separator:" ").contains("nav")}), let href=nav.attributes["href"] {
            let path=try Self.resolve(href,relativeTo:opfPath), tree=try XMLTree.parse(data(path))
            for a in tree.descendants("a") {if let href=a.attributes["href"],let p=try? Self.resolve(href,relativeTo:path),navigation[p]==nil { navigation[p]=a.allText.trimmingCharacters(in:.whitespacesAndNewlines) }}
        } else if let ncxID=opf.descendants("spine").first?.attributes["toc"],let ncx=manifest[ncxID],let href=ncx.attributes["href"] {
            let path=try Self.resolve(href,relativeTo:opfPath),tree=try XMLTree.parse(data(path))
            for point in tree.descendants("navPoint") {if let src=point.descendants("content").first?.attributes["src"],let p=try? Self.resolve(src,relativeTo:path) {navigation[p]=point.descendants("text").first?.allText ?? ""}}
        }
        var chapters:[Chapter]=[]
        for ref in opf.descendants("itemref") {
            guard let id=ref.attributes["idref"],let item=manifest[id],let href=item.attributes["href"], ["application/xhtml+xml","text/html"].contains(item.attributes["media-type"] ?? "") else {throw ReaderError.message("书籍包含不支持的章节格式。")}
            let path=try Self.resolve(href,relativeTo:opfPath),tree=try XMLTree.parse(data(path))
            guard tree.descendants("body").first != nil else {throw ReaderError.message("章节缺少正文。")}
            let title=navigation[path] ?? tree.descendants("title").first?.allText ?? "第 \(chapters.count+1) 章"
            if !chapters.contains(where:{$0.path==path}) {chapters.append(Chapter(path:path,title:title.isEmpty ? "第 \(chapters.count+1) 章":title))}
        }
        guard !chapters.isEmpty else {throw ReaderError.message("书籍没有可阅读的章节。")}
        let metadata=opf.descendants("metadata").first
        let title=metadata?.descendants("title").first?.allText.trimmingCharacters(in:.whitespacesAndNewlines)
        let author=metadata?.descendants("creator").map(\.allText).joined(separator:"、") ?? ""
        let coverItem=items.first(where:{($0.attributes["properties"] ?? "").split(separator:" ").contains("cover-image")}) ?? metadata?.descendants("meta").first(where:{$0.attributes["name"]=="cover"}).flatMap{manifest[$0.attributes["content"] ?? ""]}
        let cover=try coverItem?.attributes["href"].map{try Self.resolve($0,relativeTo:opfPath)}
        try JSONEncoder().encode(allowed).write(to:folder.appendingPathComponent(".reader-manifest.json"),options:.atomic)
        return ImportedEPUB(title:(title?.isEmpty == false ? title! : url.deletingPathExtension().lastPathComponent),author:author.isEmpty ? "未知作者":author,cover:cover,chapters:chapters)
    }
}
