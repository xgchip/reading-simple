import SwiftUI
import AppKit

enum ReadingTheme:String, CaseIterable, Identifiable {
    case white, paper, dark
    var id:String {rawValue}
    var title:String {switch self {case .white:"素白";case .paper:"暖纸";case .dark:"深色"}}
    var symbol:String {switch self {case .white:"sun.max";case .paper:"book.closed";case .dark:"moon"}}
    var scheme:ColorScheme {self == .dark ? .dark:.light}
    private func value(_ key:String,_ fallback:Int)->Int {let raw=ThemeRegistry.colors[rawValue]?[key] as? String;return raw.flatMap{Int($0.replacingOccurrences(of:"#",with:""),radix:16)} ?? fallback}
    var background:Color {Color(hex:value("canvas",0xF7F4EC))}
    var chrome:Color {Color(hex:value("chrome",0xEFECE5))}
    var sidebar:Color {chrome}
    var surface:Color {Color(hex:value("surface",0xFFFCF6))}
    var ink:Color {Color(hex:value("ink",0x302F2B))}
    var muted:Color {Color(hex:value("secondary",0x6D7068))}
    var accent:Color {Color(hex:value("accent",0x647557))}
    var line:Color {Color(hex:value("line",0xDEDCD2))}
    var selection:Color {Color(hex:value("selection",0xE1E5D7))}
    var texture:String? {self == .white ? nil:(self == .paper ? "paper-warm":"paper-dark")}
    var pdfCanvas:NSColor {
        if !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,!NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,let texture,let url=Bundle.main.url(forResource:texture,withExtension:"png"),let image=NSImage(contentsOf:url) {return NSColor(patternImage:image)}
        return NSColor(hex:value("chrome",0xEFECE5))
    }

}
private enum ThemeRegistry {
    static let colors:[String:[String:Any]] = {
        guard let url=Bundle.main.url(forResource:"DesignTokens",withExtension:"json"),let data=try? Data(contentsOf:url),let root=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let themes=root["themes"] as? [String:[String:Any]] else{return [:]};return themes
    }()
}
private struct ReadingThemeKey:EnvironmentKey {static let defaultValue:ReadingTheme = .paper}
extension EnvironmentValues {var readingTheme:ReadingTheme {get {self[ReadingThemeKey.self]} set {self[ReadingThemeKey.self]=newValue}}}
extension Color {init(hex:Int){self.init(.sRGB,red:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255,opacity:1)}}
extension NSColor {convenience init(hex:Int){self.init(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)}}
struct PaperSurface:View {
    @Environment(\.readingTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body:some View {theme.background.overlay{if !reduceTransparency,contrast != .increased,let texture=theme.texture {Image(texture).resizable(resizingMode:.tile).allowsHitTesting(false)}}}
}
struct ReaderButtonStyle:ButtonStyle {
    @Environment(\.readingTheme) private var theme
    var prominent=false
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:12,weight:.medium)).padding(.horizontal,12).padding(.vertical,8)
            .foregroundStyle(prominent ? theme.surface:theme.ink)
            .background(prominent ? theme.accent:(configuration.isPressed ? theme.line.opacity(0.55):theme.surface))
            .clipShape(RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(theme.line.opacity(prominent ? 0:0.8),lineWidth:1))
            .opacity(configuration.isPressed ? 0.78:1)
    }
}
