import Foundation
import DocumentCore

/// OPC parts and relationships are authored explicitly; Word fields remain real fields.
final class DOCXWriter {
    private var parts: [String: Data] = [:]
    private var relationships: [String] = []
    private var overrides: [String] = []
    private var nextID = 1
    private let document: ScribeDocument
    init(_ document: ScribeDocument) { self.document = document }
    private func put(_ path: String, _ xml: String) { parts[path] = Data(xml.utf8) }
    private func relationship(type: String, target: String, external: Bool = false) -> String {
        let id = "rId\(nextID)"; nextID += 1
        relationships.append("<Relationship Id=\"\(id)\" Type=\"\(DOCX.relationNS)/\(type)\" Target=\"\(DOCX.xml(target))\"\(external ? " TargetMode=\"External\"" : "")/>")
        return id
    }
    func encode() throws -> Data {
        try NativeFormat.validate(document)
        var body = ""
        for (index, section) in document.sections.enumerated() {
            var emitted: Set<UUID> = []
            for p in section.paragraphs {
                if let cell = p.tableCell, let definition = document.tables.first(where: { $0.id == cell.tableID }) {
                    if emitted.insert(cell.tableID).inserted { body += table(definition, paragraphs: section.paragraphs) }
                } else { body += paragraph(p) }
            }
            var sectionXML = DOCX.sectionProperties(section.page)
            var references = ""
            for isHeader in [true, false] {
                let text = isHeader ? section.header : section.footer
                let numbering = section.pageNumbering.flatMap { ([.topLeft, .topCenter, .topRight].contains($0.position) == isHeader) ? $0 : nil }
                guard !text.isEmpty || numbering != nil else { continue }
                let kind = isHeader ? "header" : "footer", root = isHeader ? "hdr" : "ftr"
                let path = "\(kind)\(index + 1).xml"
                var content = text.isEmpty ? "" : "<w:p><w:r><w:rPr><w:sz w:val=\"18\"/></w:rPr><w:t xml:space=\"preserve\">\(DOCX.xml(text))</w:t></w:r></w:p>"
                if let numbering {
                    let alignment = [.topCenter, .bottomCenter].contains(numbering.position) ? "center" : [.topRight, .bottomRight].contains(numbering.position) ? "right" : "left"
                    let page = "<w:fldSimple w:instr=\"PAGE\"><w:r><w:t>\(numbering.start)</w:t></w:r></w:fldSimple>"
                    var field = page
                    if numbering.format == .page || numbering.format == .pageOfTotal { field = "<w:r><w:t xml:space=\"preserve\">Page </w:t></w:r>" + field }
                    if numbering.format == .pageOfTotal { field += "<w:r><w:t xml:space=\"preserve\"> of </w:t></w:r><w:fldSimple w:instr=\"NUMPAGES\"><w:r><w:t>1</w:t></w:r></w:fldSimple>" }
                    content += "<w:p><w:pPr><w:jc w:val=\"\(alignment)\"/></w:pPr>\(field)</w:p>"
                }
                put("word/\(path)", "<w:\(root) xmlns:w=\"\(DOCX.wordNS)\">\(content)</w:\(root)>")
                let id = relationship(type: kind, target: path)
                references += "<w:\(kind)Reference w:type=\"default\" r:id=\"\(id)\"/>"
                overrides.append("<Override PartName=\"/word/\(path)\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.\(kind)+xml\"/>")
            }
            if let numbering = section.pageNumbering { sectionXML = sectionXML.replacingOccurrences(of: "</w:sectPr>", with: "<w:pgNumType w:fmt=\"\(numbering.format == .roman ? "lowerRoman" : "decimal")\" w:start=\"\(numbering.start)\"/></w:sectPr>") }
            sectionXML = sectionXML.replacingOccurrences(of: "<w:sectPr>", with: "<w:sectPr>" + references)
            body += index == document.sections.count - 1 ? sectionXML : "<w:p><w:pPr>\(sectionXML)</w:pPr></w:p>"
        }
        let namespaces = "xmlns:w=\"\(DOCX.wordNS)\" xmlns:r=\"\(DOCX.relationNS)\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\""
        put("word/document.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document \(namespaces)><w:body>\(body)</w:body></w:document>")
        let styles = document.styles.map { s in
            "<w:style w:type=\"paragraph\" w:styleId=\"\(DOCX.xml(s.id))\"\(s.id == "normal" ? " w:default=\"1\"" : "")><w:name w:val=\"\(DOCX.xml(s.name))\"/><w:pPr>\(DOCX.paragraphProperties(s.paragraph))\(s.headingLevel.map { "<w:outlineLvl w:val=\"\($0 - 1)\"/>" } ?? "")</w:pPr><w:rPr>\(DOCX.runProperties(s.text))</w:rPr></w:style>"
        }.joined()
        put("word/styles.xml", "<w:styles xmlns:w=\"\(DOCX.wordNS)\">\(styles)</w:styles>")
        _ = relationship(type: "styles", target: "styles.xml")
        let formats = ["bullet", "decimal", "lowerLetter", "lowerRoman"]
        let numbering = formats.enumerated().map { index, format in
            let id = index + 1
            let levels = (0...8).map { level in "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"\(format)\"/><w:lvlText w:val=\"\(index == 0 ? "•" : "%\(level + 1).")\"/><w:pPr><w:ind w:left=\"\((level + 1) * 480)\" w:hanging=\"240\"/></w:pPr></w:lvl>" }.joined()
            return "<w:abstractNum w:abstractNumId=\"\(id)\">\(levels)</w:abstractNum><w:num w:numId=\"\(id)\"><w:abstractNumId w:val=\"\(id)\"/></w:num>"
        }.joined()
        put("word/numbering.xml", "<w:numbering xmlns:w=\"\(DOCX.wordNS)\">\(numbering)</w:numbering>")
        _ = relationship(type: "numbering", target: "numbering.xml")
        put("word/settings.xml", "<w:settings xmlns:w=\"\(DOCX.wordNS)\"><w:updateFields w:val=\"true\"/></w:settings>")
        _ = relationship(type: "settings", target: "settings.xml")
        put("word/_rels/document.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relationships.joined())</Relationships>")
        put("_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"document\" Type=\"\(DOCX.relationNS)/officeDocument\" Target=\"word/document.xml\"/></Relationships>")
        let images = [("png", "image/png"), ("jpg", "image/jpeg"), ("jpeg", "image/jpeg"), ("tiff", "image/tiff"), ("heic", "image/heic")].map { "<Default Extension=\"\($0.0)\" ContentType=\"\($0.1)\"/>" }.joined()
        let standard = [("document", "document.main"), ("styles", "styles"), ("numbering", "numbering"), ("settings", "settings")].map { "<Override PartName=\"/word/\($0.0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.\($0.1)+xml\"/>" }.joined()
        put("[Content_Types].xml", "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>\(images)\(standard)\(overrides.joined())</Types>")
        return try ZipArchive.encode(parts)
    }
    private func paragraph(_ p: Paragraph) -> String {
        var properties = "<w:pStyle w:val=\"\(DOCX.xml(p.styleID))\"/>"
        if p.pageBreakBefore { properties += "<w:pageBreakBefore/>" }
        if let f = p.formatting { properties += DOCX.paragraphProperties(f) }
        if let list = p.list {
            let id: Int
            switch list.kind { case .bullet: id = 1; case .decimal: id = 2; case .lowerAlpha: id = 3; case .lowerRoman: id = 4 }
            properties += "<w:numPr><w:ilvl w:val=\"\(list.level)\"/><w:numId w:val=\"\(id)\"/></w:numPr>"
        }
        let runs = p.runs.map { run -> String in
            if let image = run.image { return imageRun(image) }
            let text = DOCX.xml(run.text).replacingOccurrences(of: "\t", with: "</w:t><w:tab/><w:t xml:space=\"preserve\">").replacingOccurrences(of: "\u{2028}", with: "</w:t><w:br/><w:t xml:space=\"preserve\">")
            let content = "<w:r><w:rPr>\(DOCX.runProperties(run.format))</w:rPr><w:t xml:space=\"preserve\">\(text)</w:t></w:r>"
            guard let link = run.link else { return content }
            return "<w:hyperlink r:id=\"\(relationship(type: "hyperlink", target: link, external: true))\">\(content)</w:hyperlink>"
        }.joined()
        return "<w:p><w:pPr>\(properties)</w:pPr>\(runs)</w:p>"
    }
    private func table(_ table: DocumentTable, paragraphs: [Paragraph]) -> String {
        let borders = ["top", "left", "bottom", "right", "insideH", "insideV"].map { "<w:\($0) w:val=\"single\" w:sz=\"\(Int(table.borderWidth * 8))\" w:color=\"\(table.borderColor.dropFirst())\"/>" }.joined()
        let grid = table.columnWidths.map { "<w:gridCol w:w=\"\(Int($0 * 20))\"/>" }.joined()
        let margins = ["top", "left", "bottom", "right"].map { "<w:\($0) w:w=\"\(Int(table.padding * 20))\" w:type=\"dxa\"/>" }.joined()
        let cellsByPosition = Dictionary(grouping: paragraphs.filter { $0.tableCell?.tableID == table.id }) { p in
            p.tableCell!.row * table.columnWidths.count + p.tableCell!.column
        }
        var rows = ""
        for row in 0..<table.rows {
            var cells = ""
            for column in table.columnWidths.indices {
                let content = (cellsByPosition[row * table.columnWidths.count + column] ?? []).map(paragraph).joined()
                let shade = row == 0 && table.firstRowIsHeader ? "<w:shd w:fill=\"\(table.headerBackground.dropFirst())\"/>" : ""
                cells += "<w:tc><w:tcPr><w:tcW w:w=\"\(Int(table.columnWidths[column] * 20))\" w:type=\"dxa\"/>\(shade)</w:tcPr>\(content.isEmpty ? "<w:p/>" : content)</w:tc>"
            }
            rows += "<w:tr>\(row == 0 && table.firstRowIsHeader ? "<w:trPr><w:tblHeader/></w:trPr>" : "")\(cells)</w:tr>"
        }
        return "<w:tbl><w:tblPr><w:tblW w:w=\"\(Int(table.columnWidths.reduce(0, +) * 20))\" w:type=\"dxa\"/><w:tblLayout w:type=\"fixed\"/><w:tblBorders>\(borders)</w:tblBorders><w:tblCellMar>\(margins)</w:tblCellMar></w:tblPr><w:tblGrid>\(grid)</w:tblGrid>\(rows)</w:tbl>"
    }
    private func imageRun(_ image: InlineImage) -> String {
        let name = "media/\(image.id).\(image.fileExtension)"
        parts["word/" + name] = image.data
        let id = relationship(type: "image", target: name)
        let cx = Int(image.width * 12700), cy = Int(image.height * 12700), drawingID = nextID
        return "<w:r><w:drawing><wp:inline><wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/><wp:docPr id=\"\(drawingID)\" name=\"Image \(drawingID)\" descr=\"\(DOCX.xml(image.altText))\"/><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic><pic:nvPicPr><pic:cNvPr id=\"0\" name=\"\(image.id)\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"\(id)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>"
    }
}
