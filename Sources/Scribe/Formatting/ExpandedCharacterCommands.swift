#if canImport(AppKit)
import AppKit
import DocumentCore

/// Only appearance crosses a format-painter operation. Object ownership, links,
/// paragraph IDs, review metadata and comment anchors stay with the destination.
@MainActor enum CharacterAppearance {
    static let keys: [NSAttributedString.Key] = [
        .font, .foregroundColor, .backgroundColor, .underlineStyle, .strikethroughStyle,
        .superscript, .baselineOffset, .scribeScriptLevel, .scribeScriptBaseFont,
        .scribeScriptRenderedFont, .scribeFontFace, .scribeRenderedFace
    ]
    static func extract(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        attributes.filter { keys.contains($0.key) }
    }
    static func replace(in attributes: inout [NSAttributedString.Key: Any], with appearance: [NSAttributedString.Key: Any]) {
        for key in keys { attributes.removeValue(forKey: key) }
        attributes.merge(extract(appearance)) { _, new in new }
    }
}

extension ScribeTextView {
    /// AppKit can contribute its own font-panel command to a contextual submenu.
    func routeFontMenu(_ menu: NSMenu) {
        guard let controller = editor?.owner?.editorController else { return }
        for item in menu.items {
            if item.action == #selector(NSFontManager.orderFrontFontPanel(_:)) {
                item.title = "Font and Formatting Sidebar"
                item.target = controller; item.action = #selector(EditorWindowController.showFonts)
            }
            if let submenu = item.submenu { routeFontMenu(submenu) }
        }
    }
    var currentCharacterAttributes: [NSAttributedString.Key: Any] {
        let range = selectedRange()
        return range.length > 0 && range.location < (textStorage?.length ?? 0)
            ? textStorage!.attributes(at: range.location, effectiveRange: nil) : typingAttributes
    }
    func changeCharacterAppearance(action: String, _ change: ([NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]) {
        if selectedRange().length == 0 { applyTypingAttributes(change(typingAttributes), action: action) }
        else {
            transformSelection(action: action) { value in
                value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
                    value.setAttributes(change(attributes), range: range)
                }
            }
        }
        updateFontPanel()
    }
    func setFontSize(_ size: Double) -> Bool {
        guard size.isFinite, (1...1000).contains(size) else { return false }
        transformLogicalFonts(action: "Font Size") { NSFontManager.shared.convert($0, toSize: CGFloat(size)) }
        return true
    }
    @objc func growFont(_ sender: Any?) { stepFontSize(up: true) }
    @objc func shrinkFont(_ sender: Any?) { stepFontSize(up: false) }
    private func stepFontSize(up: Bool) {
        let sizes: [CGFloat] = [1, 8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72]
        transformLogicalFonts(action: up ? "Increase Font Size" : "Decrease Font Size") { font in
            let size = up ? sizes.first(where: { $0 > font.pointSize }) ?? min(1000, font.pointSize + 10)
                : sizes.last(where: { $0 < font.pointSize }) ?? max(1, font.pointSize - 1)
            return NSFontManager.shared.convert(font, toSize: size)
        }
    }
    func setCharacterColour(_ color: NSColor?, highlight: Bool) {
        changeCharacterAppearance(action: highlight ? "Highlight Colour" : "Text Colour") { attributes in
            var result = attributes
            result[highlight ? .backgroundColor : .foregroundColor] = color
            return result
        }
    }
    @objc func clearCharacterFormatting(_ sender: Any?) {
        let styles = editor?.owner?.model.styles ?? ParagraphStyle.defaults
        changeCharacterAppearance(action: "Clear Character Formatting") { attributes in
            let style = styles.first { $0.id == attributes[.scribeStyle] as? String } ?? .normal
            let appearance = AttributedDocument.attributes(style: style)
            var result = attributes; CharacterAppearance.replace(in: &result, with: appearance)
            return result
        }
    }
    func applyCharacterAppearance(_ appearance: [NSAttributedString.Key: Any]) {
        changeCharacterAppearance(action: "Paste Character Formatting") { attributes in
            var result = attributes; CharacterAppearance.replace(in: &result, with: appearance); return result
        }
    }
    @objc func uppercaseSelection(_ sender: Any?) { changeCase(uppercase: true) }
    @objc func lowercaseSelection(_ sender: Any?) { changeCase(uppercase: false) }
    func changeCase(uppercase: Bool) {
        let selection = selectedRange()
        guard selection.length > 0, let storage = textStorage, NSMaxRange(selection) <= storage.length else { NSSound.beep(); return }
        let original = storage.attributedSubstring(from: selection)
        let result = NSMutableAttributedString(string: "")
        original.enumerateAttributes(in: NSRange(location: 0, length: original.length)) { attributes, range, _ in
            let text = (original.string as NSString).substring(with: range)
            let transformed = attributes[.attachment] == nil ? (uppercase ? text.uppercased() : text.lowercased()) : text
            result.append(NSAttributedString(string: transformed, attributes: attributes))
        }
        guard result.string != original.string else { return }
        replaceSelection(result, action: uppercase ? "Uppercase" : "Lowercase")
        // Case conversion can expand Unicode characters, for example ß → SS.
        setSelectedRange(NSRange(location: selection.location, length: min(result.length, (textStorage?.length ?? 0) - selection.location)))
    }
}
#endif
