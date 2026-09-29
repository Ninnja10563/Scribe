#if canImport(AppKit)
import AppKit
import DocumentCore

extension AttributedDocument {
    static func captureTextFormat(_ attributes: [NSAttributedString.Key: Any], style: ParagraphStyle) -> TextFormatting {
        var format = TextFormatting()
        if let font = ScriptProjection.logicalFont(in: attributes) {
            let inheritedFont = FontProjection.font(TextFormatting(), over: style.text)
            let inheritedTraits = NSFontManager.shared.traits(of: inheritedFont)
            if font.familyName != inheritedFont.familyName { format.fontFamily = font.familyName }
            if Double(font.pointSize) != style.text.fontSize { format.fontSize = Double(font.pointSize) }
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) != inheritedTraits.contains(.boldFontMask) { format.bold = traits.contains(.boldFontMask) }
            if traits.contains(.italicFontMask) != inheritedTraits.contains(.italicFontMask) { format.italic = traits.contains(.italicFontMask) }
            let inferred = FontProjection.font(format, over: style.text)
            if inferred.fontName != font.fontName { format.fontFace = font.fontName }
            // A missing installed face renders with a fallback, but remains in the
            // document until the user actually chooses a different font.
            if let requested = attributes[.scribeFontFace] as? String,
               attributes[.scribeRenderedFace] as? String == font.fontName {
                format.fontFace = requested == style.text.fontFace ? nil : requested
            }
        }
        let underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
        if underline != (style.text.underline ?? false) { format.underline = underline }
        let strike = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
        if strike != (style.text.strikethrough ?? false) { format.strikethrough = strike }
        if let color = attributes[.foregroundColor] as? NSColor, let hex = color.hex, hex != (style.text.foreground ?? "#1D1D1F") { format.foreground = hex }
        if let color = attributes[.backgroundColor] as? NSColor {
            if color.hex != style.text.highlight { format.highlight = color.hex }
        } else if style.text.highlight != nil { format.clearHighlight = true }
        let baseline = ScriptProjection.level(in: attributes)
        if baseline != (style.text.baseline ?? 0) { format.baseline = baseline }
        return format
    }
    static func editingAttributes(for paragraph: Paragraph, in document: ScribeDocument) -> [NSAttributedString.Key: Any] {
        let style = document.style(for: paragraph)
        var result = attributes(style: style, paragraph: paragraph, contentWidth: document.sections[0].page.contentWidth)
        if paragraph.text.isEmpty, let run = paragraph.runs.first { apply(run.format, over: style.text, to: &result) }
        return result
    }
}
#endif
