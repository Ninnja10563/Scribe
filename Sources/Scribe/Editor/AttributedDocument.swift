#if canImport(AppKit)
import AppKit
import DocumentCore

extension NSAttributedString.Key {
    static let scribeStyle = NSAttributedString.Key("org.scribe.paragraphStyle")
    static let scribeParagraphID = NSAttributedString.Key("org.scribe.paragraphID")
    static let scribeCell = NSAttributedString.Key("org.scribe.tableCell")
    static let scribeImage = NSAttributedString.Key("org.scribe.image")
    static let scribeList = NSAttributedString.Key("org.scribe.list")
}

/// The attributed string is an editing projection, not the on-disk document model.
@MainActor enum AttributedDocument {
    static func render(_ document: ScribeDocument) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        var numbering = ListNumbering()
        let tables = TableProjection(document: document)
        let paragraphs = document.paragraphs
        for (index, paragraph) in paragraphs.enumerated() {
            let style = document.style(for: paragraph)
            var base = attributes(style: style, paragraph: paragraph)
            if let cell = paragraph.tableCell { tables.apply(cell, to: &base) }
            let start = result.length
            if paragraph.pageBreakBefore { result.append(NSAttributedString(string: "\u{c}", attributes: base)) }
            if let marker = numbering.marker(for: paragraph.list) { result.append(NSAttributedString(string: "\t" + marker + "\t", attributes: base)) }
            for run in paragraph.runs {
                var attrs = base
                apply(run.format, over: style.text, to: &attrs)
                if let link = run.link { attrs[.link] = link }
                if let image = run.image, let attachment = ImageProjection.attachment(image) {
                    attrs[.attachment] = attachment; attrs[.scribeImage] = try? JSONEncoder().encode(image)
                }
                result.append(NSAttributedString(string: run.text, attributes: attrs))
            }
            if index < paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: base))
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
        let text = storage.string as NSString
        let originalParagraphs = original.paragraphs
        var offset = 0
        // components preserves the final empty paragraph, important after pressing Return.
        for component in storage.string.components(separatedBy: "\n") {
            let length = (component as NSString).length
            let attrs: [NSAttributedString.Key: Any]
            if offset == storage.length, let typingAttributes { attrs = typingAttributes }
            else if offset == storage.length, component.isEmpty, let last = originalParagraphs.last, last.text.isEmpty {
                // An empty final paragraph has no character to carry its attributes.
                // Preserve its model identity/style when focus has moved elsewhere.
                attrs = attributes(style: original.style(for: last), paragraph: last)
            }
            else if storage.length > 0 { attrs = storage.attributes(at: min(offset, storage.length - 1), effectiveRange: nil) }
            else { attrs = attributes(style: original.style(for: original.paragraphs[0]), paragraph: original.paragraphs[0]) }
            var p = Paragraph()
            if storage.length == 0 { p.id = original.paragraphs[0].id }
            if let idString = attrs[.scribeParagraphID] as? String, let id = UUID(uuidString: idString), !usedIDs.contains(id) { p.id = id }
            usedIDs.insert(p.id)
            p.styleID = attrs[.scribeStyle] as? String ?? "normal"
            if !document.styles.contains(where: { $0.id == p.styleID }) { p.styleID = "normal" }
            let style = document.style(for: p)
            p.pageBreakBefore = component.hasPrefix("\u{c}")
            p.tableCell = (attrs[.scribeCell] as? Data).flatMap { try? JSONDecoder().decode(TableCellReference.self, from: $0) }
            p.list = (attrs[.scribeList] as? Data).flatMap { try? JSONDecoder().decode(ListDescriptor.self, from: $0) }
            if let ns = attrs[.paragraphStyle] as? NSParagraphStyle {
                let f = paragraphFormatting(ns)
                if f != style.paragraph { p.formatting = f }
            }
            p.runs = []
            var prefix = p.pageBreakBefore ? 1 : 0
            let withoutBreak = String(component.dropFirst(prefix))
            if p.list != nil, withoutBreak.hasPrefix("\t"), let end = withoutBreak.dropFirst().firstIndex(of: "\t") {
                prefix += (String(withoutBreak[...end]) as NSString).length
            }
            if length > prefix {
                storage.enumerateAttributes(in: NSRange(location: offset + prefix, length: length - prefix)) { attributes, range, _ in
                    let value = text.substring(with: range).replacingOccurrences(of: "\u{c}", with: "")
                    guard !value.isEmpty else { return }
                    var format = TextFormatting()
                    if let font = attributes[.font] as? NSFont {
                        if font.familyName != style.text.fontFamily { format.fontFamily = font.familyName }
                        if Double(font.pointSize) != style.text.fontSize { format.fontSize = Double(font.pointSize) }
                        let traits = NSFontManager.shared.traits(of: font)
                        if traits.contains(.boldFontMask) != (style.text.bold ?? false) { format.bold = traits.contains(.boldFontMask) }
                        if traits.contains(.italicFontMask) != (style.text.italic ?? false) { format.italic = traits.contains(.italicFontMask) }
                    }
                    let underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
                    if underline != (style.text.underline ?? false) { format.underline = underline }
                    let strike = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
                    if strike != (style.text.strikethrough ?? false) { format.strikethrough = strike }
                    if let color = attributes[.foregroundColor] as? NSColor, let hex = color.hex, hex != (style.text.foreground ?? "#1D1D1F") { format.foreground = hex }
                    if let color = attributes[.backgroundColor] as? NSColor { format.highlight = color.hex }
                    if let baseline = attributes[.superscript] as? Int { format.baseline = baseline }
                    let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
                    var run = TextRun(value, format: format, link: link)
                    if let attachment = attributes[.attachment] as? NSTextAttachment {
                        if let data = attributes[.scribeImage] as? Data { run.image = try? JSONDecoder().decode(InlineImage.self, from: data) }
                        else if let bytes = attachment.fileWrapper?.regularFileContents {
                            run.image = try? ImageProjection.image(from: bytes, maximumWidth: original.sections[0].page.contentWidth, maximumHeight: original.sections[0].page.contentHeight - 24)
                        }
                    }
                    p.runs.append(run)
                }
            }
            if p.runs.isEmpty { p.runs = [TextRun("")] }
            paragraphs.append(p); offset += length + 1
        }
        document.sections[0].paragraphs = paragraphs
        let usedTables = Set(paragraphs.compactMap { $0.tableCell?.tableID })
        document.tables.removeAll { !usedTables.contains($0.id) }
        CommentProjection.capture(from: storage, document: &document)
        // The current editing projection supports one section; imports are flattened explicitly.
        return document
    }
    static func attributes(style: ParagraphStyle, paragraph: Paragraph? = nil) -> [NSAttributedString.Key: Any] {
        let ns = NSMutableParagraphStyle()
        let f = paragraph?.formatting ?? style.paragraph
        ns.alignment = [.left: .left, .center: .center, .right: .right, .justified: .justified][f.alignment]!
        ns.lineSpacing = f.lineSpacing; ns.paragraphSpacingBefore = f.spaceBefore; ns.paragraphSpacing = f.spaceAfter
        ns.firstLineHeadIndent = f.firstLineIndent; ns.headIndent = f.headIndent; ns.tailIndent = -f.tailIndent
        var attrs: [NSAttributedString.Key: Any] = [.paragraphStyle: ns, .scribeStyle: style.id]
        if let paragraph { attrs[.scribeParagraphID] = paragraph.id.uuidString }
        if let list = paragraph?.list {
            let marker: NSTextList.MarkerFormat
            switch list.kind { case .bullet: marker = .disc; case .decimal: marker = .decimal; case .lowerAlpha: marker = .lowercaseAlpha; case .lowerRoman: marker = .lowercaseRoman; case .upperAlpha: marker = .uppercaseAlpha; case .upperRoman: marker = .uppercaseRoman }
            ns.textLists = (0...list.level).map { _ in NSTextList(markerFormat: marker, options: 0) }
            ns.headIndent = CGFloat(list.level + 1) * 24; ns.firstLineHeadIndent = ns.headIndent - 18
            ns.tabStops = [NSTextTab(textAlignment: .right, location: ns.headIndent - 6), NSTextTab(textAlignment: .left, location: ns.headIndent)]
            attrs[.scribeList] = try? JSONEncoder().encode(list)
        }
        apply(TextFormatting(), over: style.text, to: &attrs)
        return attrs
    }
    static func apply(_ f: TextFormatting, over base: TextFormatting, to attributes: inout [NSAttributedString.Key: Any]) {
        let size = f.fontSize ?? base.fontSize ?? 12
        let family = f.fontFamily ?? base.fontFamily ?? "Helvetica Neue"
        var font = NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)
        if f.bold ?? base.bold ?? false { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if f.italic ?? base.italic ?? false { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        attributes[.font] = font
        attributes[.foregroundColor] = NSColor(hex: f.foreground ?? base.foreground ?? "#1D1D1F")
        attributes[.underlineStyle] = (f.underline ?? base.underline ?? false) ? NSUnderlineStyle.single.rawValue : 0
        attributes[.strikethroughStyle] = (f.strikethrough ?? base.strikethrough ?? false) ? NSUnderlineStyle.single.rawValue : 0
        if let color = f.highlight ?? base.highlight { attributes[.backgroundColor] = NSColor(hex: color) }
        if let baseline = f.baseline ?? base.baseline { attributes[.superscript] = baseline }
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
