import Foundation
import DocumentCore

public enum TextFormats {
    public static func plainText(_ text: String) -> ScribeDocument {
        var document = ScribeDocument()
        document.sections[0].paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n").map { Paragraph($0) }
        return document
    }
    /// A deliberately limited Markdown subset; unsupported syntax remains literal text.
    public static func markdown(_ text: String) -> ScribeDocument {
        var document = plainText(text)
        document.sections[0].paragraphs = document.paragraphs.map { original in
            var p = original; var text = p.text
            for level in (1...3).reversed() {
                let prefix = String(repeating: "#", count: level) + " "
                if text.hasPrefix(prefix) { p.styleID = "heading\(level)"; text.removeFirst(prefix.count); break }
            }
            if text.hasPrefix("> ") { p.styleID = "quote"; text.removeFirst(2) }
            if text.hasPrefix("- ") || text.hasPrefix("* ") { p.list = ListDescriptor(); text.removeFirst(2) }
            if let range = text.range(of: "^\\d+\\. ", options: .regularExpression) {
                p.list = ListDescriptor(kind: .decimal); text.removeSubrange(range)
            }
            p.runs = parseInline(text); return p
        }
        return document
    }
    private static func parseInline(_ text: String) -> [TextRun] {
        let pattern = "\\*\\*(.+?)\\*\\*|\\*(.+?)\\*|`(.+?)`|\\[([^\\]]+)\\]\\(([^)]+)\\)"
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString; var runs: [TextRun] = []; var position = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > position { runs.append(TextRun(ns.substring(with: NSRange(location: position, length: match.range.location - position)))) }
            var format = TextFormatting(); var value = ""; var link: String?
            if match.range(at: 1).location != NSNotFound { format.bold = true; value = ns.substring(with: match.range(at: 1)) }
            else if match.range(at: 2).location != NSNotFound { format.italic = true; value = ns.substring(with: match.range(at: 2)) }
            else if match.range(at: 3).location != NSNotFound { format.fontFamily = "Menlo"; value = ns.substring(with: match.range(at: 3)) }
            else { value = ns.substring(with: match.range(at: 4)); link = ns.substring(with: match.range(at: 5)) }
            runs.append(TextRun(value, format: format, link: link)); position = NSMaxRange(match.range)
        }
        if position < ns.length { runs.append(TextRun(ns.substring(from: position))) }
        return runs.isEmpty ? [TextRun("")] : runs
    }
    public static func exportMarkdown(_ document: ScribeDocument) -> String {
        document.paragraphs.map { p in
            let style = document.style(for: p)
            var prefix = style.headingLevel.map { String(repeating: "#", count: $0) + " " } ?? ""
            if p.styleID == "quote" { prefix = "> " }
            if let list = p.list { prefix = String(repeating: "  ", count: list.level) + (list.kind == .bullet ? "- " : "1. ") }
            return prefix + p.runs.map { run in
                if let equation = run.equation {
                    let longest = equation.source.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
                    let fence = String(repeating: "`", count: longest + 1)
                    return fence + " " + equation.source + " " + fence
                }
                var text = run.text
                if run.format.bold == true { text = "**\(text)**" }
                if run.format.italic == true { text = "*\(text)*" }
                if let link = run.link { text = "[\(text)](\(link))" }
                return text
            }.joined()
        }.joined(separator: "\n")
    }
}
