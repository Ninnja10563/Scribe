#if canImport(AppKit)
import AppKit
import DocumentCore

extension NSAttributedString.Key {
    static let scribeParagraphReview = NSAttributedString.Key("org.scribe.paragraphReview")
    static let scribeBreakReview = NSAttributedString.Key("org.scribe.breakReview")
    static let scribeReview = NSAttributedString.Key("org.scribe.review")
    static let scribePageBreakMarker = NSAttributedString.Key("org.scribe.pageBreakMarker")
    static let scribeTOC = NSAttributedString.Key("org.scribe.tableOfContents")
    static let scribeStyle = NSAttributedString.Key("org.scribe.paragraphStyle")
    static let scribeParagraphID = NSAttributedString.Key("org.scribe.paragraphID")
    static let scribeCell = NSAttributedString.Key("org.scribe.tableCell")
    static let scribeNoteContentID = NSAttributedString.Key("org.scribe.noteContent")
    static let scribeNoteLabelID = NSAttributedString.Key("org.scribe.noteLabel")
    static let scribeNoteNumber = NSAttributedString.Key("org.scribe.noteNumber")
    static let scribeNote = NSAttributedString.Key("org.scribe.note")
    static let scribeEquation = NSAttributedString.Key("org.scribe.equation")
    static let scribeImage = NSAttributedString.Key("org.scribe.image")
    static let scribeRenderedFace = NSAttributedString.Key("org.scribe.renderedFace")
    static let scribeFontFace = NSAttributedString.Key("org.scribe.fontFace")
    static let scribeList = NSAttributedString.Key("org.scribe.list")
}

