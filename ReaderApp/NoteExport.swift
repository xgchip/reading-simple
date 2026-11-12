import Foundation

struct ExportedNote {
    let book: String
    let location: String
    let quote: String
    let note: String
    let updated: Date
}
enum NoteExport {
    static func markdown(_ notes: [ExportedNote]) -> String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "zh_CN")
        date.dateFormat = "yyyy-MM-dd HH:mm"
        func escape(_ text: String) -> String {
            var result = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            for c in ["\\", "`", "*", "_", "{", "}", "[", "]", "<", ">", "#", "|", "~"] { result = result.replacingOccurrences(of: c, with: "\\" + c) }
            return result
        }
        var output = "# 我的想法\n\n共 \(notes.count) 条已保存的想法\n\n"
        for item in notes {
            output += "## \(escape(item.book).replacingOccurrences(of: "\n", with: " "))\n\n"
            output += "位置：\(escape(item.location))  \n更新时间：\(date.string(from: item.updated))\n\n"
            output += escape(item.quote).components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n") + "\n\n"
            output += escape(item.note) + "\n\n---\n\n"
        }
        return output
    }
}
