import SwiftUI
import UniformTypeIdentifiers
import PDFKit

@main struct MarginReaderApp: App {
    @AppStorage("readerTheme") private var themeRaw="paper"
    @State private var repository: LibraryRepository?
    private var startupError: String?
    init() {
        #if !APPSTORE
        IntegrationCLI.handleIfNeeded()
        #endif
        do {
            #if APPSTORE
            let root:URL?=nil
            #else
            let root=ProcessInfo.processInfo.environment["READER_TEST_DATA_DIR"].map{URL(fileURLWithPath:$0,isDirectory:true)}
            #endif
            _repository=State(initialValue:try LibraryRepository(root:root))
        } catch {startupError=error.localizedDescription}
    }
    var body: some Scene {
        WindowGroup("阅读从简") {
            if let repository {LibraryView(repository:repository).frame(minWidth:640,minHeight:520).environment(\.readingTheme,ReadingTheme(rawValue:themeRaw) ?? .paper).preferredColorScheme((ReadingTheme(rawValue:themeRaw) ?? .paper).scheme).tint((ReadingTheme(rawValue:themeRaw) ?? .paper).accent)}
            else {VStack(spacing:18){Image(systemName:"exclamationmark.triangle").font(.largeTitle);Text("书库暂时无法打开").font(.title2);Text(startupError ?? "未知错误").textSelection(.enabled);Text("数据未被删除。请检查磁盘空间与目录权限后重试。").foregroundStyle(.secondary)}.padding(40)}
        }.defaultSize(width:1200,height:820).commands {
            CommandGroup(replacing:.help) {
                Button("阅读从简使用帮助") { NSWorkspace.shared.open(URL(string:"https://xgchip.github.io/reading-simple/support.html")!) }
                Button("隐私政策") { NSWorkspace.shared.open(URL(string:"https://xgchip.github.io/reading-simple/privacy.html")!) }
            }
            CommandGroup(replacing:.newItem){Button("导入书籍…"){NotificationCenter.default.post(name:.importBooks,object:nil)}.keyboardShortcut("o")}
            CommandMenu("阅读"){Button("增大字号 / 放大"){NotificationCenter.default.post(name:.readerFont,object:1.0)}.keyboardShortcut("+");Button("减小字号 / 缩小"){NotificationCenter.default.post(name:.readerFont,object:-1.0)}.keyboardShortcut("-")}
        }
    }
}
extension Notification.Name {static let importBooks=Notification.Name("MarginReader.importBooks");static let readerFont=Notification.Name("MarginReader.readerFont")}
struct ImportReport:Identifiable {let id=UUID();var lines:[String]}
struct LibraryView:View {
    @Environment(\.readingTheme) private var theme
    @AppStorage("readerTheme") private var themeRaw="paper"
    let repository:LibraryRepository
    @State private var session=ReaderSession()
    @State private var route="books"
    @State private var search=""
    @State private var navigation=true
    @State private var tab="chapters"
    @State private var importing=false
    @State private var availableWidth:CGFloat=1200
    @State private var pdfPageInput=""
    @State private var fontPanel=false
    @State private var report:ImportReport?
    @State private var exportMessage:String?
    @AppStorage("showMarginNotes") private var marginNotes=true
    var body:some View {
        HStack(spacing:0){
            if navigation {sidebar.frame(width:route == "reader" ? 196:168);Divider()}
            VStack(spacing:0){topbar;Divider();content}
            if availableWidth>=1080,route=="reader",let mark=session.editing {Divider();NoteEditor(repository:repository,mark:mark,width:330){session.editing=nil}.id(mark.id)}
        }
        .background(PaperSurface()).foregroundStyle(theme.ink)
        .background{GeometryReader{proxy in Color.clear.onAppear{availableWidth=proxy.size.width}.onChange(of:proxy.size.width){_,value in availableWidth=value}}}
        .onOpenURL{url in Task{@MainActor in await importURLs([url])}}
        .onReceive(NotificationCenter.default.publisher(for:.importBooks)){_ in chooseBooks()}
        .onReceive(NotificationCenter.default.publisher(for:.readerFont)){notification in guard route=="reader",let delta=notification.object as? Double else{return};if session.book?.format=="pdf"{pdfZoom(delta>0 ? 1.18:0.85)}else{resizeFont(delta)}}
        .onAppear{session.sidebar=marginNotes}
        .onChange(of:marginNotes){_,v in session.sidebar=v}
        .onDrop(of:[UTType.fileURL],isTargeted:nil){providers in
            Task{@MainActor in var urls:[URL]=[];for p in providers {let url:URL?=await withCheckedContinuation{continuation in _=p.loadObject(ofClass:URL.self){url,_ in continuation.resume(returning:url)}};if let url {urls.append(url)}};if !urls.isEmpty {await importURLs(urls)}};return !providers.isEmpty
        }
        .sheet(item:$session.pdfPopup){mark in VStack(alignment:.leading,spacing:16){Text(mark.quote).foregroundStyle(.secondary);Text(mark.note.isEmpty ? "这是一条划线。":mark.note);HStack{Button("关闭"){session.pdfPopup=nil};Spacer();Button("编辑 / 继续草稿"){session.pdfPopup=nil;session.editing=mark}}}.padding(26).frame(width:460).background(theme.surface).foregroundStyle(theme.ink)}
        .sheet(item:$report){report in VStack(alignment:.leading,spacing:18){Text("导入结果").font(.title2);ScrollView{VStack(alignment:.leading,spacing:12){ForEach(Array(report.lines.enumerated()),id:\.offset){_,line in Text(line).frame(maxWidth:.infinity,alignment:.leading)}}}.frame(minHeight:100,maxHeight:350);Button("完成"){self.report=nil}.keyboardShortcut(.defaultAction)}.padding(28).frame(width:540).background(theme.surface).foregroundStyle(theme.ink)}
        .sheet(item:Binding(get:{availableWidth<1080 || route != "reader" ? session.editing:nil},set:{session.editing=$0})){mark in NoteEditor(repository:repository,mark:mark){session.editing=nil}}
        .alert("导出完成",isPresented:Binding(get:{exportMessage != nil},set:{if !$0 {exportMessage=nil}})){Button("完成"){exportMessage=nil}}message:{Text(exportMessage ?? "")}
        .alert("阅读提示",isPresented:Binding(get:{session.error != nil},set:{if !$0 {session.error=nil}})){Button("知道了"){session.error=nil}}message:{Text(session.error ?? "")}
    }
    var sidebar:some View {
        VStack(alignment:.leading,spacing:0){
            HStack(spacing:10){Image(systemName:"book.pages").font(.system(size:21,weight:.light)).foregroundStyle(theme.accent);VStack(alignment:.leading,spacing:2){Text("阅读从简").font(.system(size:17,weight:.semibold,design:.serif))}}.padding(.horizontal,16).padding(.top,23).padding(.bottom,24)
            Text("我的书库").font(.system(size:10,weight:.medium)).foregroundStyle(theme.muted).padding(.horizontal,16).padding(.bottom,10)
            VStack(spacing:5){SidebarDestination(title:"书架",symbol:"books.vertical",count:repository.books.count,selected:route=="books"){route="books";search=""};SidebarDestination(title:"我的想法",symbol:"quote.bubble",count:repository.annotations.filter{!$0.note.isEmpty}.count,selected:route=="thoughts"){route="thoughts";search=""}}
            if route=="reader",let book=session.book {
                Rectangle().fill(theme.line).frame(height:1).padding(.vertical,22).padding(.horizontal,14)
                Text("正在阅读").font(.system(size:10,weight:.medium)).foregroundStyle(theme.muted).padding(.horizontal,16)
                Text(book.title).font(.system(size:14,weight:.medium,design:.serif)).lineLimit(3).padding(.horizontal,16).padding(.top,10).padding(.bottom,18)
                Picker("书内导航",selection:$tab){Text("目录").tag("chapters");Text("划线").tag("marks")}.pickerStyle(.segmented).labelsHidden().padding(.horizontal,10)
                ScrollView{VStack(alignment:.leading,spacing:5){
                    if tab=="chapters" {ForEach(book.chapters){chapter in Button{session.navigate(chapter.path);route="reader"}label:{HStack(spacing:8){RoundedRectangle(cornerRadius:1).fill(session.chapter==chapter.path ? theme.accent:.clear).frame(width:3,height:18);Text(chapter.title).font(.system(size:12)).lineLimit(2);Spacer(minLength:2)}.padding(.vertical,9).padding(.horizontal,8).background(session.chapter==chapter.path ? theme.surface:.clear,in:RoundedRectangle(cornerRadius:7)).contentShape(Rectangle())}.buttonStyle(.plain)}}
                    else {let marks=repository.marks(for:book);if marks.isEmpty {Text("选中文字，就能留下划线。").font(.caption).foregroundStyle(theme.muted).padding(12)};ForEach(marks){mark in VStack(alignment:.leading,spacing:7){Button{open(book,mark)}label:{Text(mark.quote).font(.system(size:12,design:.serif)).lineSpacing(3).lineLimit(3).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain);HStack{Text(!mark.note.isEmpty ? "有想法":(mark.draft != nil ? "有草稿":"划线")).font(.system(size:9)).foregroundStyle(theme.muted);Spacer();Button("编辑"){session.editing=mark}.font(.system(size:10))}}.padding(12).background(theme.surface,in:RoundedRectangle(cornerRadius:8))}}
                }.padding(.horizontal,10).padding(.top,12)}
            }
            Spacer(minLength:20)
            if route != "reader",let book=session.book {Button{route="reader"}label:{HStack(spacing:9){Image(systemName:"book");VStack(alignment:.leading,spacing:3){Text("回到阅读").font(.system(size:9)).foregroundStyle(theme.muted);Text(book.title).font(.system(size:11)).lineLimit(1)};Spacer();Image(systemName:"arrow.up.right").font(.system(size:9))}.padding(12).background(theme.surface,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain).padding(.bottom,12)}
            Button(action:chooseBooks){Label(importing ? "正在导入…":"导入书籍",systemImage:"plus").frame(maxWidth:.infinity)}.buttonStyle(ReaderButtonStyle(prominent:true)).disabled(importing).padding(.horizontal,8)
            HStack(spacing:5){Image(systemName:"internaldrive");Text("本机保存 · EPUB / PDF")}.font(.system(size:9)).foregroundStyle(theme.muted).padding(.horizontal,14).padding(.top,14).padding(.bottom,21)
        }.padding(.horizontal,10).background(theme == .dark ? theme.sidebar:Color(hex:0xF7F8FA))
    }
    var topbar:some View {
        HStack(spacing:14){
            Button{navigation.toggle()} label: {Image(systemName:"sidebar.left")}.help("显示或隐藏侧栏")
            if route=="reader",let book=session.book {
                VStack(alignment:.leading,spacing:2){Text(book.title).font(.system(size:12,weight:.medium)).lineLimit(1);Text(book.chapters.first{$0.path==session.chapter}?.title ?? "章节不可用").font(.system(size:10)).foregroundStyle(.secondary)}
                Spacer()
                if book.format=="pdf" {
                    Menu{Button("放大"){pdfZoom(1.18)};Button("缩小"){pdfZoom(0.85)};Divider();Button("适合宽度"){book.pdfScale=0;try? repository.commit()};Button("向右旋转"){if session.pdfView?.document?.allowsDocumentAssembly == false {session.error="此 PDF 不允许页面旋转，可继续按原方向阅读。"}else{book.pdfRotation=(book.pdfRotation+90)%360;try? repository.commit()}}}label:{Text(book.pdfScale<=0 ? "适合宽度":"\(Int(book.pdfScale*100))%").font(.system(size:11,weight:.medium)).frame(minWidth:58)}.help("PDF 缩放与旋转")
                } else {
                    Button{fontPanel.toggle()}label:{Text("Aa").font(.system(size:16,weight:.medium,design:.serif)).frame(width:30,height:28)}.help("文字大小").popover(isPresented:$fontPanel){VStack(alignment:.leading,spacing:18){Text("文字大小").font(.system(size:13,weight:.semibold));HStack{Button{resizeFont(-1)}label:{Image(systemName:"textformat.size.smaller")}.buttonStyle(ReaderButtonStyle());Spacer();Text("\(Int(session.font)) pt").font(.system(size:14)).monospacedDigit();Spacer();Button{resizeFont(1)}label:{Image(systemName:"textformat.size.larger")}.buttonStyle(ReaderButtonStyle())};Slider(value:Binding(get:{session.font},set:{resizeFont($0-session.font)}),in:14...30,step:1).frame(width:210);Text("正文大小即时生效，阅读位置会保留。").font(.system(size:10)).foregroundStyle(theme.muted)}.padding(22).background(theme.surface).environment(\.readingTheme,theme)}
                }
                Button{marginNotes.toggle()}label:{Image(systemName:marginNotes ? "text.bubble.fill":"text.bubble").font(.system(size:14)).frame(width:28,height:28).foregroundStyle(marginNotes ? theme.accent:theme.muted).background(marginNotes ? theme.selection:.clear,in:RoundedRectangle(cornerRadius:7))}.help("页边备注").accessibilityLabel("页边备注").accessibilityValue(marginNotes ? "已开启":"已关闭")
            } else {
                Text(route=="books" ? "书架":"我的想法").font(.system(size:23,weight:.bold)).foregroundStyle(theme.ink);Spacer()
                TextField(route=="books" ? "搜索 \(repository.books.count) 本书":"搜索想法、原文或书名",text:$search).textFieldStyle(.plain).font(.system(size:12)).padding(.horizontal,13).padding(.vertical,9).background(theme == .dark ? theme.background:Color(hex:0xF4F5F7),in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:8).stroke(theme.line.opacity(0.6),lineWidth:1)).frame(maxWidth:265)
                if route=="thoughts" {
                    Menu { Button("导出全部想法…"){exportNotes(filtered:false)}.disabled(savedNotes.isEmpty);Button("导出当前搜索结果…"){exportNotes(filtered:true)}.disabled(thoughtItems.isEmpty) } label:{Label("导出笔记",systemImage:"square.and.arrow.up")}
                } else {Button(action:chooseBooks){Label("导入书籍",systemImage:"plus")}.disabled(importing)}
            }
            Menu{Picker("阅读主题",selection:$themeRaw){ForEach(ReadingTheme.allCases){t in Label(t.title,systemImage:t.symbol).tag(t.rawValue)}}}label:{Image(systemName:theme.symbol).frame(width:26,height:28)}.help("外观：素白、暖纸、深色")
        }.buttonStyle(.borderless).padding(.horizontal,24).frame(height:58).background(route == "reader" || theme == .dark ? theme.surface:Color.white)
    }
    @ViewBuilder var content:some View {
        switch route {
        case "reader":
            if let book=session.book {
                VStack(spacing:0){
                    if let failed=session.failed {failure(failed,book)}
                    if book.format=="pdf" {PDFReaderView(repository:repository,session:session).frame(maxWidth:.infinity,maxHeight:.infinity).id(book.id)} else if book.chapters.contains(where:{$0.path==session.chapter}) {ReaderWebView(repository:repository,session:session,revision:repository.revision,navigation:session.navigationToken,font:session.font,sidebar:session.sidebar,focus:session.focusID,theme:themeRaw).frame(maxWidth:.infinity,maxHeight:.infinity).id(book.id).overlay{if !session.ready {ProgressView("正在打开章节…")}}} else {empty("章节暂时不可用","备注和摘录仍保留在我的想法中。","doc.questionmark").frame(maxHeight:.infinity)}
                    Divider();HStack{Button(book.format=="pdf" ? "上一页":"上一章"){chapterStep(-1)}.disabled(chapterIndex==0);Spacer();if book.format=="pdf" {HStack{TextField("\(chapterIndex+1)",text:$pdfPageInput).textFieldStyle(.roundedBorder).frame(width:45).accessibilityLabel("跳转到 PDF 页码").onSubmit{if let page=Int(pdfPageInput),page>=1,page<=book.pdfPageCount {session.navigate("pdf:\(page-1)");pdfPageInput=""}else{session.error="请输入 1 到 \(book.pdfPageCount) 之间的页码。"}};Text("/ \(book.pdfPageCount) 页 · 位置自动保存")}.font(.caption).foregroundStyle(.secondary)}else{Text("\(chapterIndex+1) / \(book.chapters.count) 章 · 阅读位置自动保存").font(.caption).foregroundStyle(.secondary)};Spacer();Button(book.format=="pdf" ? "下一页":"下一章"){chapterStep(1)}.disabled(chapterIndex>=book.chapters.count-1)}.buttonStyle(.borderless).padding(.horizontal,22).frame(height:30)
                }
            } else {empty("先选一本书","从书架打开书籍，开始阅读。","book")}
        case "thoughts":thoughts
        default:bookshelf
        }
    }
    var filteredBooks:[Book]{repository.books.filter{search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.author.localizedCaseInsensitiveContains(search)}}
    var bookshelf:some View {
        ScrollView{VStack(alignment:.leading,spacing:16){
            if repository.books.isEmpty {VStack(spacing:18){empty("给书架添上第一本书","支持 EPUB 与 PDF，也可以从 Finder 拖入。","books.vertical");Button(action:chooseBooks){Label("导入书籍",systemImage:"plus")}.buttonStyle(ReaderButtonStyle(prominent:true))}.frame(maxWidth:.infinity).padding(.bottom,70)}
            else if filteredBooks.isEmpty {empty("没有找到书籍","试试其他书名或作者。","magnifyingglass")}
            else {
                HStack(spacing:6){Text(search.isEmpty ? "全部书籍":"搜索结果").font(.system(size:11,weight:.medium));Text("\(filteredBooks.count)").font(.system(size:10)).monospacedDigit();Spacer();Text("最近更新").font(.system(size:10))}.foregroundStyle(theme.muted)
                LazyVGrid(columns:[GridItem(.adaptive(minimum:112,maximum:148),spacing:16)],alignment:.leading,spacing:22){ForEach(filteredBooks){book in ShelfBookCard(book:book,directory:repository.directory(book)){open(book)}}}
            }
        }.padding(.horizontal,22).padding(.top,16).padding(.bottom,32).frame(maxWidth:.infinity,alignment:.leading)}.background(theme == .dark ? theme.background:Color.white)
    }
    var thoughts:some View {
        let items=thoughtItems
        return ScrollView{VStack(alignment:.leading,spacing:28){
            WorkspaceHeading(eyebrow:"",title:"我的想法",subtitle:"\(repository.annotations.filter{!$0.note.isEmpty}.count) 条已保存的想法 · 按最近更新排列")
            if items.isEmpty {empty(search.isEmpty ? "想法，从一句话开始":"没有找到想法",search.isEmpty ? "阅读时写下的正式想法，会在这里相遇。":"试试换一个书名、原文或想法中的词。","quote.bubble")}
            VStack(spacing:18){ForEach(items){mark in if let book=repository.books.first(where:{$0.id==mark.bookID}) {ThoughtCard(mark:mark,book:book){open(book,mark)}}}}
        }.frame(maxWidth:810,alignment:.leading).padding(.horizontal,availableWidth<900 ? 24:48).padding(.top,35).padding(.bottom,55).frame(maxWidth:.infinity)}.background(PaperSurface())
    }
    var savedNotes:[Annotation] {repository.annotations.filter{!$0.note.isEmpty}.sorted{$0.updatedAt > $1.updatedAt}}
    var thoughtItems:[Annotation] {savedNotes.filter{m in search.isEmpty || m.note.localizedCaseInsensitiveContains(search) || m.quote.localizedCaseInsensitiveContains(search) || repository.books.first{$0.id==m.bookID}?.title.localizedCaseInsensitiveContains(search)==true}}
    func exportNotes(filtered:Bool) {
        let marks=filtered ? thoughtItems:savedNotes
        guard !marks.isEmpty else {return}
        let items=marks.map { mark -> ExportedNote in
            let book=repository.books.first{$0.id==mark.bookID}
            let pages=Array(Set(mark.pdfPieces.map{$0.page+1})).sorted()
            let location = !pages.isEmpty ? "第 " + pages.map(String.init).joined(separator:"、") + " 页" : (book?.chapters.first{$0.path==mark.chapter}?.title ?? "章节不可用")
            return ExportedNote(book:book?.title ?? "书籍不可用",location:location,quote:mark.quote,note:mark.note,updated:mark.updatedAt)
        }
        let panel=NSSavePanel()
        panel.allowedContentTypes=[UTType(filenameExtension:"md") ?? .plainText]
        panel.nameFieldStringValue=filtered ? "我的想法-搜索结果.md":"我的想法.md"
        panel.title="导出笔记"
        panel.message="导出已保存的想法和引用原句，不包含未提交草稿。"
        panel.canCreateDirectories=true
        guard panel.runModal() == .OK,let url=panel.url else {return}
        let access=url.startAccessingSecurityScopedResource()
        defer {if access {url.stopAccessingSecurityScopedResource()}}
        do {try NoteExport.markdown(items).write(to:url,atomically:true,encoding:.utf8);exportMessage="已导出 \(items.count) 条想法到 \(url.lastPathComponent)"}
        catch {session.error="导出失败："+error.localizedDescription}
    }
    func failure(_ mark:Annotation,_ book:Book)->some View {
        VStack(alignment:.leading,spacing:8){Label("暂时无法定位原句",systemImage:"exclamationmark.triangle").font(.headline);Text(mark.note).lineLimit(3);Text(mark.quote).font(.caption).foregroundStyle(.secondary).lineLimit(2);HStack{if book.chapters.contains(where:{$0.path==mark.chapter}) {Button("打开对应章节"){session.navigate(mark.chapter)}};Button("返回我的想法"){route="thoughts"};Spacer();Button("编辑备注"){session.editing=mark}}}.padding(18).background(Color.orange.opacity(0.10))
    }
    func empty(_ title:String,_ message:String,_ icon:String)->some View {VStack(spacing:14){Image(systemName:icon).font(.system(size:38,weight:.light)).foregroundStyle(.secondary);Text(title).font(.system(size:27,weight:.medium,design:.serif));Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)}.frame(maxWidth:.infinity).padding(.top,65).padding(.bottom,26).padding(.horizontal,30)}
    var chapterIndex:Int {session.book?.chapters.firstIndex{$0.path==session.chapter} ?? 0}
    func chapterStep(_ delta:Int){if let b=session.book {let i=chapterIndex+delta;if b.chapters.indices.contains(i){session.navigate(b.chapters[i].path)}}}
    func pdfZoom(_ factor:Double){guard let book=session.book else{return};book.pdfScale=min(5,max(0.2,(session.pdfView?.scaleFactor ?? 1)*factor));do{try repository.commit()}catch{session.error=error.localizedDescription}}
    func resizeFont(_ delta:Double){session.font=min(30,max(14,session.font+delta));if let book=session.book {book.fontSize=session.font;do{try repository.commit()}catch{session.error=error.localizedDescription}}}
    func open(_ book:Book,_ mark:Annotation?=nil){session.open(book,annotation:mark);route="reader"}
    func chooseBooks(){let p=NSOpenPanel();p.allowedContentTypes=[.item];p.allowsMultipleSelection=true;p.canChooseDirectories=false;p.message="选择 EPUB 或 PDF 文件";if p.runModal() == .OK {let urls=p.urls;Task{@MainActor in await importURLs(urls)}}}
    func importURLs(_ urls:[URL]) async {
        guard !importing else {session.error="已有导入任务正在处理，请稍后再试。";return};importing=true;var lines:[String]=[]
        for url in urls {await Task.yield();do{let (book,duplicate)=try repository.importBook(url);lines.append((duplicate ? "已有书籍 · ":"已导入 · ")+book.title);if duplicate {open(book)}}catch{lines.append("导入失败 · \(url.lastPathComponent)\n\(error.localizedDescription)")}}
        importing=false;report=ImportReport(lines:lines)
    }
}
struct BookCover:View {
    let book:Book;let directory:URL
    private var hue:Color {let colors=[0x5E6F62,0x676B81,0x9C735D,0xAD9467,0x626F7C,0x815E61];let index=Int(book.contentHash.prefix(2),radix:16) ?? 0;return Color(hex:colors[index%colors.count])}
    var body:some View {
        GeometryReader{proxy in
            Group{if let path=book.cover,let image=NSImage(contentsOf:directory.appendingPathComponent(path)){Color.white.overlay{Image(nsImage:image).resizable().scaledToFit()}}
            else {ZStack(alignment:.leading){LinearGradient(colors:[hue,hue.opacity(0.90)],startPoint:.topLeading,endPoint:.bottomTrailing);Image("PaperGrain").resizable(resizingMode:.tile).opacity(0.2).blendMode(.overlay);LinearGradient(colors:[.black.opacity(0.24),.white.opacity(0.10),.clear],startPoint:.leading,endPoint:.trailing).frame(width:13);VStack(alignment:.leading,spacing:12){Text(book.format.uppercased()).font(.system(size:max(6,proxy.size.width*0.045),weight:.medium)).tracking(2).opacity(0.65);Rectangle().fill(.white.opacity(0.26)).frame(width:24,height:1);Text(book.title).font(.system(size:max(11,min(25,proxy.size.width*0.135)),weight:.medium,design:.serif)).lineSpacing(5).lineLimit(5).minimumScaleFactor(0.7);Spacer(minLength:4);Text(book.author).font(.system(size:max(6,proxy.size.width*0.055))).opacity(0.75).lineLimit(1)}.foregroundStyle(Color.white.opacity(0.94)).padding(.leading,max(12,proxy.size.width*0.13)).padding(.trailing,12).padding(.vertical,max(13,proxy.size.height*0.09))}}
            }.clipShape(RoundedRectangle(cornerRadius:4)).overlay(RoundedRectangle(cornerRadius:4).stroke(.black.opacity(0.06),lineWidth:0.6))
        }
    }
}
struct NoteEditor:View {
    @Environment(\.readingTheme) private var theme
    let repository:LibraryRepository;let mark:Annotation;let width:CGFloat;let close:()->Void
    @State private var text:String
    @State private var status="草稿 · 自动保存在本机"
    @State private var deleteKind=""
    init(repository:LibraryRepository,mark:Annotation,width:CGFloat=560,close:@escaping()->Void){self.repository=repository;self.mark=mark;self.width=width;self.close=close;_text=State(initialValue:mark.draft ?? mark.note)}
    var body:some View {
        VStack(alignment:.leading,spacing:16){HStack{Text("写在页边").font(.system(size:21,weight:.medium,design:.serif));Spacer();Button("稍后继续",action:close).keyboardShortcut(.cancelAction)}
            ScrollView{Text(mark.quote).font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(15).background(theme.background).clipShape(RoundedRectangle(cornerRadius:8))}.frame(maxHeight:110)
            TextEditor(text:$text).font(.system(size:14)).scrollContentBackground(.hidden).frame(minHeight:200).padding(12).background(theme.surface).overlay(RoundedRectangle(cornerRadius:9).stroke(theme.line)).accessibilityLabel("想法正文")
            Text(status).font(.caption).foregroundStyle(status.hasPrefix("未") ? Color.red:Color.secondary)
            HStack{Menu("删除…"){if !mark.note.isEmpty || mark.draft != nil {Button("仅删除备注",role:.destructive){deleteKind="note"}};Button("删除整条划线",role:.destructive){deleteKind="mark"}};Spacer();Button("保存想法"){do{try repository.saveNote(mark,text:text);close()}catch{status="未保存："+error.localizedDescription}}.buttonStyle(ReaderButtonStyle(prominent:true)).disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).keyboardShortcut("s")}
        }.padding(24).frame(width:width).background(theme.surface).foregroundStyle(theme.ink)
        .onChange(of:text){_,v in do{try repository.draft(mark,text:v);status="草稿已保存在本机"}catch{status="未保存草稿："+error.localizedDescription}}
        .alert(deleteKind=="note" ? "仅删除备注？":"删除整条划线？",isPresented:Binding(get:{!deleteKind.isEmpty},set:{if !$0{deleteKind=""}})){
            Button("取消",role:.cancel){deleteKind=""};Button("删除",role:.destructive){do{if deleteKind=="note"{try repository.deleteNote(mark)}else{try repository.deleteMark(mark)};close()}catch{status="未删除："+error.localizedDescription};deleteKind=""}
        }message:{Text(deleteKind=="note" ? "备注和该条草稿会被删除，并从『我的想法』移除。原句划线会保留。":"这条划线、关联备注和草稿将一并删除，此操作无法撤销。")}
    }
}
