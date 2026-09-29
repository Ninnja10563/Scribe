#if canImport(AppKit)
import AppKit

extension NSAttributedString.Key {
    static let scribeScriptLevel = NSAttributedString.Key("org.scribe.scriptLevel")
    static let scribeScriptBaseFont = NSAttributedString.Key("org.scribe.scriptBaseFont")
    static let scribeScriptRenderedFont = NSAttributedString.Key("org.scribe.scriptRenderedFont")
}

/// Semantic script levels keep their original font size. Only the native projection
/// reduces the glyphs and moves their baseline; external rich text uses semantic levels.
@MainActor enum ScriptProjection {
    static func logicalFont(in attributes: [NSAttributedString.Key: Any]) -> NSFont? {
        guard let font = attributes[.font] as? NSFont else { return nil }
        if let base = attributes[.scribeScriptBaseFont] as? NSFont,
           let rendered = attributes[.scribeScriptRenderedFont] as? NSFont, font == rendered { return base }
        return font
    }
    static func level(in attributes: [NSAttributedString.Key: Any]) -> Int {
        max(-1, min(1, attributes[.scribeScriptLevel] as? Int ?? attributes[.superscript] as? Int ?? 0))
    }
    static func setLevel(_ level: Int, in attributes: inout [NSAttributedString.Key: Any]) {
        attributes.removeValue(forKey: .scribeScriptLevel); attributes[.superscript] = level
        apply(to: &attributes)
    }
    static func apply(to attributes: inout [NSAttributedString.Key: Any]) {
        guard let font = logicalFont(in: attributes) else { return }
        let level = level(in: attributes)
        // AppKit also offsets NSSuperscript. Keep the semantic level separately
        // so our size-relative baseline is applied exactly once.
        attributes.removeValue(forKey: .superscript); attributes.removeValue(forKey: .scribeScriptLevel)
        attributes[.font] = font
        attributes.removeValue(forKey: .scribeScriptBaseFont); attributes.removeValue(forKey: .scribeScriptRenderedFont)
        attributes.removeValue(forKey: .baselineOffset)
        guard level != 0 else { return }
        attributes[.scribeScriptLevel] = level
        let rendered = NSFontManager.shared.convert(font, toSize: font.pointSize * 0.65)
        attributes[.font] = rendered
        attributes[.scribeScriptBaseFont] = font; attributes[.scribeScriptRenderedFont] = rendered
        attributes[.baselineOffset] = font.pointSize * (level > 0 ? 0.35 : -0.2)
    }
    static func setFont(_ font: NSFont, in attributes: inout [NSAttributedString.Key: Any]) {
        attributes.removeValue(forKey: .scribeScriptBaseFont); attributes.removeValue(forKey: .scribeScriptRenderedFont)
        attributes[.font] = font; apply(to: &attributes)
    }
    static func external(_ value: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: value)
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
            guard attributes[.scribeScriptBaseFont] != nil, let font = logicalFont(in: attributes) else { return }
            var plain = attributes; plain[.font] = font; plain[.superscript] = level(in: attributes)
            plain.removeValue(forKey: .scribeScriptLevel)
            plain.removeValue(forKey: .scribeScriptBaseFont); plain.removeValue(forKey: .scribeScriptRenderedFont)
            plain.removeValue(forKey: .baselineOffset)
            result.setAttributes(plain, range: range)
        }
        return result
    }
}
#endif