/// The attributed string is an editing projection, not the on-disk document model.
@MainActor enum AttributedDocument {
    static func render(_ document: ScribeDocument) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let numberedNotes = (try? NoteNumbering.resolve(referenceIDs: document.paragraphs.flatMap(\.runs).compactMap(\.noteID), notes: document.notes)) ?? []
        let notes = Dictionary(uniqueKeysWithValues: numberedNotes.map { ($0.id, $0) })
        var numbering = ListNumbering()
        let tables = TableProjection(document: document)
        let paragraphs = document.paragraphs
        for (index, paragraph) in paragraphs.enumerated() {
            let style = document.style(for: paragraph)
            var base = attributes(style: style, paragraph: paragraph, contentWidth: document.sections[0].page.contentWidth)
            if paragraph.text.isEmpty, let run = paragraph.runs.first { apply(run.format, over: style.text, to: &base) }
            if let cell = paragraph.tableCell { tables.apply(cell, to: &base) }
            let start = result.length
            if paragraph.pageBreakBefore {
                var marker = base; marker[.scribePageBreakMarker] = true
                result.append(NSAttributedString(string: "\u{c}", attributes: marker))
            }
            if let marker = numbering.marker(for: paragraph.list) { result.append(NSAttributedString(string: "\t" + marker + "\t", attributes: base)) }
            for run in paragraph.runs {
                var attrs = base
                apply(run.format, over: style.text, to: &attrs)
                if let review = run.review { attrs[.scribeReview] = try? JSONEncoder().encode(review) }
                if let link = run.link { attrs[.link] = link }
                if let id = run.noteID, let note = notes[id] {
                    attrs[.attachment] = NoteProjection.attachment(note, baseFont: ScriptProjection.logicalFont(in: attrs) ?? .systemFont(ofSize: 12))
                    attrs[.scribeNoteNumber] = note.number
                    attrs[.scribeNote] = try? JSONEncoder().encode(note.note)
                }
                if let equation = run.equation {
                    attrs[.attachment] = EquationProjection.attachment(equation); attrs[.scribeEquation] = try? JSONEncoder().encode(equation)
                }
                if let image = run.image, let attachment = ImageProjection.attachment(image) {
                    attrs[.attachment] = attachment; attrs[.scribeImage] = try? JSONEncoder().encode(image)
                }
                result.append(NSAttributedString(string: run.text, attributes: attrs))
            }
            if index < paragraphs.count - 1 {
                var separator = base
                if let review = paragraph.breakReview { separator[.scribeBreakReview] = try? JSONEncoder().encode(review) }
                result.append(NSAttributedString(string: "\n", attributes: separator))
            }
            if result.length > start {
                result.addAttributes([.scribeStyle: paragraph.styleID, .scribeParagraphID: paragraph.id.uuidString], range: NSRange(location: start, length: result.length - start))
            }
        }
        CommentProjection.apply(to: result, document: document)
        return result
    }
    static func capture(_ storage: NSAttributedString, preserving original: ScribeDocument, typingAttributes: [NSAttributedString.Key: Any]? = nil) -> ScribeDocument {
        var document = original
        var paragraphs: [Paragraph] = [], usedIDs: Set<UUID> = []
        var capturedNotes: [DocumentNote] = []
        var characterFormats = CharacterFormatCaptureCache()
        let text = storage.string as NSString
        let originalParagraphs = original.paragraphs
        let originalsByID = Dictionary(originalParagraphs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let originalTOCIDs = Set(originalParagraphs.filter { $0.toc != nil }.map(\.id))
        var offset = 0
        // components preserves the final empty paragraph, important after pressing Return.
        for component in storage.string.components(separatedBy: "\n") {
            let length = (component as NSString).length
            let attrs: [NSAttributedString.Key: Any]
            if offset == storage.length, let typingAttributes { attrs = typingAttributes }
            else if offset == storage.length, component.isEmpty, let last = originalParagraphs.last, last.text.isEmpty {
                // An empty final paragraph has no character to carry its attributes.
                // Preserve its model identity/style when focus has moved elsewhere.
                attrs = editingAttributes(for: last, in: original)
            }
            else if storage.length > 0 { attrs = storage.attributes(at: min(offset, storage.length - 1), effectiveRange: nil) }
            else { attrs = editingAttributes(for: original.paragraphs[0], in: original) }
            var p = Paragraph()
            if storage.length == 0 { p.id = original.paragraphs[0].id }
            if let idString = attrs[.scribeParagraphID] as? String, let id = UUID(uuidString: idString), !usedIDs.contains(id) { p.id = id }
            usedIDs.insert(p.id)
            if originalTOCIDs.contains(p.id) {
                p.toc = (attrs[.scribeTOC] as? Data).flatMap { try? JSONDecoder().decode(TOCParagraph.self, from: $0) }
            }
            p.styleID = attrs[.scribeStyle] as? String ?? "normal"
            if !document.styles.contains(where: { $0.id == p.styleID }) { p.styleID = "normal" }
            let style = document.style(for: p)
            p.pageBreakBefore = component.hasPrefix("\u{c}") && attrs[.scribePageBreakMarker] as? Bool == true
            p.tableCell = (attrs[.scribeCell] as? Data).flatMap { try? JSONDecoder().decode(TableCellReference.self, from: $0) }
            p.list = (attrs[.scribeList] as? Data).flatMap { try? JSONDecoder().decode(ListDescriptor.self, from: $0) }
            if let ns = attrs[.paragraphStyle] as? NSParagraphStyle {
                let f = paragraphFormatting(ns)
                if f != style.paragraph { p.formatting = f }
                // List markers supply display indents. Capturing those as direct
                // paragraph formatting would leave the list indent behind when
                // the user exits a list, and freeze unrelated style properties.
                if p.list != nil, p.tableCell == nil, let source = originalsByID[p.id],
                   source.list == p.list, source.styleID == p.styleID,
                   let projected = attributes(style: style, paragraph: source)[.paragraphStyle] as? NSParagraphStyle,
                   paragraphFormatting(projected) == f {
                    p.formatting = source.formatting
                }
            }
            if let data = attrs[.scribeParagraphReview] as? Data,
               let review = try? JSONDecoder().decode(ParagraphFormattingReview.self, from: data) {
                p.formattingReview = review
                var expected = p; review.state.apply(to: &expected)
                let projected = attributes(style: document.style(for: expected), paragraph: expected, contentWidth: document.sections[0].page.contentWidth)
                if let actual = attrs[.paragraphStyle] as? NSParagraphStyle,
                   let expectedStyle = projected[.paragraphStyle] as? NSParagraphStyle,
                   paragraphFormatting(actual) == paragraphFormatting(expectedStyle) {
                    p.formatting = review.state.formatting
                }
            }
            if offset + length < storage.length, let data = storage.attribute(.scribeBreakReview, at: offset + length, effectiveRange: nil) as? Data {
                p.breakReview = try? JSONDecoder().decode(RunReview.self, from: data)
            }
            p.runs = []
            var prefix = p.pageBreakBefore ? 1 : 0
            let withoutBreak = String(component.dropFirst(prefix))
            if p.list != nil, withoutBreak.hasPrefix("\t"), let end = withoutBreak.dropFirst().firstIndex(of: "\t") {
                prefix += (String(withoutBreak[...end]) as NSString).length
            }
            if length > prefix {
                storage.enumerateAttributes(in: NSRange(location: offset + prefix, length: length - prefix)) { attributes, range, _ in
                    let value = text.substring(with: range)
                    guard !value.isEmpty else { return }
                    let format = characterFormats.format(attributes, style: style)
                    let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
                    var run = TextRun(value, format: format, link: link)
                    if let data = attributes[.scribeReview] as? Data {
                        run.review = try? JSONDecoder().decode(RunReview.self, from: data)
                        run.format = run.review?.preservingFormatting(format, inheriting: style.text) ?? format
                    }
                    if let attachment = attributes[.attachment] as? NSTextAttachment {
                        if let data = attributes[.scribeNote] as? Data, data.count <= NativeFormat.maximumBytes,
                           let note = try? JSONDecoder().decode(DocumentNote.self, from: data) {
                            run.noteID = note.id; capturedNotes.append(note)
                        }
                        else if let data = attributes[.scribeEquation] as? Data { run.equation = try? JSONDecoder().decode(Equation.self, from: data) }
                        else if let data = attributes[.scribeImage] as? Data { run.image = try? JSONDecoder().decode(InlineImage.self, from: data) }
                        else if let bytes = attachment.fileWrapper?.regularFileContents {
                            run.image = try? ImageProjection.image(from: bytes, maximumWidth: original.sections[0].page.contentWidth, maximumHeight: original.sections[0].page.contentHeight - 24)
                        }
                    }
                    if (run.equation != nil || run.image != nil || run.noteID != nil), value.allSatisfy({ $0 == "\u{FFFC}" }) {
                        // AppKit may coalesce adjacent copies of the same attachment.
                        run.text = "\u{FFFC}"
                        p.runs.append(contentsOf: Array(repeating: run, count: value.count))
                    } else { p.runs.append(run) }
                }
            }
            if p.runs.isEmpty { p.runs = [TextRun("", format: characterFormats.format(attrs, style: style))] }
            paragraphs.append(p); offset += length + 1
        }
        document.sections[0].paragraphs = paragraphs
        document.notes = capturedNotes
        let usedTOCs = Set(paragraphs.compactMap { $0.toc?.tableID })
        document.tablesOfContents.removeAll { !usedTOCs.contains($0.id) }
        let usedTables = Set(paragraphs.compactMap { $0.tableCell?.tableID })
        document.tables.removeAll { !usedTables.contains($0.id) }
        CommentProjection.capture(from: storage, document: &document)
        // The current editing projection supports one section; imports are flattened explicitly.
        return document
    }
    static func attributes(style: ParagraphStyle, paragraph: Paragraph? = nil, contentWidth: Double? = nil) -> [NSAttributedString.Key: Any] {
        let ns = NSMutableParagraphStyle()
        let f = paragraph?.formatting ?? style.paragraph
        ns.alignment = [.left: .left, .center: .center, .right: .right, .justified: .justified][f.alignment]!
        ns.lineSpacing = f.lineSpacing; ns.paragraphSpacingBefore = f.spaceBefore; ns.paragraphSpacing = f.spaceAfter
        ns.firstLineHeadIndent = f.firstLineIndent; ns.headIndent = f.headIndent; ns.tailIndent = -f.tailIndent
        var attrs: [NSAttributedString.Key: Any] = [.paragraphStyle: ns, .scribeStyle: style.id]
        if let paragraph {
            attrs[.scribeParagraphID] = paragraph.id.uuidString
            if let review = paragraph.formattingReview { attrs[.scribeParagraphReview] = try? JSONEncoder().encode(review) }
        }
        if let list = paragraph?.list {
            let marker: NSTextList.MarkerFormat
            switch list.kind { case .bullet: marker = .disc; case .decimal: marker = .decimal; case .lowerAlpha: marker = .lowercaseAlpha; case .lowerRoman: marker = .lowercaseRoman; case .upperAlpha: marker = .uppercaseAlpha; case .upperRoman: marker = .uppercaseRoman }
            ns.textLists = (0...list.level).map { _ in NSTextList(markerFormat: marker, options: 0) }
            ns.headIndent = CGFloat(list.level + 1) * 24; ns.firstLineHeadIndent = ns.headIndent - 18
            ns.tabStops = [NSTextTab(textAlignment: .right, location: ns.headIndent - 6), NSTextTab(textAlignment: .left, location: ns.headIndent)]
            attrs[.scribeList] = try? JSONEncoder().encode(list)
        }
        if let toc = paragraph?.toc {
            attrs[.scribeTOC] = try? JSONEncoder().encode(toc)
            if toc.kind == .entry {
                ns.headIndent = CGFloat(max(0, (toc.level ?? 1) - 1)) * 14; ns.firstLineHeadIndent = ns.headIndent
                ns.tabStops = [NSTextTab(textAlignment: .right, location: (contentWidth ?? 451.276) - f.tailIndent)]
            }
        }
        apply(TextFormatting(), over: style.text, to: &attrs)
        return attrs
    }
    static func apply(_ f: TextFormatting, over base: TextFormatting, to attributes: inout [NSAttributedString.Key: Any]) {
        let font = FontProjection.font(f, over: base)
        attributes[.font] = font
        if let face = FontProjection.requestedFace(f, over: base) {
            attributes[.scribeFontFace] = face; attributes[.scribeRenderedFace] = font.fontName
        } else {
            attributes.removeValue(forKey: .scribeFontFace); attributes.removeValue(forKey: .scribeRenderedFace)
        }
        attributes[.foregroundColor] = NSColor(hex: f.foreground ?? base.foreground ?? "#1D1D1F")
        attributes[.underlineStyle] = (f.underline ?? base.underline ?? false) ? NSUnderlineStyle.single.rawValue : 0
        attributes[.strikethroughStyle] = (f.strikethrough ?? base.strikethrough ?? false) ? NSUnderlineStyle.single.rawValue : 0
        let highlight = f.clearHighlight == true ? nil : f.highlight ?? (base.clearHighlight == true ? nil : base.highlight)
        if let color = highlight { attributes[.backgroundColor] = NSColor(hex: color) }
        else { attributes.removeValue(forKey: .backgroundColor) }
        ScriptProjection.setLevel(f.baseline ?? base.baseline ?? 0, in: &attributes)
    }
    static func paragraphFormatting(_ ns: NSParagraphStyle) -> ParagraphFormatting {
        var f = ParagraphFormatting()
        f.alignment = [.left: Alignment.left, .center: .center, .right: .right, .justified: .justified][ns.alignment] ?? .left
        f.lineSpacing = ns.lineSpacing; f.spaceBefore = ns.paragraphSpacingBefore; f.spaceAfter = ns.paragraphSpacing
        f.firstLineIndent = ns.firstLineHeadIndent; f.headIndent = ns.headIndent; f.tailIndent = -ns.tailIndent
        return f
    }
}
extension NSColor {
    convenience init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x1D1D1F
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    var hex: String? {
        guard let c = usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}
#endif
