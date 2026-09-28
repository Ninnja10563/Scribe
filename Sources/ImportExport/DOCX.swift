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
        var relationships: [(String, String)] = []
        var body = ""
        for (sectionIndex, section) in document.sections.enumerated() {
            for p in section.paragraphs {
                var properties = "<w:pStyle w:val=\"\(xml(p.styleID))\"/>"
                if p.pageBreakBefore { properties += "<w:pageBreakBefore/>" }
                if let formatting = p.formatting { properties += paragraphProperties(formatting) }
                if let list = p.list {
                    properties += "<w:numPr><w:ilvl w:val=\"\(list.level)\"/><w:numId w:val=\"\(list.kind == .bullet ? 1 : 2)\"/></w:numPr>"
                }
                let runs = p.runs.map { run -> String in
                    let content = "<w:r><w:rPr>\(runProperties(run.format))</w:rPr><w:t xml:space=\"preserve\">\(xml(run.text))</w:t></w:r>"
                    guard let link = run.link else { return content }
                    let id = "link\(relationships.count + 1)"; relationships.append((id, link))
                    return "<w:hyperlink r:id=\"\(id)\">\(content)</w:hyperlink>"
                }.joined()
                body += "<w:p><w:pPr>\(properties)</w:pPr>\(runs)</w:p>"
            }
            let settings = sectionProperties(section.page)
            body += sectionIndex == document.sections.count - 1 ? settings : "<w:p><w:pPr>\(settings)</w:pPr></w:p>"
        }
        let styles = document.styles.map { style in
            "<w:style w:type=\"paragraph\" w:styleId=\"\(xml(style.id))\"\(style.id == "normal" ? " w:default=\"1\"" : "")><w:name w:val=\"\(xml(style.name))\"/><w:pPr>\(paragraphProperties(style.paragraph))\(style.headingLevel.map { "<w:outlineLvl w:val=\"\($0 - 1)\"/>" } ?? "")</w:pPr><w:rPr>\(runProperties(style.text))</w:rPr></w:style>"
        }.joined()
        let rels = relationships.map { "<Relationship Id=\"\($0.0)\" Type=\"\(relationNS)/hyperlink\" Target=\"\(xml($0.1))\" TargetMode=\"External\"/>" }.joined()
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/></Types>
        """
        let numbering = (1...2).map { id in
            let levels = (0...8).map { level in
                "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"\(id == 1 ? "bullet" : "decimal")\"/><w:lvlText w:val=\"\(id == 1 ? "•" : "%\(level + 1).")\"/><w:pPr><w:ind w:left=\"\((level + 1) * 360)\" w:hanging=\"180\"/></w:pPr></w:lvl>"
            }.joined()
            return "<w:abstractNum w:abstractNumId=\"\(id)\">\(levels)</w:abstractNum><w:num w:numId=\"\(id)\"><w:abstractNumId w:val=\"\(id)\"/></w:num>"
        }.joined()
        let files: [String: String] = [
            "[Content_Types].xml": contentTypes,
            "_rels/.rels": "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(relationNS)/officeDocument\" Target=\"word/document.xml\"/></Relationships>",
            "word/document.xml": "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document xmlns:w=\"\(wordNS)\" xmlns:r=\"\(relationNS)\"><w:body>\(body)</w:body></w:document>",
            "word/styles.xml": "<w:styles xmlns:w=\"\(wordNS)\">\(styles)</w:styles>",
            "word/numbering.xml": "<w:numbering xmlns:w=\"\(wordNS)\">\(numbering)</w:numbering>",
            "word/_rels/document.xml.rels": "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"styles\" Type=\"\(relationNS)/styles\" Target=\"styles.xml\"/><Relationship Id=\"numbering\" Type=\"\(relationNS)/numbering\" Target=\"numbering.xml\"/>\(rels)</Relationships>"
        ]
        return try ZipArchive.encode(files.mapValues { Data($0.utf8) })
    }
    public static func decode(_ data: Data) throws -> ImportResult {
        let files = try ZipArchive.decode(data)
        guard let content = files["word/document.xml"] else { throw DocumentError.invalid("DOCX has no main document part") }
        let delegate = WordReader()
        if let rels = files["word/_rels/document.xml.rels"] {
            let reader = RelationshipReader(); try parse(rels, delegate: reader); delegate.links = reader.links
        }
        if let styles = files["word/styles.xml"] {
            let reader = StyleReader(); try parse(styles, delegate: reader)
            for style in reader.styles { delegate.document.updateStyle(style) }
        }
        try parse(content, delegate: delegate)
        guard delegate.sawDocument else { throw DocumentError.invalid("missing Word document root") }
        if delegate.paragraphs.isEmpty { delegate.paragraphs = [Paragraph()] }
        delegate.document.sections[0].paragraphs = delegate.paragraphs
        for p in delegate.paragraphs where !delegate.document.styles.contains(where: { $0.id == p.styleID }) {
            delegate.document.updateStyle(ParagraphStyle(id: p.styleID, name: p.styleID))
        }
        if files.keys.contains(where: { $0.contains("comments") || $0.contains("footnotes") || $0.contains("endnotes") }) {
            delegate.warnings.insert("Comments and notes are not imported in this version.")
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
private class RelationshipReader: NSObject, XMLParserDelegate {
    var links: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if name == "Relationship", let id = a["Id"], let target = a["Target"], a["Type"]?.hasSuffix("/hyperlink") == true { links[id] = target }
    }
}
private class StyleReader: NSObject, XMLParserDelegate {
    var styles: [ParagraphStyle] = []; var current: ParagraphStyle?
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if name == "style", wordAttribute(a, "type") == "paragraph", let id = wordAttribute(a, "styleId") {
            current = ParagraphStyle(id: id, name: id)
        }
        guard current != nil else { return }
        if name == "name" { current?.name = wordAttribute(a) ?? current!.name }
        if name == "outlineLvl", let level = wordAttribute(a).flatMap(Int.init), level < 9 { current?.headingLevel = level + 1 }
        applyRun(name, a, &current!.text)
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "style", let style = current { styles.append(style); current = nil }
    }
}
private class WordReader: NSObject, XMLParserDelegate {
    var document = ScribeDocument(), paragraphs: [Paragraph] = [], warnings: Set<String> = []
    var paragraph: Paragraph?, run = TextRun(""), collecting = false, links: [String: String] = [:], link: String?
    var inRun = false, sawDocument = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        guard namespaceURI == DOCX.wordNS else { return }
        switch name {
        case "document": sawDocument = true
        case "p": paragraph = Paragraph(); paragraph?.runs = []
        case "r": run = TextRun("", link: link); inRun = true
        case "t": collecting = true
        case "tab": run.text += "\t"
        case "br":
            if wordAttribute(a, "type") == "page" { paragraph?.pageBreakBefore = true }
            else { run.text += "\u{2028}" }
        case "pStyle": paragraph?.styleID = wordAttribute(a) ?? "normal"
        case "pageBreakBefore": paragraph?.pageBreakBefore = flag(a)
        case "numPr": paragraph?.list = ListDescriptor(kind: .decimal); warnings.insert("List numbering is approximated; custom numbering definitions are not imported.")
        case "ilvl": paragraph?.list?.level = min(8, max(0, wordAttribute(a).flatMap(Int.init) ?? 0))
        case "numId": if wordAttribute(a) == "1" { paragraph?.list?.kind = .bullet }
        case "jc":
            if paragraph?.formatting == nil { paragraph?.formatting = ParagraphFormatting() }
            paragraph?.formatting?.alignment = wordAttribute(a) == "both" ? .justified : Alignment(rawValue: wordAttribute(a) ?? "left") ?? .left
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
        case "tbl": warnings.insert("Table cells are imported as sequential paragraphs; table geometry is not retained.")
        case "drawing", "pict": warnings.insert("Images and drawings are not imported in this version.")
        case "headerReference", "footerReference": warnings.insert("Headers and footers are not imported in this version.")
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
        case "r": paragraph?.runs.append(run); inRun = false
        case "p": if let p = paragraph { paragraphs.append(p) }; paragraph = nil
        case "hyperlink": link = nil
        default: break
        }
    }
}
