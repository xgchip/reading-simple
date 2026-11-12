import SwiftUI

struct WorkspaceHeading:View {
    @Environment(\.readingTheme) private var theme
    let eyebrow:String
    let title:String
    let subtitle:String
    var body:some View {VStack(alignment:.leading,spacing:9){if !eyebrow.isEmpty {Text(eyebrow).font(.system(size:11,weight:.semibold)).tracking(1.7).foregroundStyle(theme.muted)};Text(title).font(.system(size:30,weight:.medium,design:.serif)).foregroundStyle(theme.ink);Text(subtitle).font(.system(size:13)).foregroundStyle(theme.muted)}}
}
struct SidebarDestination:View {
    @Environment(\.readingTheme) private var theme
    let title:String
    let symbol:String
    let count:Int
    let selected:Bool
    let action:()->Void
    var body:some View {Button(action:action){HStack(spacing:8){Image(systemName:symbol).font(.system(size:15,weight:.medium)).frame(width:20);Text(title).font(.system(size:13,weight:selected ? .semibold:.regular));Spacer();Text("\(count)").font(.system(size:11,weight:.medium)).monospacedDigit().foregroundStyle(selected ? Color.white.opacity(0.8):theme.muted)}.padding(.horizontal,10).padding(.vertical,9).contentShape(RoundedRectangle(cornerRadius:9))}.buttonStyle(.plain).foregroundStyle(selected ? Color.white:theme.ink).background(selected ? (theme == .dark ? Color(hex:0x596653):Color(hex:0x232831)):Color.clear,in:RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(selected ? theme.line.opacity(0.6):.clear,lineWidth:1))}
}
struct ShelfBookCard:View {
    @Environment(\.readingTheme) private var theme
    let book:Book
    let directory:URL
    let action:()->Void
    @State private var hovered=false
    var body:some View {
        Button(action:action){VStack(alignment:.leading,spacing:7){
            BookCover(book:book,directory:directory).aspectRatio(0.70,contentMode:.fit)
                .offset(y:hovered ? -3:0)
                .shadow(color:.black.opacity(hovered ? 0.19:0.11),radius:hovered ? 9:4,x:0,y:hovered ? 6:2)
            Text(book.title).font(.system(size:12,weight:.medium)).foregroundStyle(theme.ink).lineLimit(2).frame(height:32,alignment:.topLeading).frame(maxWidth:.infinity,alignment:.leading)
            HStack(spacing:4){Text(book.format.uppercased()).font(.system(size:9,weight:.medium));Text("·");Text("第 \((book.chapters.firstIndex{$0.path==book.chapterPath} ?? 0)+1) \(book.format=="pdf" ? "页":"章")").lineLimit(1);Spacer(minLength:0)}.font(.system(size:10)).foregroundStyle(theme.muted)
        }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())}
        .buttonStyle(.plain).onHover{hovered=$0}.animation(.easeOut(duration:0.18),value:hovered)
        .help(book.title + " · " + book.author)
    }

}
struct ContinueReadingCard:View {
    @Environment(\.readingTheme) private var theme
    let book:Book
    let directory:URL
    let action:()->Void
    var body:some View {Button(action:action){HStack(spacing:26){BookCover(book:book,directory:directory).frame(width:78,height:112).rotationEffect(.degrees(-4)).shadow(color:.black.opacity(0.13),radius:7,x:2,y:5);VStack(alignment:.leading,spacing:10){Text("继续阅读").font(.system(size:10,weight:.semibold)).tracking(1.5).foregroundStyle(theme.accent);Text(book.title).font(.system(size:24,weight:.medium,design:.serif)).foregroundStyle(theme.ink).lineLimit(1);HStack(spacing:8){Text(book.author);Text("·");Text(book.chapters.first{$0.path==book.chapterPath}?.title ?? "从上次的位置继续")}.font(.system(size:12)).foregroundStyle(theme.muted).lineLimit(1)};Spacer(minLength:12);Image(systemName:"arrow.up.right").font(.system(size:20,weight:.light)).foregroundStyle(theme.accent).frame(width:42,height:42).background(theme.accent.opacity(0.07),in:Circle())}.padding(.horizontal,30).padding(.vertical,23).frame(maxWidth:.infinity,alignment:.leading).background(theme.surface,in:RoundedRectangle(cornerRadius:15)).overlay(RoundedRectangle(cornerRadius:15).stroke(theme.line.opacity(0.75),lineWidth:1))}.buttonStyle(.plain)}
}
struct ThoughtCard:View {
    @Environment(\.readingTheme) private var theme
    let mark:Annotation
    let book:Book
    let action:()->Void
    @State private var hovered=false
    var body:some View {Button(action:action){VStack(alignment:.leading,spacing:17){HStack{Image(systemName:"quote.opening").font(.system(size:17,weight:.light)).foregroundStyle(theme.accent.opacity(0.55));Spacer();Text(mark.updatedAt,style:.date).font(.system(size:10)).foregroundStyle(theme.muted)};Text(mark.note).font(.system(size:17,weight:.regular,design:.serif)).lineSpacing(6).foregroundStyle(theme.ink).frame(maxWidth:.infinity,alignment:.leading);Text(mark.quote).font(.system(size:13)).lineSpacing(5).foregroundStyle(theme.muted).lineLimit(3).padding(.leading,14).overlay(alignment:.leading){Capsule().fill(theme.accent.opacity(0.25)).frame(width:2)};Rectangle().fill(theme.line.opacity(0.7)).frame(height:1);HStack(spacing:8){Image(systemName:"book.closed").font(.system(size:11));Text(book.title).lineLimit(1);Text("·");Text(book.chapters.first{$0.path==mark.chapter}?.title ?? "章节不可用").lineLimit(1);Spacer();Image(systemName:"arrow.up.right")}.font(.system(size:11)).foregroundStyle(theme.muted)}.padding(25).frame(maxWidth:.infinity,alignment:.leading).background(theme.surface,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(hovered ? theme.accent.opacity(0.6):theme.line.opacity(0.70),lineWidth:1))}.buttonStyle(.plain).onHover{hovered=$0}.accessibilityLabel("返回原文，"+book.title+"。"+mark.note)}
}
