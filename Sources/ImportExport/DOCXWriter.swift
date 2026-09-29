import Foundation
import DocumentCore

/// OPC parts and relationships are authored explicitly; Word fields remain real fields.
final class DOCXWriter {
    private var parts: [String: Data] = [:]
    private var relationships: [String] = []
    private var overrides: [String] = []
    private var nextID = 1
    private let document: ScribeDocument
    private let numbering: DOCXNumberingWriter
    private let comments: DOCXCommentsWriter
    private let contents: DOCXTableOfContents
    private var contentWidth = 451.276
    private var bookmarkIDs: [UUID: Int] = [:]
    private var namedBookmarks: DOCXBookmarks?
    init(_ document: ScribeDocument) { self.document = document; numbering = DOCXNumberingWriter(paragraphs: document.paragraphs); comments = DOCXCommentsWriter(document: document); contents = DOCXTableOfContents(document: document) }
    private func put(_ path: String, _ xml: String) { parts[path] = Data(xml.utf8) }
    private func relationship(type: String, target: String, external: Bool = false, namespace: String = DOCX.relationNS) -> String {
        let id = "rId\(nextID)"; nextID += 1
        relationships.append("<Relationship Id=\"\(id)\" Type=\"\(namespace)/\(type)\" Target=\"\(DOCX.xml(target))\"\(external ? " TargetMode=\"External\"" : "")/>")
        return id
    }
    func encode() throws -> Data {
        try NativeFormat.validate(document)
        let linked = Set(document.paragraphs.flatMap(\.runs).compactMap { $0.link.flatMap(DocumentLink.paragraphID) })
        for paragraph in document.paragraphs where linked.contains(paragraph.id) { bookmarkIDs[paragraph.id] = bookmarkIDs.count }
        namedBookmarks = DOCXBookmarks(document, startingID: bookmarkIDs.count, reservedNames: Set(bookmarkIDs.keys.map(DocumentLink.officeBookmark)))
        var body = ""
        let usesEvenPages = document.sections.contains { $0.runningContent?.differentOddEvenPages == true }
        for (index, section) in document.sections.enumerated() {
            contentWidth = section.page.contentWidth
            var emitted: Set<UUID> = []
            for p in section.paragraphs {
                if let cell = p.tableCell, let definition = document.tables.first(where: { $0.id == cell.tableID }) {
                    if emitted.insert(cell.tableID).inserted { body += table(definition, paragraphs: section.paragraphs) }
                } else { body += paragraph(p) }
            }
            var sectionXML = DOCX.sectionProperties(section.page)
            var references = ""
            for part in DOCXRunningContent.parts(section: section, index: index, documentUsesEvenPages: usesEvenPages) {
                put("word/" + part.path, part.xml)
                let id = relationship(type: part.kind, target: part.path)
                references += "<w:\(part.kind)Reference w:type=\"\(part.variant)\" r:id=\"\(id)\"/>"
                overrides.append("<Override PartName=\"/word/\(part.path)\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.\(part.kind)+xml\"/>")
            }
            if let numbering = section.pageNumbering { sectionXML = sectionXML.replacingOccurrences(of: "</w:sectPr>", with: "<w:pgNumType w:fmt=\"\(numbering.format == .roman ? "lowerRoman" : "decimal")\" w:start=\"\(numbering.start)\"/></w:sectPr>") }
            if section.pageNumbering == nil, let start = section.runningContent?.startingPageNumber {
                sectionXML = sectionXML.replacingOccurrences(of: "</w:sectPr>", with: "<w:pgNumType w:start=\"\(start)\"/></w:sectPr>")
            }
            if section.runningContent?.differentFirstPage == true { sectionXML = sectionXML.replacingOccurrences(of: "</w:sectPr>", with: "<w:titlePg/></w:sectPr>") }
            sectionXML = sectionXML.replacingOccurrences(of: "<w:sectPr>", with: "<w:sectPr>" + references)
            body += index == document.sections.count - 1 ? sectionXML : "<w:p><w:pPr>\(sectionXML)</w:pPr></w:p>"
        }
        let namespaces = "xmlns:w=\"\(DOCX.wordNS)\" xmlns:r=\"\(DOCX.relationNS)\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\""
        put("word/document.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document \(namespaces)><w:body>\(body)</w:body></w:document>")
        let styles = document.styles.map { s in
            "<w:style w:type=\"paragraph\" w:styleId=\"\(DOCX.xml(s.id))\"\(s.id == "normal" ? " w:default=\"1\"" : "")><w:name w:val=\"\(DOCX.xml(s.name))\"/><w:pPr>\(DOCX.paragraphProperties(s.paragraph))\(s.headingLevel.map { "<w:outlineLvl w:val=\"\($0 - 1)\"/>" } ?? "")</w:pPr><w:rPr>\(DOCX.runProperties(s.text))</w:rPr></w:style>"
        }.joined()
        let language = try DocumentMetadata.languageIdentifier(document.language)
        let defaults = language == "und" ? "" : "<w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val=\"\(DOCX.xml(language))\"/></w:rPr></w:rPrDefault></w:docDefaults>"
        put("word/styles.xml", "<w:styles xmlns:w=\"\(DOCX.wordNS)\">\(defaults)\(styles)</w:styles>")
        _ = relationship(type: "styles", target: "styles.xml")
        put("word/numbering.xml", numbering.xml)
        _ = relationship(type: "numbering", target: "numbering.xml")
        if !document.comments.isEmpty {
            put("word/comments.xml", comments.xml)
            _ = relationship(type: "comments", target: "comments.xml")
            put("word/commentsExtended.xml", comments.extendedXML)
            _ = relationship(type: "commentsExtended", target: "commentsExtended.xml", namespace: "http://schemas.microsoft.com/office/2011/relationships")
            overrides.append("<Override PartName=\"/word/commentsExtended.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.commentsExtended+xml\"/>")
            overrides.append("<Override PartName=\"/word/comments.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml\"/>")
        }
        put("word/settings.xml", "<w:settings xmlns:w=\"\(DOCX.wordNS)\">\(usesEvenPages ? "<w:evenAndOddHeaders/>" : "")<w:updateFields w:val=\"true\"/></w:settings>")
        _ = relationship(type: "settings", target: "settings.xml")
        put("word/_rels/document.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relationships.joined())</Relationships>")
        put("docProps/core.xml", try DOCXMetadata.xml(document))
        overrides.append("<Override PartName=\"/docProps/core.xml\" ContentType=\"\(DOCXMetadata.contentType)\"/>")
        put("_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"document\" Type=\"\(DOCX.relationNS)/officeDocument\" Target=\"word/document.xml\"/><Relationship Id=\"properties\" Type=\"\(DOCXMetadata.relationship)\" Target=\"docProps/core.xml\"/></Relationships>")
        let images = [("png", "image/png"), ("jpg", "image/jpeg"), ("jpeg", "image/jpeg"), ("tiff", "image/tiff"), ("heic", "image/heic")].map { "<Default Extension=\"\($0.0)\" ContentType=\"\($0.1)\"/>" }.joined()
        let standard = [("document", "document.main"), ("styles", "styles"), ("numbering", "numbering"), ("settings", "settings")].map { "<Override PartName=\"/word/\($0.0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.\($0.1)+xml\"/>" }.joined()
        put("[Content_Types].xml", "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>\(images)\(standard)\(overrides.joined())</Types>")
        return try ZipArchive.encode(parts)
    }
    private func paragraph(_ p: Paragraph) -> String {
        var properties = "<w:pStyle w:val=\"\(DOCX.xml(p.styleID))\"/>"
        if p.pageBreakBefore { properties += "<w:pageBreakBefore/>" }
        if let list = p.list {
            let id = numbering.paragraphIDs[p.id]!
            properties += "<w:numPr><w:ilvl w:val=\"\(list.level)\"/><w:numId w:val=\"\(id)\"/></w:numPr>"
        }
        if let toc = p.toc, toc.kind == .entry {
            var formatting = p.formatting ?? document.style(for: p).paragraph
            formatting.headIndent = Double(max(0, (toc.level ?? 1) - 1)) * 14; formatting.firstLineIndent = formatting.headIndent
            properties += "<w:tabs><w:tab w:val=\"right\" w:pos=\"\(Int((contentWidth - formatting.tailIndent) * 20))\"/></w:tabs>"
            properties += DOCX.paragraphProperties(formatting)
        } else if let f = p.formatting { properties += DOCX.paragraphProperties(f) }
        var text = "", offset = 0
        let boundaries = comments.boundaries(paragraphID: p.id)
        for run in p.runs {
            let length = (run.text as NSString).length
            let cuts = [offset] + boundaries.filter { $0 > offset && $0 < offset + length } + [offset + length]
            for (start, end) in zip(cuts, cuts.dropFirst()) where end > start {
                text += comments.markers(paragraphID: p.id, offset: start)
                var fragment = run; fragment.text = (run.text as NSString).substring(with: NSRange(location: start - offset, length: end - start))
                text += runXML(fragment)
            }
            offset += length
        }
        text += comments.markers(paragraphID: p.id, offset: offset)
        let bookmark = bookmarkIDs[p.id].map { "<w:bookmarkStart w:id=\"\($0)\" w:name=\"\(DocumentLink.officeBookmark(p.id))\"/><w:bookmarkEnd w:id=\"\($0)\"/>" } ?? ""
        return "<w:p><w:pPr>\(properties)</w:pPr>\(bookmark)\(namedBookmarks?.markers(at: p.id) ?? "")\(contents.start(p.id))\(text)\(contents.end(p.id))</w:p>"
    }
    private func runXML(_ run: TextRun) -> String {
            if let image = run.image { return imageRun(image) }
            let text = DOCX.xml(run.text).replacingOccurrences(of: "\t", with: "</w:t><w:tab/><w:t xml:space=\"preserve\">").replacingOccurrences(of: "\u{2028}", with: "</w:t><w:br/><w:t xml:space=\"preserve\">")
            let pageText = text.replacingOccurrences(of: "\u{c}", with: "</w:t><w:br w:type=\"page\"/><w:t xml:space=\"preserve\">")
            let content = "<w:r><w:rPr>\(DOCX.runProperties(run.format))</w:rPr><w:t xml:space=\"preserve\">\(pageText)</w:t></w:r>"
            guard let link = run.link else { return content }
            if let id = DocumentLink.paragraphID(link) {
                guard bookmarkIDs[id] != nil else { return content }
                return "<w:hyperlink w:anchor=\"\(DocumentLink.officeBookmark(id))\">\(content)</w:hyperlink>"
            }
            if let id = DocumentLink.bookmarkID(link) {
                guard let name = namedBookmarks?.name(for: id) else { return content }
                return "<w:hyperlink w:anchor=\"\(DOCX.xml(name))\">\(content)</w:hyperlink>"
            }
            return "<w:hyperlink r:id=\"\(relationship(type: "hyperlink", target: link, external: true))\">\(content)</w:hyperlink>"
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
                let merge = table.merge(atRow: row, column: column)
                if let merge, column != merge.column { continue }
                let continuation = merge.map { row != $0.row } ?? false
                let content = continuation ? "" : (cellsByPosition[row * table.columnWidths.count + column] ?? []).map(paragraph).joined()
                let span = merge?.columnSpan ?? 1
                let width = table.columnWidths[column..<(column + span)].reduce(0, +)
                let gridSpan = span > 1 ? "<w:gridSpan w:val=\"\(span)\"/>" : ""
                let vertical = (merge?.rowSpan ?? 1) > 1 ? "<w:vMerge w:val=\"\(continuation ? "continue" : "restart")\"/>" : ""
                let shade = DOCX.cellProperties(table, row: row, column: column)
                cells += "<w:tc><w:tcPr><w:tcW w:w=\"\(Int(width * 20))\" w:type=\"dxa\"/>\(gridSpan)\(vertical)\(shade)</w:tcPr>\(content.isEmpty ? "<w:p/>" : content)</w:tc>"
            }
            rows += "<w:tr>\(DOCX.rowProperties(table, row: row))\(cells)</w:tr>"
        }
        return "<w:tbl><w:tblPr><w:tblW w:w=\"\(Int(table.columnWidths.reduce(0, +) * 20))\" w:type=\"dxa\"/><w:tblBorders>\(borders)</w:tblBorders><w:tblLayout w:type=\"fixed\"/><w:tblCellMar>\(margins)</w:tblCellMar></w:tblPr><w:tblGrid>\(grid)</w:tblGrid>\(rows)</w:tbl>"
    }
    private func imageRun(_ image: InlineImage) -> String {
        // Separate parts also preserve pasted objects that share a semantic ID
        // but contain different source bytes.
        let name = "media/\(image.id)-\(nextID).\(image.fileExtension)"
        parts["word/" + name] = image.data
        let id = relationship(type: "image", target: name)
        let geometry = DOCXImageAdjustments.geometry(image), drawingID = nextID
        let cx = geometry.width, cy = geometry.height
        return "<w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/>\(geometry.effects)<wp:docPr id=\"\(drawingID)\" name=\"Image \(drawingID)\" descr=\"\(DOCX.xml(image.altText))\"/><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic><pic:nvPicPr><pic:cNvPr id=\"0\" name=\"\(image.id)\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"\(id)\">\(geometry.opacity)</a:blip>\(geometry.crop)<a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm\(geometry.rotation)><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>"
    }
}
