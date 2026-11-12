import SwiftUI
import WebKit
import UniformTypeIdentifiers
import PDFKit

@MainActor @Observable final class ReaderSession {
    var book: Book?
    var chapter: String = ""
    var focusID: UUID?
    var navigationToken = UUID()
    var selection: TextAnchor?
    var editing: Annotation?
    var failed: Annotation?
    var error: String?
    var sidebar = true
    var font: Double = 19
    var theme="paper"
    var web: WKWebView?
    var ready = false
    var pendingOffset = 0
    var pdfView:PDFView?
    var pdfSelection:[PDFPiece]=[]
    var pdfVisiblePages:Set<Int>=[]
    var pdfExpanded:Set<UUID>=[]
    var pdfPopup:Annotation?
    var pdfNotice=""
    func open(_ book: Book, annotation: Annotation? = nil) {
        self.book = book; font=book.fontSize;pdfSelection=[];pdfVisiblePages=[];pdfPopup=nil;pdfView=nil;pdfNotice=""
        chapter=annotation?.chapter ?? book.chapterPath
        focusID=annotation?.id; pendingOffset=annotation == nil ? book.progressOffset : 0
        failed=nil; ready=false; navigationToken=UUID()
    }
    func navigate(_ chapter: String, offset: Int=0) { self.chapter=chapter; pendingOffset=offset; focusID=nil; failed=nil; ready=false;navigationToken=UUID() }
}
final class BookResourceHandler: NSObject, WKURLSchemeHandler {
    var directory: URL?
    var host = ""
    var allowed = Set<String>()
    var chapters = Set<String>()
    func configure(root: URL, host: String, chapters: [Chapter]) throws {
        directory=root;self.host=host;self.chapters=Set(chapters.map(\.path))
        allowed=Set(try JSONDecoder().decode([String].self,from:Data(contentsOf:root.appendingPathComponent(".reader-manifest.json"))))
    }
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        #if !APPSTORE
        if ProcessInfo.processInfo.environment["READER_DIAGNOSTICS"] != nil {print("SCHEME",urlSchemeTask.request.url as Any)}
        #endif
        do {
            guard let u=urlSchemeTask.request.url, u.scheme=="book",u.host==host,let dir=directory else {throw ReaderError.message("资源不属于当前书籍。")}
            let path=String(u.path.dropFirst())
            guard allowed.contains(path), !path.split(separator:"/").contains(".."),!path.contains("\\"),!path.contains("\0") else {throw ReaderError.message("书籍资源不可访问。")}
            let file=dir.appendingPathComponent(path).standardizedFileURL
            guard file.path.hasPrefix(dir.standardizedFileURL.path+"/"), !((try file.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink ?? false) else {throw ReaderError.message("资源路径无效。")}
            var bytes=try Data(contentsOf:file)
            var mime=UTType(filenameExtension:file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            if chapters.contains(path) { bytes=try Self.document(bytes);mime="text/html" }
            let response=URLResponse(url:u,mimeType:mime,expectedContentLength:bytes.count,textEncodingName:mime.hasPrefix("text/") ? "utf-8":nil)
            urlSchemeTask.didReceive(response);urlSchemeTask.didReceive(bytes);urlSchemeTask.didFinish()
        } catch {urlSchemeTask.didFailWithError(error)}
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
    static func escape(_ s: String) -> String {s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;")}
    static func html(_ n:XMLNode) -> String {
        if n.name=="#text" {return escape(n.text)}
        let blocked:Set<String>=["script","iframe","frame","frameset","object","embed","form","input","button","textarea","select","base","meta","noscript","audio","video","foreignObject"]
        guard !blocked.contains(n.name) else {return ""}
        var attrs=""
        for (key,value) in n.attributes.sorted(by:{$0.key<$1.key}) {
            if key.lowercased().hasPrefix("on") || ["srcdoc","formaction","xmlns","xmlns:epub","xml:base","contenteditable"].contains(key.lowercased()) {continue}
            if ["src","href","xlink:href","poster","action"].contains(key.lowercased()) {
                let trimmed=value.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
                if trimmed.contains(":") && !trimmed.hasPrefix("data:image/") {continue}
                if trimmed.hasPrefix("//") {continue}
            }
            attrs+=" \(key)=\"\(escape(value))\""
        }
        let voids:Set<String>=["img","br","hr","link","wbr","source","area","col"]
        let body=n.children.map(html).joined()
        return "<\(n.name)\(attrs)>"+body+(voids.contains(n.name) ? "":"</\(n.name)>")
    }
    static func document(_ data:Data) throws -> Data {
        let tree=try XMLTree.parse(data),body=tree.descendants("body").first!
        let styles=(tree.descendants("head").first?.children ?? []).filter{$0.name=="style" || ($0.name=="link" && $0.attributes["rel"]=="stylesheet")}.map(html).joined()
        let css=try String(contentsOf:Bundle.main.url(forResource:"Reader",withExtension:"css")!,encoding:.utf8)
        let grain=(try? Bundle.main.url(forResource:"paper-warm",withExtension:"png").map{try Data(contentsOf:$0).base64EncodedString()}) ?? ""
        let darkGrain=(try? Bundle.main.url(forResource:"paper-dark",withExtension:"png").map{try Data(contentsOf:$0).base64EncodedString()}) ?? ""
        let themeCSS=(try? Bundle.main.url(forResource:"ThemeVariables",withExtension:"css").map{try String(contentsOf:$0,encoding:.utf8)}) ?? ""
        let doc="""
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src book: data:; style-src 'unsafe-inline' book:; font-src book:; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">\(styles)<style>\(css) \(themeCSS) :root{--paper-grain:url(data:image/png;base64,\(grain));--dark-grain:url(data:image/png;base64,\(darkGrain))}</style></head><body><main id="reader-canvas"><div id="book-text">\(body.children.map(html).joined())</div><aside id="reader-notes" aria-label="页边想法"></aside></main><div id="reader-highlights"></div><div id="reader-selection" hidden><button data-action="highlight">划线</button><button data-action="note">写想法</button></div><section id="reader-popup" role="dialog" aria-label="引用与想法" hidden></section></body></html>
        """
        return Data(doc.utf8)
    }
}
struct ReaderWebView: NSViewRepresentable {
    let repository: LibraryRepository
    let session: ReaderSession
    let revision:Int
    let navigation:UUID
    let font:Double
    let sidebar:Bool
    let focus:UUID?
    let theme:String
    func makeCoordinator() -> Coordinator {let c=Coordinator(repository:repository,session:session);c.theme=theme;return c}
    func makeNSView(context:Context) -> WKWebView {
        let config=WKWebViewConfiguration();config.defaultWebpagePreferences.allowsContentJavaScript=false
        config.websiteDataStore = .nonPersistent();config.setURLSchemeHandler(context.coordinator.resources,forURLScheme:"book")
        config.userContentController.add(context.coordinator,contentWorld:context.coordinator.world,name:"reader")
        let web=WKWebView(frame:.zero,configuration:config);web.navigationDelegate=context.coordinator
        web.setValue(false,forKey:"drawsBackground");session.web=web;return web
    }
    func updateNSView(_ web:WKWebView,context:Context) {context.coordinator.theme=theme;context.coordinator.update(web)}
    @MainActor final class Coordinator:NSObject,WKNavigationDelegate,WKScriptMessageHandler {
        let repository:LibraryRepository;let session:ReaderSession
        let resources=BookResourceHandler();let world=WKContentWorld.world(name:"MarginReader.app")
        var theme="paper"
        var token:UUID?;var bookID:UUID?;var secret="";var loadedChapter="";var textLength=0;var lastFocus:UUID?;var lastPayload="";var progressWork:DispatchWorkItem?
        init(repository:LibraryRepository,session:ReaderSession){self.repository=repository;self.session=session}
        func payload() -> [String:Any] {
            guard let book=session.book else {return [:]}
            let marks=repository.marks(for:book,chapter:session.chapter).map{m -> [String:Any] in ["id":m.id.uuidString,"start":m.start,"end":m.end,"quote":m.quote,"prefix":m.prefix,"suffix":m.suffix,"anchorVersion":m.anchorVersion,"note":m.note,"draft":m.draft as Any? ?? NSNull()]}
            return ["marks":marks,"sidebar":session.sidebar,"font":session.font,"theme":theme,"texture":(!NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency),"offset":session.pendingOffset]
        }
        func json(_ o:Any) -> String {(String(data:(try? JSONSerialization.data(withJSONObject:o,options:[.sortedKeys,.fragmentsAllowed])) ?? Data("null".utf8),encoding:.utf8) ?? "null")}
        func update(_ web:WKWebView) {
            guard let book=session.book else {return}
            if token != session.navigationToken {
                #if !APPSTORE
                if ProcessInfo.processInfo.environment["READER_DIAGNOSTICS"] != nil {print("LOAD",session.chapter,web.frame)}
                #endif
                token=session.navigationToken;bookID=book.id;secret=UUID().uuidString.lowercased();loadedChapter=session.chapter;lastFocus=nil;lastPayload="";textLength=0
                guard book.chapters.contains(where:{$0.path==session.chapter}) else {if let id=session.focusID {session.failed=repository.annotations.first{$0.id==id}};session.error="对应章节已不可用，备注与摘录仍已保留。";return}
                do {try resources.configure(root:repository.directory(book),host:secret,chapters:book.chapters)
                    var c=URLComponents();c.scheme="book";c.host=secret;c.path="/"+session.chapter
                    guard let url=c.url else {throw ReaderError.message("章节地址无效。")};web.load(URLRequest(url:url))
                    let expected=token
                    DispatchQueue.main.asyncAfter(deadline:.now()+12){[weak self] in guard let self,self.token==expected,!self.session.ready else{return};self.session.error="阅读内容进程未能启动。请重试；书籍和备注仍保存在本机。"}
                } catch {session.error=error.localizedDescription};return
            }
            guard session.ready else {return}
            let data=payload(),fingerprint=json(data)
            if lastPayload != fingerprint {lastPayload=fingerprint;web.callAsyncJavaScript("window.Reader.update(payload)",arguments:["payload":data],in:nil,in:world,completionHandler:nil)}
            if let focus=session.focusID,focus != lastFocus {lastFocus=focus;web.callAsyncJavaScript("return window.Reader.focus(id)",arguments:["id":focus.uuidString],in:nil,in:world,completionHandler:nil)}
        }
        func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
            #if !APPSTORE
            if ProcessInfo.processInfo.environment["READER_DIAGNOSTICS"] != nil {print("FINISH",webView.url as Any)}
            #endif
            guard webView.url?.host==secret else {return}
            do {var js=try String(contentsOf:Bundle.main.url(forResource:"Reader",withExtension:"js")!,encoding:.utf8)
                js=js.replacingOccurrences(of:"__SESSION__",with:json(secret)).replacingOccurrences(of:"__CHAPTER__",with:json(loadedChapter)).replacingOccurrences(of:"__INITIAL__",with:json(payload()))
                webView.evaluateJavaScript(js,in:nil,in:world){result in if case .failure(let error)=result {self.session.error="阅读脚本未能启动："+error.localizedDescription}}
            } catch {session.error=error.localizedDescription}
        }
        func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){session.error="章节打开失败："+error.localizedDescription}
        func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
            #if !APPSTORE
            if ProcessInfo.processInfo.environment["READER_DIAGNOSTICS"] != nil {print("POLICY",navigationAction.request.url as Any)}
            #endif
            guard let url=navigationAction.request.url,url.scheme=="book",url.host==secret else {decisionHandler(.cancel);return};decisionHandler(.allow)
        }
        func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
            #if !APPSTORE
            if ProcessInfo.processInfo.environment["READER_DIAGNOSTICS"] != nil {print("MESSAGE",message.body)}
            #endif
            guard message.frameInfo.isMainFrame, let body=message.body as? [String:Any],body["session"] as? String==secret,body["chapter"] as? String==loadedChapter,loadedChapter==session.chapter,let type=body["type"] as? String,let book=session.book,book.id==bookID else {return}
            do {switch type {
            case "ready":guard let n=body["textLength"] as? Int,n>=0,n<=32*1024*1024 else {return};textLength=n;try repository.progress(book,chapter:loadedChapter,offset:session.pendingOffset);session.ready=true;if let web=session.web {update(web)}
            case "selection":guard let raw=body["anchor"],JSONSerialization.isValidJSONObject(raw) else {return}
                let anchor=try JSONDecoder().decode(TextAnchor.self,from:JSONSerialization.data(withJSONObject:raw));guard anchor.valid(),anchor.end<=textLength else {return}
                let mark=try repository.mark(book:book,chapter:loadedChapter,anchor:anchor)
                if body["action"] as? String=="note" {session.editing=mark}
            case "edit","openMark","anchorFailed":guard let idString=body["id"] as? String,let id=UUID(uuidString:idString),let mark=repository.marks(for:book,chapter:loadedChapter).first(where:{$0.id==id}) else {return}
                if type=="edit" {session.editing=mark} else if type=="anchorFailed" {session.failed=mark}
            case "progress":guard let n=body["offset"] as? Int,n>=0,n<=textLength else {return};try repository.progress(book,chapter:loadedChapter,offset:n)
            case "link":guard let href=body["href"] as? String,href.utf8.count<8192 else {return}
                if href.hasPrefix("#") {session.web?.callAsyncJavaScript("window.Reader.chapterFragment(id)",arguments:["id":String(href.dropFirst()).removingPercentEncoding ?? ""],in:nil,in:world,completionHandler:nil)}
                else {let path=try EPUBImporter.resolve(href,relativeTo:loadedChapter);if book.chapters.contains(where:{$0.path==path}) {session.navigate(path)}else {session.error="该链接不是本书可阅读的章节。"}}
            default:return
            }}catch{session.error=error.localizedDescription}
        }
    }
}
