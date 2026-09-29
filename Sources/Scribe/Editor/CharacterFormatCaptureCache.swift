#if canImport(AppKit)
import AppKit
import DocumentCore

/// Scoped to one capture: paragraph IDs and review identities must not prevent
/// identical character appearances from sharing expensive font conversions.
@MainActor struct CharacterFormatCaptureCache {
    private struct Key: Hashable {
        let styleID: String
        let font: NSFont?
        let requestedFace: String?
        let renderedFace: String?
        let underline: Bool
        let strike: Bool
        let foreground: NSColor?
        let highlight: NSColor?
        let script: Int
    }
    private var values: [Key: TextFormatting] = [:]
    mutating func format(_ attributes: [NSAttributedString.Key: Any], style: ParagraphStyle) -> TextFormatting {
        let key = Key(styleID: style.id, font: ScriptProjection.logicalFont(in: attributes),
                      requestedFace: attributes[.scribeFontFace] as? String,
                      renderedFace: attributes[.scribeRenderedFace] as? String,
                      underline: (attributes[.underlineStyle] as? Int ?? 0) != 0,
                      strike: (attributes[.strikethroughStyle] as? Int ?? 0) != 0,
                      foreground: attributes[.foregroundColor] as? NSColor,
                      highlight: attributes[.backgroundColor] as? NSColor,
                      script: ScriptProjection.level(in: attributes))
        if let value = values[key] { return value }
        let value = AttributedDocument.captureTextFormat(attributes, style: style)
        // Highly heterogeneous documents retain bounded cache memory.
        if values.count < 512 { values[key] = value }
        return value
    }
}
#endif
