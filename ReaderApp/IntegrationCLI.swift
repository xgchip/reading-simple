#if !APPSTORE
import AppKit
import WebKit
import PDFKit

@MainActor enum IntegrationCLI {
    static func handleIfNeeded() {
        let args=CommandLine.arguments
        guard args.count>1, ["--self-test","--inspect-data","--inject-anchor","--web-test","--pdf-test"].contains(args[1]) else {return}
        guard let path=ProcessInfo.processInfo.environment["READER_TEST_DATA_DIR"],path.hasPrefix("/"),!path.isEmpty else {print("Diagnostic commands require READER_TEST_DATA_DIR; user library was not opened.");exit(2)}
        do {
            let repo=try LibraryRepository(root:URL(fileURLWithPath:path,isDirectory:true))
            switch args[1] {
            case "--inspect-data":printJSON(["books":repo.books.map{["id":$0.id.uuidString,"title":$0.title,"chapter":$0.chapterPath,"offset":$0.progressOffset,"format":$0.format,"pdfPageCount":$0.pdfPageCount,"pdfProgressX":$0.pdfProgressX,"pdfProgressY":$0.pdfProgressY] as [String:Any]},"annotations":repo.annotations.map{["id":$0.id.uuidString,"bookID":$0.bookID.uuidString,"chapter":$0.chapter,"start":$0.start,"end":$0.end,"quote":$0.quote,"prefix":$0.prefix,"suffix":$0.suffix,"note":$0.note,"draft":$0.draft as Any? ?? NSNull(),"pdfPieces":$0.pdfPieces.map{["page":$0.page,"start":$0.start,"length":$0.length,"quote":$0.quote,"boxes":$0.boxes.map{["x":$0.x,"y":$0.y,"width":$0.width,"height":$0.height]}]}] as [String:Any]}])
            case "--inject-anchor":
                guard args.count==4,let id=UUID(uuidString:args[2]),let mark=repo.annotations.first(where:{$0.id==id}) else {throw ReaderError.message("usage --inject-anchor annotationUUID range|ambiguous|missing-text|missing-chapter")}
                switch args[3] {case "range":mark.start=Int.max/4;mark.end=mark.start+mark.quote.utf16.count
                case "ambiguous":mark.start=Int.max/4;mark.end=mark.start+mark.quote.utf16.count;mark.prefix="";mark.suffix=""
                case "missing-text":mark.start=Int.max/4;mark.end=mark.start+1;mark.quote="不存在的测试摘录-"+UUID().uuidString
                case "missing-chapter":mark.chapter="__missing__/test.xhtml"
                default:throw ReaderError.message("unknown injection mode")}
                if mark.pdfAnchorData != nil {var pieces=mark.pdfPieces;for i in pieces.indices {switch args[3]{case "range":pieces[i].start=Int.max/4
                case "ambiguous":pieces[i].start=Int.max/4;pieces[i].prefix="";pieces[i].suffix=""
                case "missing-text":pieces[i].start=Int.max/4;pieces[i].quote="不存在的PDF摘录-"+UUID().uuidString;pieces[i].length=pieces[i].quote.utf16.count
                case "missing-chapter":pieces[i].page=Int.max/4
                default:break}};mark.pdfAnchorData=try JSONEncoder().encode(pieces)}
                try repo.commit();printJSON(["injected":args[3],"id":id.uuidString])
            case "--self-test":guard args.count>2 else {throw ReaderError.message("fixture directory required")};try core(repo,fixtures:URL(fileURLWithPath:args[2]))
            case "--pdf-test":guard args.count>2 else {throw ReaderError.message("fixture directory required")};try pdf(repo,fixtures:URL(fileURLWithPath:args[2]))
            case "--web-test":guard args.count>2 else {throw ReaderError.message("fixture file required")};try web(repo,file:URL(fileURLWithPath:args[2]))
            default:break
            };exit(0)
        }catch{printJSON(["error":error.localizedDescription]);exit(1)}
    }
    static func printJSON(_ value:Any){if let bytes=try? JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]),let s=String(data:bytes,encoding:.utf8){print(s)}}
    static func core(_ repo:LibraryRepository,fixtures:URL) throws {
        let (book,_)=try repo.importBook(fixtures.appendingPathComponent("river.epub"))
        let chapter=book.chapters[0].path
        let a=TextAnchor(start:0,end:4,quote:"甲乙丙丁",prefix:"",suffix:"")
        let m=try repo.mark(book:book,chapter:chapter,anchor:a);let repeatMark=try repo.mark(book:book,chapter:chapter,anchor:a)
        guard m.id==repeatMark.id else {throw ReaderError.message("exact range dedup failed")}
        try repo.saveNote(m,text:"跨重启正式想法");try repo.draft(m,text:"独立草稿")
        let (copy,duplicate)=try repo.importBook(fixtures.appendingPathComponent("river-identical-copy.epub"))
        guard duplicate,copy.id==book.id else {throw ReaderError.message("hash dedup failed")}
        let oldCount=repo.books.count
        for name in ["corrupt.epub","fixed-layout.epub"] {var rejected=false;do{_=try repo.importBook(fixtures.appendingPathComponent(name))}catch{rejected=true};guard rejected,repo.books.count==oldCount else {throw ReaderError.message("expected rejection with no residual row: "+name)}}
        let (other,_)=try repo.importBook(fixtures.appendingPathComponent("mountain.epub"))
        guard other.id != book.id else {throw ReaderError.message("cross book identity failed")}
        let reopened=try LibraryRepository(root:repo.root)
        guard let stored=reopened.annotations.first(where:{$0.id==m.id}),stored.note=="跨重启正式想法",stored.draft=="独立草稿" else {throw ReaderError.message("reopen persistence failed")}
        printJSON(["pass":true,"checks":["EPUB3 import","hash dedup","independent book identity","exact selection reuse","formal note + draft persistence","failed import no rows"],"bookID":book.id.uuidString,"annotationID":m.id.uuidString,"dataRoot":repo.root.path])
    }
    static func pdf(_ repo:LibraryRepository,fixtures:URL) throws {
        _=NSApplication.shared
        let (book,_)=try repo.importBook(fixtures.appendingPathComponent("text-river.pdf"))
        guard book.format=="pdf",book.pdfPageCount>=2,let doc=PDFDocument(url:repo.directory(book).appendingPathComponent("content.pdf")),let first=doc.page(at:0),let second=doc.page(at:1) else {throw ReaderError.message("PDF import failed")}
        let firstText=(first.string ?? "") as NSString,secondText=(second.string ?? "") as NSString
        guard firstText.length>30,secondText.length>30,let a=first.selection(for:NSRange(location:firstText.length-30,length:30)),let b=second.selection(for:NSRange(location:0,length:30)) else {throw ReaderError.message("PDF text fixture absent")}
        let selection=PDFSelection(document:doc);selection.add([a,b]);let pieces=NativePDFReader.pieces(selection,document:doc)
        guard Set(pieces.map(\.page))==Set([0,1]),pieces.allSatisfy({NativePDFReader.resolve($0,document:doc) != nil}) else {throw ReaderError.message("PDF cross page anchors failed")}
        let mark=try repo.pdfMark(book:book,pieces:pieces),same=try repo.pdfMark(book:book,pieces:pieces)
        guard mark.id==same.id else {throw ReaderError.message("PDF exact selection dedup failed")}
        try repo.saveNote(mark,text:"PDF 跨页正式想法");try repo.draft(mark,text:"PDF 未提交草稿")
        let (copy,duplicate)=try repo.importBook(fixtures.appendingPathComponent("text-river-identical-copy.pdf"));guard duplicate,copy.id==book.id else {throw ReaderError.message("PDF hash dedup failed")}
        let view=PDFView(frame:CGRect(x:0,y:0,width:900,height:700));view.document=doc;view.displayMode = .singlePageContinuous
        for rotation in [0,90,180,270] {first.rotation=rotation;view.layoutDocumentView();for scale in [0.5,1.2,2.0] {view.scaleFactor=scale;guard NativePDFReader.resolve(pieces[0],document:doc) != nil else {throw ReaderError.message("PDF zoom/rotation anchor failed")};if let box=pieces[0].boxes.first {let transformed=view.convert(box.rect,from:first),restored=view.convert(transformed,to:first);guard abs(restored.midX-box.rect.midX)<0.1,abs(restored.midY-box.rect.midY)<0.1 else{throw ReaderError.message("PDF page coordinate round trip failed")}}}}
        first.rotation=0
        func originalPagePixels() throws -> Data {guard let tiff=first.thumbnail(of:NSSize(width:300,height:430),for:.cropBox).tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let bytes=rep.representation(using:.png,properties:[:]) else {throw ReaderError.message("PDF pixel check unavailable")};return bytes}
        let baselinePixels=try originalPagePixels(),fileHash=try EPUBImporter().hash(repo.directory(book).appendingPathComponent("content.pdf"))
        for theme in ReadingTheme.allCases {view.backgroundColor=theme.pdfCanvas;view.appearance=NSAppearance(named:theme == .dark ? .darkAqua:.aqua);guard try originalPagePixels()==baselinePixels,NativePDFReader.resolve(pieces[0],document:doc) != nil else {throw ReaderError.message("theme changed PDF page pixels or anchor")}}
        guard try EPUBImporter().hash(repo.directory(book).appendingPathComponent("content.pdf"))==fileHash else {throw ReaderError.message("theme changed original PDF file")}
        try repo.pdfProgress(book,page:1,point:CGPoint(x:25,y:450))
        for name in ["corrupt.pdf","locked.pdf"] {let count=repo.books.count;var rejected=false;do{_=try repo.importBook(fixtures.appendingPathComponent(name))}catch{rejected=true};guard rejected,repo.books.count==count else{throw ReaderError.message("invalid PDF not rejected: "+name)}}
        let (scan,_)=try repo.importBook(fixtures.appendingPathComponent("scan-only.pdf"));guard let scanDoc=PDFDocument(url:repo.directory(scan).appendingPathComponent("content.pdf")),scanDoc.pageCount>0,(scanDoc.string ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw ReaderError.message("scanned PDF reading check failed")}
        let (restricted,_)=try repo.importBook(fixtures.appendingPathComponent("restricted-copy.pdf"));guard let restrictedDoc=PDFDocument(url:repo.directory(restricted).appendingPathComponent("content.pdf")),!restrictedDoc.allowsCopying else{throw ReaderError.message("restricted fixture permissions absent")}
        var denied=false;do{_=try repo.pdfMark(book:restricted,pieces:pieces)}catch{denied=true};guard denied else{throw ReaderError.message("PDF text extraction permissions bypassed")}
        let reopened=try LibraryRepository(root:repo.root)
        guard let stored=reopened.annotations.first(where:{$0.id==mark.id}),stored.pdfPieces==pieces,stored.note=="PDF 跨页正式想法",stored.draft=="PDF 未提交草稿",let storedBook=reopened.books.first(where:{$0.id==book.id}),storedBook.chapterPath=="pdf:1",storedBook.pdfProgressY==450 else{throw ReaderError.message("PDF persisted state failed")}
        printJSON(["pass":true,"checks":["PDF managed copy and metadata","cross page text + page coordinates","exact range reuse","hash dedup","zoom and rotation coordinate stability","formal note + draft + page position reopen","scan only reading","locked/corrupt rejection","copy permission enforcement","all themes preserve original PDF page pixels and file"],"bookID":book.id.uuidString,"annotationID":mark.id.uuidString])
    }
    static func web(_ repo:LibraryRepository,file:URL) throws {
        _=NSApplication.shared
        let (book,_)=try repo.importBook(file)
        let session=ReaderSession();session.open(book)
        let bridge=ReaderWebView.Coordinator(repository:repo,session:session)
        let config=WKWebViewConfiguration();config.defaultWebpagePreferences.allowsContentJavaScript=false;config.websiteDataStore = .nonPersistent();config.setURLSchemeHandler(bridge.resources,forURLScheme:"book");config.userContentController.add(bridge,contentWorld:bridge.world,name:"reader")
        let web=WKWebView(frame:CGRect(x:0,y:0,width:1200,height:800),configuration:config);web.navigationDelegate=bridge;session.web=web
        let window=NSWindow(contentRect:CGRect(x:100,y:100,width:1200,height:800),styleMask:[.titled,.resizable],backing:.buffered,defer:false);window.title="阅读从简 · 隔离集成验证";window.contentView=web;window.makeKeyAndOrderFront(nil);defer{window.orderOut(nil)}
        bridge.update(web)
        let deadline=Date().addingTimeInterval(20)
        while !session.ready && session.error==nil && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
        guard session.ready else {throw ReaderError.message(session.error ?? "WebView ready timeout")}
        var done=false;var failure:String?
        let js = #"""
        const root=document.getElementById('book-text');
        if(root.querySelector('script,iframe,object,embed')||document.body.dataset.bookScriptRan)throw Error('unsafe book script/embedding survived');
        if([...root.querySelectorAll('[src],[href]')].some(n=>/^(https?:|file:|javascript:|\/\/)/i.test(n.getAttribute('src')||n.getAttribute('href')||'')))throw Error('external resource survived sanitizer');
        const violations=[];document.addEventListener('securitypolicyviolation',e=>violations.push(e.effectiveDirective));
        const probe=new Image();probe.src='http://127.0.0.1:9/reader-local-csp-probe';root.append(probe);
        await new Promise(r=>setTimeout(r,80));probe.remove();
        if(!violations.includes('img-src'))throw Error('CSP did not block remote image');
        const d=window.Reader.diagnostics(),q='雨停以后，我们沿着河岸慢慢走。',first=d.text.indexOf(q),second=d.text.indexOf(q,first+1);
        if(first<0||second<0)throw Error('repeat fixture absent');
        const a=window.Reader.testAnchor(second,second+q.length),b={...a,start:999999,end:999999+q.length};
        if(window.Reader.testResolve(a)!==second||window.Reader.testResolve(b)!==second||window.Reader.testResolve({...b,prefix:'',suffix:''})!==null)throw Error('anchor resolution failed');
        const marks=[{...a,id:'one',anchorVersion:1,note:'第一条备注',draft:null},{...window.Reader.testAnchor(second+1,second+q.length),id:'two',anchorVersion:1,note:'第二条备注',draft:null}];
        window.Reader.update({marks,sidebar:true,font:28,offset:0});
        await new Promise(r=>setTimeout(r,150));const g=window.Reader.testGeometry();
        if(g.length!==2||g[1].top<g[0].top+g[0].height+11)throw Error('note overlap '+JSON.stringify(g));
        const themes={};
        for(const theme of ['white','paper','dark']){
          window.Reader.update({marks,sidebar:true,font:28,offset:0,theme});await new Promise(r=>setTimeout(r,60));
          if(window.Reader.diagnostics().text!==d.text||window.Reader.testResolve(a)!==second)throw Error('theme mutated text or anchor');
          const paper=getComputedStyle(document.getElementById('reader-canvas')).backgroundColor;
          const texture=getComputedStyle(document.getElementById('reader-canvas'),'::before').backgroundImage;
          const expected={white:'rgb(255, 255, 255)',paper:'rgb(247, 244, 236)',dark:'rgb(39, 43, 37)'};
          if(paper!==expected[theme]||document.documentElement.dataset.theme!==theme)throw Error('theme color mismatch '+theme+' '+paper);
          if(theme==='white'&&texture!=='none'||theme!=='white'&&!texture.includes('data:image/png'))throw Error('theme texture mismatch '+theme);
          themes[theme]={paper,texture:theme!=='white',anchorPreserved:true};
        }
        return {pass:true,second,textLength:d.textLength,geometry:g,themes,security:{bookScriptDisabled:!document.body.dataset.bookScriptRan,unsafeDOMRemoved:true,remoteImageBlockedByCSP:violations.includes("img-src")}};
        """#
        web.callAsyncJavaScript(js,arguments:[:],in:nil,in:bridge.world){result in switch result{case .success(let value):printJSON(value as Any);case .failure(let error):failure=String(describing:(error as NSError).userInfo)};done=true}
        while !done && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
        guard done,failure==nil else {throw ReaderError.message(failure ?? "WebView assertions timeout")}
    }
}

#endif
