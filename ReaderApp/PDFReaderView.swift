import SwiftUI
import PDFKit

extension ReaderSession {
    var pdfPageIndex: Int { Int(chapter.replacingOccurrences(of:"pdf:",with:"")) ?? 0 }
}
struct PDFReaderView:View {
    @Environment(\.readingTheme) private var theme
    let repository:LibraryRepository
    let session:ReaderSession
    var body:some View {
        GeometryReader{proxy in
            HStack(spacing:0){
                NativePDFReader(repository:repository,session:session,revision:repository.revision,navigation:session.navigationToken,scale:session.book?.pdfScale ?? 0,rotation:session.book?.pdfRotation ?? 0,marginVisible:session.sidebar && proxy.size.width>=810,theme:theme)
                    .overlay(alignment:.bottom){if !session.pdfSelection.isEmpty {HStack{Text("已选择 \(session.pdfSelection.count) 个页面片段").font(.caption);Button("划线"){save(false)};Button("写想法"){save(true)}}.padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:10)).padding(18)}}
                if session.sidebar && proxy.size.width>=810,let book=session.book {
                    Divider();ScrollView{VStack(alignment:.leading,spacing:16){Text("页边想法").font(.system(size:18,weight:.medium,design:.serif));Text("可见页："+session.pdfVisiblePages.sorted().map{String($0+1)}.joined(separator:"、")).font(.system(size:10)).foregroundStyle(theme.muted)
                        let marks=repository.marks(for:book).filter{m in !m.note.isEmpty && m.pdfPieces.contains{session.pdfVisiblePages.contains($0.page)}}
                        if marks.isEmpty {Text("在原句旁留下一个想法。已保存的备注会按页出现在这里。").font(.callout).foregroundStyle(.secondary)}
                        ForEach(marks){mark in VStack(alignment:.leading,spacing:10){Text(mark.note).font(.system(size:14,design:.serif)).lineSpacing(5).lineLimit(session.pdfExpanded.contains(mark.id) ? nil:4);Text(mark.pdfPieces.map{$0.page+1}.map(String.init).joined(separator:", ")+" 页 · "+mark.quote).font(.system(size:11)).foregroundStyle(theme.muted).lineLimit(2);HStack{Button("回到原文"){session.focusID=mark.id;session.navigationToken=UUID()};Button("编辑"){session.editing=mark};Button(session.pdfExpanded.contains(mark.id) ? "收起":"展开"){if session.pdfExpanded.contains(mark.id){session.pdfExpanded.remove(mark.id)}else{session.pdfExpanded.insert(mark.id)}}}.font(.system(size:10)).buttonStyle(.plain).foregroundStyle(theme.accent)}.padding(17).background(theme.surface,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(theme.line,lineWidth:1))}
                    }.padding(18)}.frame(width:264).background(theme.chrome)
                }
            }.overlay(alignment:.topLeading){if !session.pdfNotice.isEmpty {Text(session.pdfNotice).font(.caption).padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:8)).padding(12)}}
        }
    }
    func save(_ note:Bool){guard let book=session.book else{return};do{let mark=try repository.pdfMark(book:book,pieces:session.pdfSelection);session.pdfView?.clearSelection();session.pdfSelection=[];if note{session.editing=mark}}catch{session.error=error.localizedDescription}}
}
final class WidthFittingPDFView:PDFView {
    var onReaderAnnotation:((UUID)->Void)?
    override func mouseDown(with event:NSEvent){let point=convert(event.locationInWindow,from:nil);if let page=page(for:point,nearest:false),let annotation=page.annotation(at:convert(point,to:page)),annotation.type==PDFAnnotationSubtype.text.rawValue,let raw=annotation.userName,raw.hasPrefix("reader:"),let id=UUID(uuidString:String(raw.dropFirst(7))){onReaderAnnotation?(id);return};super.mouseDown(with:event)}
    var fitsPageWidth=true
    private var fitting=false
    override func layout(){super.layout();guard fitsPageWidth,!fitting,bounds.width>60,let page=currentPage ?? document?.page(at:0) else{return};let rendered=convert(page.bounds(for:.cropBox),from:page);guard rendered.width>1,scaleFactor>0 else{return};let desired=min(5,max(0.1,scaleFactor*(bounds.width-48)/rendered.width));guard abs(desired-scaleFactor)>0.003 else{return};fitting=true;let destination=currentDestination;autoScales=false;scaleFactor=desired;if let destination{go(to:destination)};fitting=false}
}
struct NativePDFReader:NSViewRepresentable {
    let repository:LibraryRepository;let session:ReaderSession
    let revision:Int
    let navigation:UUID
    let scale:Double
    let rotation:Int
    let marginVisible:Bool
    let theme:ReadingTheme
    func makeCoordinator()->Coordinator {Coordinator(repository:repository,session:session)}
    func makeNSView(context:Context)->PDFView {
        let view=WidthFittingPDFView();view.displayMode = .singlePageContinuous;view.displayDirection = .vertical;view.autoScales=true;view.displaysPageBreaks=true;view.pageBreakMargins=NSEdgeInsets(top:12,left:18,bottom:12,right:18);view.backgroundColor = .windowBackgroundColor;view.acceptsDraggedFiles=false;view.delegate=context.coordinator
        session.pdfView=view;context.coordinator.attach(view);return view
    }
    func updateNSView(_ view:PDFView,context:Context){view.backgroundColor=theme.pdfCanvas;context.coordinator.marginVisible=marginVisible;context.coordinator.update(view)}
    static func pieces(_ selection:PDFSelection,document:PDFDocument) -> [PDFPiece] {
        var pieces:[PDFPiece]=[]
        for page in selection.pages {
            let index=document.index(for:page),text=(page.string ?? "") as NSString
            guard index != NSNotFound else{continue}
            for i in 0..<selection.numberOfTextRanges(on:page) {
                let range=selection.range(at:i,on:page)
                guard range.location != NSNotFound,range.length>0,range.location+range.length<=text.length,let selected=page.selection(for:range) else{continue}
                let boxes=selected.selectionsByLine().map{PDFBox($0.bounds(for:page))}.filter{!$0.rect.isEmpty}
                guard !boxes.isEmpty else{continue}
                let prefixRange=NSRange(location:max(0,range.location-48),length:min(48,range.location))
                let suffixStart=range.location+range.length
                pieces.append(PDFPiece(page:index,start:range.location,length:range.length,quote:text.substring(with:range),prefix:text.substring(with:prefixRange),suffix:text.substring(with:NSRange(location:suffixStart,length:min(48,text.length-suffixStart))),boxes:boxes))
            }
        }
        return pieces
    }
    static func resolve(_ piece:PDFPiece,document:PDFDocument)->PDFSelection? {
        guard let page=document.page(at:piece.page),let content=page.string else{return nil};let text=content as NSString
        if piece.start>=0,piece.length>0,piece.start<=text.length-piece.length,text.substring(with:NSRange(location:piece.start,length:piece.length))==piece.quote {return page.selection(for:NSRange(location:piece.start,length:piece.length))}
        guard !piece.quote.isEmpty else{return nil};var hits:[NSRange]=[],offset=0
        while offset<text.length {let found=text.range(of:piece.quote,range:NSRange(location:offset,length:text.length-offset));if found.location==NSNotFound{break}
            let before=text.substring(with:NSRange(location:max(0,found.location-piece.prefix.utf16.count),length:min(piece.prefix.utf16.count,found.location))),afterStart=found.location+found.length
            let after=text.substring(with:NSRange(location:afterStart,length:min(piece.suffix.utf16.count,text.length-afterStart)))
            if before==piece.prefix && after==piece.suffix{hits.append(found)};offset=found.location+max(1,found.length)
        }
        return hits.count==1 ? page.selection(for:hits[0]):nil
    }
    @MainActor final class Coordinator:NSObject,PDFViewDelegate {
        let repository:LibraryRepository;let session:ReaderSession
        weak var view:PDFView?;var bookID:UUID?;var token:UUID?;var marksFingerprint="";var generated:[(PDFPage,PDFAnnotation)]=[];var observers:[NSObjectProtocol]=[];var saveWork:DispatchWorkItem?;var baseRotations:[Int]=[];var rotation=0;var applying=false;var marginVisible=false
        init(repository:LibraryRepository,session:ReaderSession){self.repository=repository;self.session=session}
        deinit{observers.forEach{NotificationCenter.default.removeObserver($0)}}
        func attach(_ view:PDFView){self.view=view
            (view as? WidthFittingPDFView)?.onReaderAnnotation={[weak self]id in guard let self,let mark=self.repository.annotations.first(where:{$0.id==id}) else{return};self.session.editing=mark}
            for name in [Notification.Name.PDFViewSelectionChanged,.PDFViewPageChanged,.PDFViewVisiblePagesChanged,.PDFViewScaleChanged] {observers.append(NotificationCenter.default.addObserver(forName:name,object:view,queue:.main){[weak self]_ in Task{@MainActor in self?.changed()}})}
            observers.append(NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:nil,queue:.main){[weak self]n in guard let clip=n.object as? NSView,let view=self?.view,clip.isDescendant(of:view) else{return};Task{@MainActor in self?.changed()}})
            observers.append(NotificationCenter.default.addObserver(forName:.PDFViewAnnotationHit,object:view,queue:.main){[weak self]n in guard let annotation=n.userInfo?.values.compactMap({$0 as? PDFAnnotation}).first,let raw=annotation.userName,raw.hasPrefix("reader:"),let id=UUID(uuidString:String(raw.dropFirst(7))) else{return};Task{@MainActor in if let self,let mark=self.repository.annotations.first(where:{$0.id==id}) {self.session.editing=mark}}})
        }
        func update(_ view:PDFView){
            guard let book=session.book,book.format=="pdf" else{return};applying=true;defer{applying=false}
            if bookID != book.id {
                guard let doc=PDFDocument(url:repository.directory(book).appendingPathComponent("content.pdf")),!doc.isLocked else{session.error="PDF 副本暂时无法打开，备注仍已保留。";return}
                bookID=book.id;view.document=doc;baseRotations=(0..<doc.pageCount).map{doc.page(at:$0)?.rotation ?? 0};rotation = -1;token=nil;marksFingerprint=""
                session.pdfNotice=(doc.allowsCopying && doc.allowsCommenting) ? ((doc.string?.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ?? true) ? "此 PDF 没有可选文字，可阅读和缩放；本轮不含 OCR。":"") : "此 PDF 限制文字复制或批注，可阅读，但不能创建文字标记。"
            }
            guard let doc=view.document else{return}
            if rotation != book.pdfRotation {let destination=view.currentDestination;rotation=book.pdfRotation;for i in 0..<doc.pageCount {let desired=(baseRotations[i]+rotation)%360;if let page=doc.page(at:i),page.rotation != desired,doc.allowsDocumentAssembly{page.rotation=desired}};view.layoutDocumentView();if let destination {view.go(to:destination)}}
            if let fitting=view as? WidthFittingPDFView {fitting.fitsPageWidth=book.pdfScale<=0};if book.pdfScale<=0 {view.needsLayout=true}else if abs(view.scaleFactor-book.pdfScale)>0.001 {let destination=view.currentDestination;view.autoScales=false;view.scaleFactor=book.pdfScale;if let destination{view.go(to:destination)}}
            let marks=repository.marks(for:book),fingerprint=marks.map{"\($0.id)-\($0.updatedAt.timeIntervalSince1970)-\($0.note)"}.joined()
            if fingerprint != marksFingerprint {marksFingerprint=fingerprint;for(p,a)in generated{p.removeAnnotation(a)};generated=[]
                for mark in marks {for piece in mark.pdfPieces {guard let page=doc.page(at:piece.page),Self.valid(piece,doc:doc) else{continue};for box in piece.boxes {let a=PDFAnnotation(bounds:box.rect,forType:.highlight,withProperties:nil);a.color=NSColor.systemYellow.withAlphaComponent(0.35);a.userName="reader:"+mark.id.uuidString;page.addAnnotation(a);generated.append((page,a))}
                    if let box=piece.boxes.first {let a=PDFAnnotation(bounds:CGRect(x:box.x+box.width+4,y:box.y,width:16,height:16),forType:.text,withProperties:nil);a.contents=mark.note.isEmpty ? "划线：点击编辑想法":mark.note;a.userName="reader:"+mark.id.uuidString;a.color = .systemGreen;page.addAnnotation(a);generated.append((page,a))}
                }}
            }
            if token != session.navigationToken {token=session.navigationToken
                if let id=session.focusID,let mark=marks.first(where:{$0.id==id}) {
                    let pieces=mark.pdfPieces,resolved=pieces.compactMap{NativePDFReader.resolve($0,document:doc)}
                    if !pieces.isEmpty,resolved.count==pieces.count {let selection=PDFSelection(document:doc);selection.add(resolved);view.setCurrentSelection(selection,animate:true);view.go(to:selection);view.scrollSelectionToVisible(nil);DispatchQueue.main.asyncAfter(deadline:.now()+0.08){[weak self] in guard let self,self.session.focusID==mark.id else{return};if !self.marginVisible {self.session.pdfPopup=mark}};session.failed=nil}
                    else {session.failed=mark}
                }else if let page=doc.page(at:session.pdfPageIndex){let point=(book.chapterPath==session.chapter && (book.pdfProgressX != 0 || book.pdfProgressY != 0)) ? CGPoint(x:book.pdfProgressX,y:book.pdfProgressY):CGPoint(x:page.bounds(for:.cropBox).minX,y:page.bounds(for:.cropBox).maxY);view.go(to:PDFDestination(page:page,at:point))}
            }
            session.ready=true;session.pdfVisiblePages=Set(view.visiblePages.map{doc.index(for:$0)});if session.pdfVisiblePages.isEmpty{session.pdfVisiblePages=[session.pdfPageIndex]}
        }
        static func valid(_ piece:PDFPiece,doc:PDFDocument)->Bool {NativePDFReader.resolve(piece,document:doc) != nil}
        func changed(){guard !applying,let view,let doc=view.document,let book=session.book,book.id==bookID else{return}
            if doc.allowsCopying && doc.allowsCommenting,let selection=view.currentSelection,!(selection.string ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {session.pdfSelection=NativePDFReader.pieces(selection,document:doc)}else{session.pdfSelection=[]}
            session.pdfVisiblePages=Set(view.visiblePages.map{doc.index(for:$0)})
            saveWork?.cancel();let work=DispatchWorkItem{[weak self]in guard let self,let destination=view.currentDestination,let page=destination.page else{return};do{try self.repository.pdfProgress(book,page:doc.index(for:page),point:destination.point);self.session.chapter=book.chapterPath}catch{self.session.error=error.localizedDescription}};saveWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.3,execute:work)
        }
        func pdfViewWillClick(onLink sender:PDFView,with url:URL){session.error="本地阅读器不会自动打开 PDF 中的外部链接。"}
        func pdfViewOpenPDF(_ sender:PDFView,forRemoteGoToAction action:PDFActionRemoteGoTo){session.error="不支持从 PDF 自动打开外部文件。"}
    }
}
