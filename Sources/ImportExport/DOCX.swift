import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import DocumentCore

public struct ImportResult {
    public let document: ScribeDocument
    public let warnings: [String]
}
public enum DOCX {
    static let wordNS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    static let relationNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    public static func encode(_ document: ScribeDocument) throws -> Data {
        try NativeFormat.validate(document)
        return try DOCXWriter(document).encode()
    }
    public static func decode(_ data: Data) throws -> ImportResult {
        let files = try ZipArchive.decode(data)
        guard let content = files["word/document.xml"] else { throw DocumentError.invalid("DOCX has no main document part") }
        let delegate = WordReader(); delegate.files = files
        if let rels = files["word/_rels/document.xml.rels"] {
            let reader = RelationshipReader(); try parse(rels, delegate: reader); delegate.links = reader.links; delegate.targets = reader.targets
        }
        if let styles = files["word/styles.xml"] {
            let reader = StyleReader(); try parse(styles, delegate: reader)
            for style in reader.styles { delegate.document.updateStyle(style) }
            delegate.styleLists = reader.resolvedLists
        }
        if let numbering = files["word/numbering.xml"] { try parse(numbering, delegate: delegate.numbering) }
        try parse(content, delegate: delegate)
        delegate.warnings.formUnion(delegate.numbering.warnings)
        guard delegate.sawDocument else { throw DocumentError.invalid("missing Word document root") }
        if delegate.paragraphs.isEmpty { delegate.paragraphs = [Paragraph()] }
        delegate.document.sections[0].paragraphs = delegate.paragraphs
        for p in delegate.paragraphs where !delegate.document.styles.contains(where: { $0.id == p.styleID }) {
            delegate.document.updateStyle(ParagraphStyle(id: p.styleID, name: p.styleID))
        }
        if let data = files["word/comments.xml"] {
            let reader = DOCXCommentsReader(); try parse(data, delegate: reader)
            let index = DocumentTextIndex(paragraphs: delegate.paragraphs)
            for value in reader.values {
                var anchor = delegate.commentStarts[value.id] ?? delegate.commentReferences[value.id] ?? TextAnchor(paragraphID: delegate.paragraphs[0].id, offset: 0, length: 0)
                var detached = delegate.commentStarts[value.id] == nil && delegate.commentReferences[value.id] == nil
                if let end = delegate.commentEnds[value.id] {
                    if end.paragraphID == anchor.paragraphID { anchor.length = max(0, end.offset - anchor.offset) }
                    else { anchor.endParagraphID = end.paragraphID; anchor.endOffset = end.offset }
                    if let range = index.range(for: anchor) { anchor.length = range.length } else { detached = true }
                }
                var comment = Comment(anchor: anchor, text: value.text, author: value.author)
                if detached { comment.isDetached = true }
                delegate.document.comments.append(comment)
            }
        }
        if files.keys.contains(where: { $0.contains("footnotes") || $0.contains("endnotes") }) {
            delegate.warnings.insert("Footnotes and endnotes are not imported in this version.")
        }
        if files.keys.contains(where: { $0.contains("commentsExtended") || $0.contains("commentsExtensible") }) {
            delegate.warnings.insert("Modern comment threading and resolution metadata are not imported.")
        }
        for (id, isHeader) in [(delegate.headerID, true), (delegate.footerID, false)] {
            guard let id, let target = delegate.targets[id], let data = files["word/" + target] else { continue }
            let reader = WordReader(); try parse(data, delegate: reader)
            let text = reader.paragraphs.map(\.text).joined(separator: " ")
            if isHeader { delegate.document.sections[0].header = text } else { delegate.document.sections[0].footer = text }
            if String(data: data, encoding: .utf8)?.contains("fld") == true { delegate.warnings.insert("Running-content fields are imported as their cached text; update page numbering in Scribe if needed.") }
        }
        try NativeFormat.validate(delegate.document)
        return ImportResult(document: delegate.document, warnings: delegate.warnings.sorted())
    }
    static func parse(_ data: Data, delegate: XMLParserDelegate) throws {
        guard let xml = String(data: data, encoding: .utf8), !xml.localizedCaseInsensitiveContains("<!DOCTYPE") else { throw DocumentError.invalid("unsupported XML encoding or document type declaration") }
        let parser = XMLParser(data: data); parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), parser.parserError == nil else { throw DocumentError.invalid("malformed Office XML") }
    }
    static func xml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    static func runProperties(_ f: TextFormatting) -> String {
        var s = ""
        if let family = f.fontFamily { s += "<w:rFonts w:ascii=\"\(xml(family))\" w:hAnsi=\"\(xml(family))\"/>" }
        if let size = f.fontSize { s += "<w:sz w:val=\"\(Int(size * 2))\"/>" }
        if let b = f.bold { s += "<w:b w:val=\"\(b ? 1 : 0)\"/>" }
        if let i = f.italic { s += "<w:i w:val=\"\(i ? 1 : 0)\"/>" }
        if let u = f.underline { s += "<w:u w:val=\"\(u ? "single" : "none")\"/>" }
        if let strike = f.strikethrough { s += "<w:strike w:val=\"\(strike ? 1 : 0)\"/>" }
        if let color = f.foreground { s += "<w:color w:val=\"\(xml(color.replacingOccurrences(of: "#", with: "")))\"/>" }
        if let color = f.highlight { s += "<w:shd w:fill=\"\(xml(color.replacingOccurrences(of: "#", with: "")))\"/>" }
        if let baseline = f.baseline, baseline != 0 { s += "<w:vertAlign w:val=\"\(baseline > 0 ? "superscript" : "subscript")\"/>" }
        return s
    }
    static func paragraphProperties(_ f: ParagraphFormatting) -> String {
        "<w:jc w:val=\"\(f.alignment == .justified ? "both" : f.alignment.rawValue)\"/><w:spacing w:before=\"\(Int(f.spaceBefore * 20))\" w:after=\"\(Int(f.spaceAfter * 20))\"/><w:ind w:left=\"\(Int(f.headIndent * 20))\" w:right=\"\(Int(f.tailIndent * 20))\" \(f.firstLineIndent >= f.headIndent ? "w:firstLine" : "w:hanging")=\"\(Int(abs(f.firstLineIndent - f.headIndent) * 20))\"/>"
    }
    static func sectionProperties(_ p: PageSettings) -> String {
        "<w:sectPr><w:pgSz w:w=\"\(Int(p.width * 20))\" w:h=\"\(Int(p.height * 20))\"/><w:pgMar w:top=\"\(Int(p.top * 20))\" w:bottom=\"\(Int(p.bottom * 20))\" w:left=\"\(Int(p.left * 20))\" w:right=\"\(Int(p.right * 20))\"/></w:sectPr>"
    }
}

private func wordAttribute(_ a: [String: String], _ key: String = "val") -> String? { a["w:\(key)"] ?? a[key] }
private func flag(_ a: [String: String]) -> Bool { !["0", "false", "off"].contains(wordAttribute(a) ?? "1") }
private func applyRun(_ name: String, _ a: [String: String], _ f: inout TextFormatting) {
    switch name {
    case "rFonts": f.fontFamily = wordAttribute(a, "ascii") ?? wordAttribute(a, "hAnsi")
    case "sz": f.fontSize = wordAttribute(a).flatMap(Double.init).map { $0 / 2 }
    case "b": f.bold = flag(a)
    case "i": f.italic = flag(a)
    case "u": f.underline = wordAttribute(a) != "none"
    case "strike": f.strikethrough = flag(a)
    case "color": if let c = wordAttribute(a), c != "auto" { f.foreground = "#" + c }
    case "shd": if let c = wordAttribute(a, "fill"), c != "auto" { f.highlight = "#" + c }
    case "vertAlign": f.baseline = wordAttribute(a) == "superscript" ? 1 : wordAttribute(a) == "subscript" ? -1 : 0
    default: break
    }
}
private func applyParagraph(_ name: String, _ a: [String: String], _ f: inout ParagraphFormatting) {
    switch name {
    case "jc": f.alignment = wordAttribute(a) == "both" ? .justified : Alignment(rawValue: wordAttribute(a) ?? "left") ?? .left
    case "spacing":
        if let before = wordAttribute(a, "before").flatMap(Double.init) { f.spaceBefore = before / 20 }
        if let after = wordAttribute(a, "after").flatMap(Double.init) { f.spaceAfter = after / 20 }
    case "ind":
        if let left = (wordAttribute(a, "left") ?? wordAttribute(a, "start")).flatMap(Double.init) { f.headIndent = left / 20; f.firstLineIndent = f.headIndent }
        if let right = (wordAttribute(a, "right") ?? wordAttribute(a, "end")).flatMap(Double.init) { f.tailIndent = right / 20 }
        if let first = wordAttribute(a, "firstLine").flatMap(Double.init) { f.firstLineIndent = f.headIndent + first / 20 }
        if let hanging = wordAttribute(a, "hanging").flatMap(Double.init) { f.firstLineIndent = f.headIndent - hanging / 20 }
    default: break
    }
}
private class RelationshipReader: NSObject, XMLParserDelegate {
    var links: [String: String] = [:], targets: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if name == "Relationship", let id = a["Id"], let target = a["Target"] {
            if a["Type"]?.hasSuffix("/hyperlink") == true { links[id] = target }
            else if a["TargetMode"] != "External", !target.hasPrefix("/"), !target.split(separator: "/").contains("..") { targets[id] = target }
        }
    }
}
private struct StyleList {
    var id: String?
    var level: Int?
}
private class StyleReader: NSObject, XMLParserDelegate {
    private var lists: [String: StyleList] = [:], parents: [String: String] = [:]
    var resolvedLists: [String: StyleList] {
        var result: [String: StyleList] = [:]
        for style in styles {
            var chain: [String] = [], visited: Set<String> = [], id: String? = style.id
            while let next = id, visited.insert(next).inserted { chain.append(next); id = parents[next] }
            var list = StyleList()
            for item in chain.reversed() {
                if let value = lists[item]?.id { list.id = value }
                if let value = lists[item]?.level { list.level = value }
            }
            if list.id != nil { result[style.id] = list }
        }
        return result
    }
    var styles: [ParagraphStyle] = []; var current: ParagraphStyle?
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if name == "style", wordAttribute(a, "type") == "paragraph", let id = wordAttribute(a, "styleId") {
            current = ParagraphStyle(id: id, name: id)
        }
        guard current != nil else { return }
        if name == "basedOn" { parents[current!.id] = wordAttribute(a) }
        if name == "numId" { var list = lists[current!.id] ?? StyleList(); list.id = wordAttribute(a); lists[current!.id] = list }
        if name == "ilvl" { var list = lists[current!.id] ?? StyleList(); list.level = wordAttribute(a).flatMap(Int.init); lists[current!.id] = list }
        if name == "name" { current?.name = wordAttribute(a) ?? current!.name }
        if name == "outlineLvl", let level = wordAttribute(a).flatMap(Int.init), level < 9 { current?.headingLevel = level + 1 }
        applyRun(name, a, &current!.text)
        applyParagraph(name, a, &current!.paragraph)
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "style", let style = current { styles.append(style); current = nil }
    }
}
private class WordReader: NSObject, XMLParserDelegate {
    var document = ScribeDocument(), paragraphs: [Paragraph] = [], warnings: Set<String> = []
    var paragraph: Paragraph?, run = TextRun(""), collecting = false, links: [String: String] = [:], link: String?
    let numbering = DOCXNumberingReader()
    var commentStarts: [String: TextAnchor] = [:], commentEnds: [String: TextAnchor] = [:], commentReferences: [String: TextAnchor] = [:]
    var styleLists: [String: StyleList] = [:]
    var listID: String?, listLevel: Int?
    var inRun = false, sawDocument = false
    var files: [String: Data] = [:], targets: [String: String] = [:]
    var headerID: String?, footerID: String?
    var tableDepth = 0, tableIndex: Int?, row = -1, column = -1
    var inDrawing = false, drawingTarget: String?, drawingWidth = 100.0, drawingHeight = 100.0, drawingAlt = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if inDrawing {
            if name == "extent", let cx = a["cx"].flatMap(Double.init), let cy = a["cy"].flatMap(Double.init) { drawingWidth = cx / 12700; drawingHeight = cy / 12700 }
            if name == "docPr" { drawingAlt = a["descr"] ?? a["name"] ?? "" }
            if name == "blip", let id = a["r:embed"] ?? a["embed"] { drawingTarget = targets[id] }
            if name == "anchor" { warnings.insert("Floating images are imported inline with the text.") }
        }
        guard namespaceURI == DOCX.wordNS else { return }
        switch name {
        case "document": sawDocument = true
        case "p":
            paragraph = Paragraph(); paragraph?.runs = []; listID = nil; listLevel = nil
            if let t = tableIndex, row >= 0, column >= 0 { paragraph?.tableCell = TableCellReference(tableID: document.tables[t].id, row: row, column: column) }
        case "r": run = TextRun("", link: link); inRun = true
        case "t": collecting = true
        case "tab": run.text += "\t"
        case "br":
            if wordAttribute(a, "type") == "page" { paragraph?.pageBreakBefore = true }
            else { run.text += "\u{2028}" }
        case "pStyle": paragraph?.styleID = wordAttribute(a) ?? "normal"
        case "pageBreakBefore": paragraph?.pageBreakBefore = flag(a)
        case "ilvl": listLevel = min(8, max(0, wordAttribute(a).flatMap(Int.init) ?? 0))
        case "numId": listID = wordAttribute(a)
        case "jc", "spacing", "ind":
            if let p = paragraph {
                var formatting = p.formatting ?? document.style(for: p).paragraph
                applyParagraph(name, a, &formatting); paragraph?.formatting = formatting
            }
        case "commentRangeStart", "commentRangeEnd", "commentReference":
            if let id = wordAttribute(a, "id"), let paragraph {
                let offset = paragraph.runs.reduce(0) { $0 + ($1.text as NSString).length } + (inRun ? (run.text as NSString).length : 0)
                let anchor = TextAnchor(paragraphID: paragraph.id, offset: offset, length: 0)
                if name == "commentRangeStart" { commentStarts[id] = anchor }
                else if name == "commentRangeEnd" { commentEnds[id] = anchor }
                else { commentReferences[id] = anchor }
            }
        case "hyperlink": link = (a["r:id"] ?? a["id"]).flatMap { links[$0] }
        case "pgSz":
            if let w = wordAttribute(a, "w").flatMap(Double.init), let h = wordAttribute(a, "h").flatMap(Double.init) {
                document.sections[0].page.width = w / 20; document.sections[0].page.height = h / 20
            }
        case "pgMar":
            if let n = wordAttribute(a, "top").flatMap(Double.init) { document.sections[0].page.top = n / 20 }
            if let n = wordAttribute(a, "bottom").flatMap(Double.init) { document.sections[0].page.bottom = n / 20 }
            if let n = wordAttribute(a, "left").flatMap(Double.init) { document.sections[0].page.left = n / 20 }
            if let n = wordAttribute(a, "right").flatMap(Double.init) { document.sections[0].page.right = n / 20 }
        case "tbl":
            tableDepth += 1
            if tableDepth == 1 {
                var table = DocumentTable(rows: 1, columns: 1, width: document.sections[0].page.contentWidth)
                table.columnWidths = []; table.firstRowIsHeader = false
                document.tables.append(table); tableIndex = document.tables.count - 1; row = -1; column = -1
            } else { warnings.insert("Nested tables are flattened into the enclosing cell.") }
        case "gridCol":
            if tableDepth == 1, let t = tableIndex, let width = wordAttribute(a, "w").flatMap(Double.init) { document.tables[t].columnWidths.append(max(12, width / 20)) }
        case "tr": if tableDepth == 1 { row += 1; column = -1 }
        case "tc":
            if tableDepth == 1, let t = tableIndex {
                column += 1
                if column >= document.tables[t].columnWidths.count { document.tables[t].columnWidths.append(100) }
            }
        case "tblHeader": if let t = tableIndex { document.tables[t].firstRowIsHeader = true }
        case "gridSpan", "vMerge": warnings.insert("Merged cells are imported as individual cells; merged geometry is not retained.")
        case "drawing":
            if !run.text.isEmpty { paragraph?.runs.append(run); run = TextRun("", link: link) }
            inDrawing = true; drawingTarget = nil; drawingWidth = 100; drawingHeight = 100; drawingAlt = ""
        case "pict": warnings.insert("Legacy drawings are not imported.")
        case "headerReference": headerID = a["r:id"] ?? a["id"]
        case "footerReference": footerID = a["r:id"] ?? a["id"]
        case "ins", "del": warnings.insert("Tracked changes are flattened; review history is not retained.")
        case "sectPr": if !paragraphs.isEmpty && paragraph != nil { warnings.insert("Section settings are flattened to one page layout.") }
        default: if inRun { applyRun(name, a, &run.format) }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) { if collecting { run.text += text } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard namespaceURI == DOCX.wordNS else { return }
        switch name {
        case "t": collecting = false
        case "r": if !run.text.isEmpty { paragraph?.runs.append(run) }; inRun = false
        case "drawing":
            inDrawing = false
            if let target = drawingTarget, let data = files["word/" + target], ["png", "jpg", "jpeg", "tiff", "heic"].contains((target as NSString).pathExtension.lowercased()) {
                var imageRun = TextRun("\u{FFFC}")
                let scale = min(1, document.sections[0].page.contentWidth / max(1, drawingWidth), (document.sections[0].page.contentHeight - 24) / max(1, drawingHeight))
                imageRun.image = InlineImage(data: data, fileExtension: (target as NSString).pathExtension.lowercased(), width: max(1, drawingWidth * scale), height: max(1, drawingHeight * scale), altText: drawingAlt)
                paragraph?.runs.append(imageRun)
            } else { warnings.insert("An unsupported or missing image was omitted.") }
            run = TextRun("", link: link)
        case "tbl":
            if tableDepth == 1, let t = tableIndex {
                document.tables[t].rows = max(1, row + 1)
                if document.tables[t].columnWidths.isEmpty { document.tables[t].columnWidths = [100] }
                tableIndex = nil; row = -1; column = -1
            }
            tableDepth = max(0, tableDepth - 1)
        case "p":
            let inherited = paragraph.flatMap { styleLists[$0.styleID] }
            if let id = listID ?? inherited?.id { paragraph?.list = numbering.descriptor(id: id, level: listLevel ?? inherited?.level ?? 0) }
            if let p = paragraph { paragraphs.append(p) }; paragraph = nil
        case "hyperlink": link = nil
        default: break
        }
    }
}
