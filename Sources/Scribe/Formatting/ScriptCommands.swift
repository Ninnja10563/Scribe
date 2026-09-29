#if canImport(AppKit)
import AppKit

extension ScribeTextView {
    func setScriptLevel(_ level: Int) {
        let name = level > 0 ? "Superscript" : level < 0 ? "Subscript" : "Normal Baseline"
        if selectedRange().length == 0 {
            var attributes = typingAttributes; attributes[.superscript] = level
            ScriptProjection.apply(to: &attributes); typingAttributes = attributes
        } else {
            transformSelection(action: name) { value in
                value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { existing, range, _ in
                    var attributes = existing; attributes[.superscript] = level
                    ScriptProjection.apply(to: &attributes); value.setAttributes(attributes, range: range)
                }
            }
        }
        updateFontPanel()
    }
    func transformLogicalFonts(action: String, transform: @escaping (NSFont) -> NSFont) {
        if selectedRange().length == 0 {
            var attributes = typingAttributes
            guard let font = ScriptProjection.logicalFont(in: attributes) else { return }
            ScriptProjection.setFont(transform(font), in: &attributes); typingAttributes = attributes
        } else {
            transformSelection(action: action) { value in
                value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { existing, range, _ in
                    guard let font = ScriptProjection.logicalFont(in: existing) else { return }
                    var attributes = existing; ScriptProjection.setFont(transform(font), in: &attributes)
                    value.setAttributes(attributes, range: range)
                }
            }
        }
        updateFontPanel()
    }
}
#endif
