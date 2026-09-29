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
        guard !document.hasPendingRevisions else { throw DocumentError.invalid("tracked-change DOCX export is still being implemented") }
        return try DOCXWriter(document).encode()
    }
    public static func decode(_ data: Data) throws -> ImportResult {
        let files = try ZipArchive.decode(data)
        guard let content = files["word/document.xml"] else { throw DocumentError.invalid("DOCX has no main document part") }
        let delegate = WordReader(); delegate.files = files
        delegate.document.title = "" // The importing application can suggest the source filename.
        delegate.document.language = "und"
        var metadataPath = "docProps/core.xml"
        if let rootRelationships = files["_rels/.rels"] {
            let reader = RelationshipReader(); try parse(rootRelationships, delegate: reader)
            metadataPath = reader.partTargets[DOCXMetadata.relationship] ?? metadataPath
        }
        if let metadata = files[metadataPath] {
            let reader = DOCXMetadataReader(); try parse(metadata, delegate: reader)
            if let title = reader.title, !title.isEmpty { delegate.document.title = title }
            if let author = reader.author { delegate.document.author = author }
            if let language = reader.language, let normalized = try? DocumentMetadata.languageIdentifier(language) { delegate.document.language = normalized }
        }
        var partTargets: [String: String] = [:]
        if let rels = files["word/_rels/document.xml.rels"] {
            let reader = RelationshipReader(); try parse(rels, delegate: reader); delegate.links = reader.links; delegate.targets = reader.targets; partTargets = reader.partTargets
        }
        func part(_ name: String, namespace: String = DOCX.relationNS) -> Data? { files["word/" + (partTargets[namespace + "/" + name] ?? name + ".xml")] }
        if let styles = part("styles") {
            let reader = StyleReader(); try parse(styles, delegate: reader)
            for style in reader.styles { delegate.document.updateStyle(style) }
            delegate.styleLists = reader.resolvedLists
            if let language = reader.defaultLanguage, let normalized = try? DocumentMetadata.languageIdentifier(language) { delegate.document.language = normalized }
            if reader.styleLanguages.contains(where: { (try? DocumentMetadata.languageIdentifier($0)) != delegate.document.language }) {
                delegate.warnings.insert("Style-specific spelling languages are flattened to the document language.")
            }
        }
        if let numbering = part("numbering") { try parse(numbering, delegate: delegate.numbering) }
        var noteCatalog: [UUID: DocumentNote] = [:]
        for kind in DocumentNote.Kind.allCases {
            let root = kind.rawValue + "s"
            guard let data = part(root) else { continue }
            let path = partTargets[DOCX.relationNS + "/" + root] ?? root + ".xml"
            let components = path.split(separator: "/").map(String.init)
            let noteRelationships = RelationshipReader(baseDirectory: Array(components.dropLast()))
            let relPath = "word/" + (components.dropLast() + ["_rels", components.last! + ".rels"]).joined(separator: "/")
            if let relations = files[relPath] { try parse(relations, delegate: noteRelationships) }
            let notesReader = DOCXNotesReader(kind: kind) {
                let reader = WordReader(); reader.files = files
                reader.document.styles = delegate.document.styles
                reader.document.language = delegate.document.language
                reader.styleLists = delegate.styleLists; reader.numbering = delegate.numbering
                reader.targets = noteRelationships.targets; reader.links = noteRelationships.links
                return reader
            }
            try parse(data, delegate: notesReader)
            delegate.warnings.formUnion(notesReader.warnings)
            for (id, note) in notesReader.notes {
                noteCatalog[note.id] = note; delegate.noteIDs[kind.rawValue + ":" + id] = note.id
            }
        }
        try parse(content, delegate: delegate)
        let referencedNotes = delegate.paragraphs.flatMap(\.runs).compactMap(\.noteID)
        guard Set(referencedNotes).count == referencedNotes.count else { throw DocumentError.invalid("a DOCX note has more than one body reference") }
        delegate.document.notes = referencedNotes.compactMap { noteCatalog[$0] }
        if noteCatalog.count > referencedNotes.count { delegate.warnings.insert("Unreferenced note definitions are not included in the imported document.") }
        delegate.warnings.formUnion(delegate.numbering.warnings)
        guard delegate.sawDocument else { throw DocumentError.invalid("missing Word document root") }
        if delegate.paragraphs.isEmpty { delegate.paragraphs = [Paragraph()] }
        var namedBookmarks: [String: Bookmark] = [:]
        for name in delegate.bookmarkOrder {
            guard let paragraphID = delegate.bookmarkParagraphs[name], !name.hasPrefix("_"),
                  !(name.hasPrefix("Scribe_") && name.count == 39 && name.dropFirst(7).allSatisfy({ $0.isHexDigit })) else { continue }
            let bookmark = Bookmark(name: name, anchor: TextAnchor(paragraphID: paragraphID, offset: 0, length: 0))
            namedBookmarks[name] = bookmark; delegate.document.bookmarks.append(bookmark)
        }
        for p in delegate.paragraphs.indices {
            for r in delegate.paragraphs[p].runs.indices {
                guard let link = delegate.paragraphs[p].runs[r].link, link.hasPrefix("#") else { continue }
                if let target = delegate.bookmarkParagraphs[String(link.dropFirst())] {
                    if let bookmark = namedBookmarks[String(link.dropFirst())] { delegate.paragraphs[p].runs[r].link = DocumentLink.bookmark(bookmark.id) }
                    else { delegate.paragraphs[p].runs[r].link = DocumentLink.paragraph(target) }
                } else {
                    delegate.paragraphs[p].runs[r].link = nil
                    delegate.warnings.insert("An internal hyperlink has a missing bookmark destination; its text was retained.")
                }
            }
        }
        delegate.document.sections[0].paragraphs = delegate.paragraphs
        for p in delegate.paragraphs + delegate.document.notes.flatMap(\.paragraphs) where !delegate.document.styles.contains(where: { $0.id == p.styleID }) {
            delegate.document.updateStyle(ParagraphStyle(id: p.styleID, name: p.styleID))
        }
        let resolutions = DOCXCommentResolutionReader()
        if let data = part("commentsExtended", namespace: "http://schemas.microsoft.com/office/2011/relationships") { try parse(data, delegate: resolutions) }
        if resolutions.hasReplies { delegate.warnings.insert("Comment replies are imported as separate comments; thread hierarchy is not retained.") }
        if let data = part("comments") {
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
                comment.resolved = value.paragraphID.flatMap { resolutions.resolved[$0] } ?? false
                if detached { comment.isDetached = true }
                delegate.document.comments.append(comment)
            }
        }
        if files.keys.contains(where: { $0.contains("commentsExtensible") }) {
            delegate.warnings.insert("Newer comment identity and collaboration metadata are not imported.")
        }
        if !delegate.document.notes.isEmpty {
            let settings = DOCXNoteSettingsReader()
            try parse(content, delegate: settings)
            if let data = part("settings") { try parse(data, delegate: settings) }
            delegate.warnings.formUnion(settings.warnings)
            for note in delegate.document.notes.indices {
                for paragraph in delegate.document.notes[note].paragraphs.indices {
                    for run in delegate.document.notes[note].paragraphs[paragraph].runs.indices {
                        guard let link = delegate.document.notes[note].paragraphs[paragraph].runs[run].link, link.hasPrefix("#") else { continue }
                        let name = String(link.dropFirst())
                        if let bookmark = namedBookmarks[name] {
                            delegate.document.notes[note].paragraphs[paragraph].runs[run].link = DocumentLink.bookmark(bookmark.id)
                        } else if let id = delegate.bookmarkParagraphs[name] {
                            delegate.document.notes[note].paragraphs[paragraph].runs[run].link = DocumentLink.paragraph(id)
                        } else {
                            delegate.document.notes[note].paragraphs[paragraph].runs[run].link = nil
                            delegate.warnings.insert("A note hyperlink has a missing bookmark destination; its text was retained.")
                        }
                    }
                }
            }
        }
        let runningSettings = DOCXRunningContentSettingsReader()
        if let settings = part("settings") { try parse(settings, delegate: runningSettings) }
        var variants = RunningContentVariants()
        variants.startingPageNumber = delegate.runningNumberStart
        variants.differentFirstPage = delegate.differentFirstPage
        variants.differentOddEvenPages = runningSettings.differentOddEvenPages
        for isHeader in [true, false] {
            let references = isHeader ? delegate.headerIDs : delegate.footerIDs
            for (variant, id) in references {
                guard ["default", "first", "even"].contains(variant), let target = delegate.targets[id], let data = files["word/" + target] else { continue }
                let reader = WordReader(); try parse(data, delegate: reader)
                delegate.warnings.formUnion(reader.warnings)
                if !reader.paragraphs.isEmpty {
                    delegate.warnings.insert("Headers and footers are imported as plain text; rich formatting and embedded objects are not retained.")
                }
                let text = reader.paragraphs.map(\.text).joined(separator: " ")
                switch (variant, isHeader) {
                case ("default", true): delegate.document.sections[0].header = text
                case ("default", false): delegate.document.sections[0].footer = text
                case ("first", true): variants.firstHeader = text
                case ("first", false): variants.firstFooter = text
                case ("even", true): variants.evenHeader = text
                case ("even", false): variants.evenFooter = text
                default: break
                }
                if String(data: data, encoding: .utf8)?.contains("fld") == true { delegate.warnings.insert("Running-content fields are imported as their cached text; update page numbering in Scribe if needed.") }
            }
        }
        if variants.differentOddEvenPages, let start = variants.startingPageNumber, start.isMultiple(of: 2) {
            delegate.warnings.insert("Odd/even running text uses the displayed page number in Scribe. With this even starting number, editors that use physical page order may display different variants.")
        }
        if variants != RunningContentVariants() { delegate.document.sections[0].runningContent = variants }
        // Validate bounds and merge references before constructing the full grid.
        try NativeFormat.validate(delegate.document)
        for table in delegate.document.tables { delegate.document.normalizeTableFlow(tableID: table.id) }
        delegate.document.reconcileCommentAnchors()
        try NativeFormat.validate(delegate.document)
        return ImportResult(document: delegate.document, warnings: delegate.warnings.sorted())
    }
    static func parse(_ data: Data, delegate: XMLParserDelegate) throws {
        guard let xml = String(data: data, encoding: .utf8), !xml.localizedCaseInsensitiveContains("<!DOCTYPE") else { throw DocumentError.invalid("unsupported XML encoding or document type declaration") }
        let parser = XMLParser(data: data); parser.shouldProcessNamespaces = true
        let normalizer = OfficeXMLDelegate(receiver: delegate)
        parser.shouldResolveExternalEntities = false; parser.shouldReportNamespacePrefixes = true; parser.delegate = normalizer
        let parsed = withExtendedLifetime(normalizer) { parser.parse() }
        guard parsed, parser.parserError == nil else { throw DocumentError.invalid("malformed Office XML") }
    }
    static func xml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    static func runProperties(_ f: TextFormatting) -> String {
        var s = ""
        if let family = f.fontFamily { s += "<w:rFonts w:ascii=\"\(xml(family))\" w:hAnsi=\"\(xml(family))\"/>" }
        if let b = f.bold { s += "<w:b w:val=\"\(b ? 1 : 0)\"/>" }
        if let i = f.italic { s += "<w:i w:val=\"\(i ? 1 : 0)\"/>" }
        if let strike = f.strikethrough { s += "<w:strike w:val=\"\(strike ? 1 : 0)\"/>" }
        if let color = f.foreground { s += "<w:color w:val=\"\(xml(color.replacingOccurrences(of: "#", with: "")))\"/>" }
        if let size = f.fontSize { s += "<w:sz w:val=\"\(Int(size * 2))\"/>" }
        if let u = f.underline { s += "<w:u w:val=\"\(u ? "single" : "none")\"/>" }
        if f.clearHighlight == true { s += "<w:shd w:val=\"nil\" w:fill=\"auto\"/>" }
        else if let color = f.highlight { s += "<w:shd w:val=\"clear\" w:fill=\"\(xml(color.replacingOccurrences(of: "#", with: "")))\"/>" }
        if let baseline = f.baseline { s += "<w:vertAlign w:val=\"\(baseline > 0 ? "superscript" : baseline < 0 ? "subscript" : "baseline")\"/>" }
        return s
    }
    static func paragraphProperties(_ f: ParagraphFormatting) -> String {
        "<w:spacing w:before=\"\(Int(f.spaceBefore * 20))\" w:after=\"\(Int(f.spaceAfter * 20))\"/><w:ind w:left=\"\(Int(f.headIndent * 20))\" w:right=\"\(Int(f.tailIndent * 20))\" \(f.firstLineIndent >= f.headIndent ? "w:firstLine" : "w:hanging")=\"\(Int(abs(f.firstLineIndent - f.headIndent) * 20))\"/><w:jc w:val=\"\(f.alignment == .justified ? "both" : f.alignment.rawValue)\"/>"
    }
    static func sectionProperties(_ p: PageSettings) -> String {
        "<w:sectPr><w:pgSz w:w=\"\(Int(p.width * 20))\" w:h=\"\(Int(p.height * 20))\"/><w:pgMar w:top=\"\(Int(p.top * 20))\" w:bottom=\"\(Int(p.bottom * 20))\" w:left=\"\(Int(p.left * 20))\" w:right=\"\(Int(p.right * 20))\"/></w:sectPr>"
    }
}

func wordAttribute(_ a: [String: String], _ key: String = "val") -> String? { a["w:\(key)"] ?? a[key] }
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
    case "shd":
        if wordAttribute(a) == "nil" || wordAttribute(a, "fill") == "auto" { f.highlight = nil; f.clearHighlight = true }
        else if let c = wordAttribute(a, "fill") { f.highlight = "#" + c; f.clearHighlight = nil }
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
class RelationshipReader: NSObject, XMLParserDelegate {
    private let baseDirectory: [String]?
    init(baseDirectory: [String]? = nil) { self.baseDirectory = baseDirectory }
    private func internalTarget(_ target: String) -> String? {
        guard !target.hasPrefix("/"), !target.contains("\\"), !target.contains(":") else { return nil }
        guard var path = baseDirectory else {
            return target.split(separator: "/").contains("..") ? nil : target
        }
        for component in target.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                guard !path.isEmpty else { return nil }; path.removeLast()
            } else { path.append(String(component)) }
        }
        return path.isEmpty ? nil : path.joined(separator: "/")
    }
    var links: [String: String] = [:], targets: [String: String] = [:], partTargets: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if name == "Relationship", let id = a["Id"], let target = a["Target"] {
            if a["Type"]?.hasSuffix("/hyperlink") == true { links[id] = target }
            else if a["TargetMode"] != "External", let resolved = internalTarget(target) {
                targets[id] = resolved
                if let type = a["Type"] { partTargets[type] = resolved }
            }
        }
    }
}
struct StyleList {
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
    var defaultLanguage: String?
    var styleLanguages = Set<String>()
    private var inDefaults = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if name == "docDefaults" { inDefaults = true }
        if inDefaults, name == "lang" { defaultLanguage = wordAttribute(a) }
        if name == "style", wordAttribute(a, "type") == "paragraph", let id = wordAttribute(a, "styleId") {
            current = ParagraphStyle(id: id, name: id)
        }
        guard current != nil else { return }
        if name == "lang", let language = wordAttribute(a) { styleLanguages.insert(language) }
        if name == "basedOn" { parents[current!.id] = wordAttribute(a) }
        if name == "numId" { var list = lists[current!.id] ?? StyleList(); list.id = wordAttribute(a); lists[current!.id] = list }
        if name == "ilvl" { var list = lists[current!.id] ?? StyleList(); list.level = wordAttribute(a).flatMap(Int.init); lists[current!.id] = list }
        if name == "name" { current?.name = wordAttribute(a) ?? current!.name }
        if name == "outlineLvl", let level = wordAttribute(a).flatMap(Int.init), level < 9 { current?.headingLevel = level + 1 }
        applyRun(name, a, &current!.text)
        applyParagraph(name, a, &current!.paragraph)
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "docDefaults" { inDefaults = false }
        if name == "style", let style = current { styles.append(style); current = nil }
    }
}
class WordReader: NSObject, XMLParserDelegate {
    var document = ScribeDocument(), paragraphs: [Paragraph] = [], warnings: Set<String> = []
    var paragraph: Paragraph?, run = TextRun(""), collecting = false, links: [String: String] = [:], link: String?
    var numbering = DOCXNumberingReader()
    var noteIDs: [String: UUID] = [:]
    var commentStarts: [String: TextAnchor] = [:], commentEnds: [String: TextAnchor] = [:], commentReferences: [String: TextAnchor] = [:]
    var styleLists: [String: StyleList] = [:]
    var bookmarkParagraphs: [String: UUID] = [:]
    var bookmarkOrder: [String] = []
    var listID: String?, listLevel: Int?
    var inRun = false, sawDocument = false
    var collectingInstruction = false, instruction = ""
    private var fieldInstructions: [String] = []
    private var skippedReviewDepth = 0
    private let reviewImportWarning = "Tracked changes are imported without review history. Deleted run content is omitted; revised paragraph and table structure may be approximated."
    var files: [String: Data] = [:], targets: [String: String] = [:]
    var headerIDs: [String: String] = [:], footerIDs: [String: String] = [:]
    var differentFirstPage = false
    var runningNumberStart: Int?
    var tableDepth = 0, tableIndex: Int?, row = -1, column = -1
    private let tableFormatting = DOCXTableFormattingReader()
    private let tableMerging = DOCXTableMergingReader()
    var inDrawing = false
    private let imageReader = DOCXImageReader()
    private let equationReader = DOCXEquationReader()
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if skippedReviewDepth > 0 { skippedReviewDepth += 1; return }
        if namespaceURI == DOCX.wordNS, ["del", "moveFrom", "rPrChange", "pPrChange"].contains(name) {
            warnings.insert(reviewImportWarning)
            skippedReviewDepth = 1
            return
        }
        if equationReader.active || (namespaceURI == DOCXEquations.namespace && name == "oMath") {
            if !equationReader.active { equationReader.defaultSize = paragraph.map { document.style(for: $0).text.fontSize ?? 12 } ?? 12 }
            equationReader.start(name, namespace: namespaceURI, attributes: a, parser: parser); return
        }
        if inDrawing {
            imageReader.start(name, namespace: namespaceURI, attributes: a, targets: targets, warnings: &warnings)
        }
        guard namespaceURI == DOCX.wordNS else { return }
        switch name {
        case "document": sawDocument = true
        case "p":
            paragraph = Paragraph(); paragraph?.runs = []; listID = nil; listLevel = nil
            if let t = tableIndex, row >= 0, column >= 0 { paragraph?.tableCell = TableCellReference(tableID: document.tables[t].id, row: row, column: column) }
        case "r": run = TextRun("", link: link); inRun = true
        case "t": collecting = true
        case "lang":
            if let language = wordAttribute(a), (try? DocumentMetadata.languageIdentifier(language)) != document.language {
                warnings.insert("Run and paragraph spelling languages are flattened to the document language.")
            }
        case "instrText": collectingInstruction = true; instruction = ""
        case "fldSimple": inspectFieldInstruction(wordAttribute(a, "instr") ?? "")
        case "fldChar":
            switch wordAttribute(a, "fldCharType") {
            case "begin": fieldInstructions.append("")
            case "separate":
                if let code = fieldInstructions.last { inspectFieldInstruction(code); fieldInstructions[fieldInstructions.count - 1] = "" }
            case "end": if let code = fieldInstructions.popLast() { inspectFieldInstruction(code) }
            default: break
            }
        case "footnoteReference", "endnoteReference":
            let kind = name == "footnoteReference" ? "footnote" : "endnote"
            guard let rawID = wordAttribute(a, "id"), let number = Int(rawID), let id = noteIDs[kind + ":" + String(number)] else { parser.abortParsing(); return }
            if !run.text.isEmpty { paragraph?.runs.append(run) }
            var reference = TextRun("\u{fffc}", format: run.format); reference.noteID = id; reference.format.baseline = nil
            paragraph?.runs.append(reference); run = TextRun("", format: run.format, link: link)
            if ["1", "true", "on"].contains(wordAttribute(a, "customMarkFollows") ?? "") { warnings.insert("Custom note reference marks use automatic numbering in Scribe.") }
        case "tab": run.text += "\t"
        case "br":
            if wordAttribute(a, "type") == "page" { run.text += "\u{c}" }
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
        case "bookmarkStart":
            if let name = wordAttribute(a, "name"), let paragraph {
                if bookmarkParagraphs[name] == nil { bookmarkOrder.append(name) }
                bookmarkParagraphs[name] = paragraph.id
                if paragraph.runs.contains(where: { !$0.text.isEmpty }) || (inRun && !run.text.isEmpty) {
                    warnings.insert("Bookmarks and internal links to positions within paragraphs navigate to the paragraph start in this version.")
                }
            }
        case "hyperlink":
            link = (a["r:id"] ?? a["id"]).flatMap { links[$0] }
            if link == nil, let anchor = wordAttribute(a, "anchor") { link = "#" + anchor }
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
                tableMerging.startTable()
            } else { warnings.insert("Nested tables are flattened into the enclosing cell.") }
        case "gridCol":
            if tableDepth == 1, let t = tableIndex, let width = wordAttribute(a, "w").flatMap(Double.init) { document.tables[t].columnWidths.append(max(12, width / 20)) }
        case "tr": if tableDepth == 1 { row += 1; column = -1; tableMerging.span = 1 }
        case "tc":
            if tableDepth == 1, let t = tableIndex {
                column += tableMerging.span
                tableMerging.startCell(paragraphCount: paragraphs.count)
                if column >= document.tables[t].columnWidths.count { document.tables[t].columnWidths.append(100) }
            }
        case "tblHeader": if let t = tableIndex { document.tables[t].firstRowIsHeader = true }
        case "gridSpan":
            if tableDepth == 1 {
                guard let span = wordAttribute(a, "val").flatMap(Int.init), (1...20).contains(span) else { parser.abortParsing(); return }
                tableMerging.span = span
            }
        case "vMerge": if tableDepth == 1 { tableMerging.vertical = wordAttribute(a, "val") ?? "continue" }
        case "hMerge": warnings.insert("Legacy horizontal merge properties are imported as separate cells; all cell text is retained.")
        case "gridBefore", "gridAfter": warnings.insert("Omitted table grid cells are approximated with a rectangular table; leading offsets are retained.")
            if name == "gridBefore", tableDepth == 1, let count = wordAttribute(a, "val").flatMap(Int.init), (0...19).contains(count) { column = count - 1 }
        case "drawing":
            if !run.text.isEmpty { paragraph?.runs.append(run); run = TextRun("", link: link) }
            inDrawing = true; imageReader.reset()
        case "pict": warnings.insert("Legacy drawings are not imported.")
        case "headerReference": headerIDs[wordAttribute(a, "type") ?? "default"] = a["r:id"] ?? a["id"]
        case "footerReference": footerIDs[wordAttribute(a, "type") ?? "default"] = a["r:id"] ?? a["id"]
        case "titlePg": differentFirstPage = flag(a)
        case "pgNumType": runningNumberStart = wordAttribute(a, "start").flatMap(Int.init)
        case "ins", "moveTo": warnings.insert(reviewImportWarning)
        case "sectPr": differentFirstPage = false; if !paragraphs.isEmpty && paragraph != nil { warnings.insert("Section settings are flattened to one page layout.") }
        default: if inRun { applyRun(name, a, &run.format) }
        }
        if tableDepth == 1, let t = tableIndex { tableFormatting.start(name, a, table: &document.tables[t], row: row, column: column, warnings: &warnings) }
    }
    private func inspectFieldInstruction(_ code: String) {
        if code.split(whereSeparator: \.isWhitespace).first?.uppercased() == "TOC" {
            warnings.insert("Tables of contents are imported as cached text and heading links. Insert a Scribe table of contents to regenerate entries and page numbers.")
        }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) {
        guard skippedReviewDepth == 0 else { return }
        if equationReader.active { equationReader.characters(text, parser: parser); return }
        if collecting { run.text += text }
        if collectingInstruction { instruction += text }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if skippedReviewDepth > 0 { skippedReviewDepth -= 1; return }
        if equationReader.active {
            if let result = equationReader.end() {
                paragraph?.runs.append(result.run)
                if let warning = result.warning { warnings.insert(warning) }
            }
            return
        }
        guard namespaceURI == DOCX.wordNS else { return }
        if tableDepth == 1, let t = tableIndex {
            if name == "tbl" { document.tables[t].rows = max(1, row + 1) }
            tableFormatting.end(name, table: &document.tables[t], warnings: &warnings)
        }
        switch name {
        case "t": collecting = false
        case "instrText":
            collectingInstruction = false
            if !fieldInstructions.isEmpty { fieldInstructions[fieldInstructions.count - 1] += instruction }
            else { inspectFieldInstruction(instruction) }
        case "r": if !run.text.isEmpty { paragraph?.runs.append(run) }; inRun = false
        case "drawing":
            inDrawing = false
            if let image = imageReader.image(files: files, page: document.sections[0].page, warnings: &warnings) {
                var imageRun = TextRun("\u{FFFC}")
                imageRun.image = image
                paragraph?.runs.append(imageRun)
            }
            run = TextRun("", link: link)
        case "tbl":
            if tableDepth == 1, let t = tableIndex {
                document.tables[t].rows = max(1, row + 1)
                tableMerging.finishTable(&document.tables[t])
                if document.tables[t].columnWidths.isEmpty { document.tables[t].columnWidths = [100] }
                tableIndex = nil; row = -1; column = -1
            }
            tableDepth = max(0, tableDepth - 1)
        case "tc":
            if tableDepth == 1, let t = tableIndex {
                let protected = Set(bookmarkParagraphs.values).union(commentStarts.values.map(\.paragraphID)).union(commentEnds.values.map(\.paragraphID)).union(commentReferences.values.map(\.paragraphID))
                tableMerging.finishCell(table: &document.tables[t], row: row, column: column, paragraphs: &paragraphs, protectedIDs: protected, warnings: &warnings)
            }
        case "p":
            let inherited = paragraph.flatMap { styleLists[$0.styleID] }
            if let id = listID ?? inherited?.id { paragraph?.list = numbering.descriptor(id: id, level: listLevel ?? inherited?.level ?? 0) }
            if let p = paragraph { paragraphs.append(p) }; paragraph = nil
        case "hyperlink": link = nil
        default: break
        }
    }
}
