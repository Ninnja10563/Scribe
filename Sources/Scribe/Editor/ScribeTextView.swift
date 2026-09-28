#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class ScribeTextView: NSTextView {
    weak var editor: PaginatedEditor?
    override func paste(_ sender: Any?) {
        // Normalize clipboard paragraphs and exclude unsupported attachments before they enter the model.
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .rtf),
           let value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
           !value.containsAttachments {
            let normalized = AttributedDocument.capture(value, preserving: ScribeDocument())
            replaceSelection(AttributedDocument.render(normalized), action: "Paste")
        } else if let string = pasteboard.string(forType: .string) {
            insertText(string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"), replacementRange: selectedRange())
        }
    }
    func replaceSelection(_ value: NSAttributedString, action: String) {
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: value.string) else { return }
        textStorage?.replaceCharacters(in: range, with: value)
        didChangeText(); setSelectedRange(NSRange(location: range.location + value.length, length: 0))
        undoManager?.setActionName(action)
    }
    @objc func toggleBold(_ sender: Any?) { toggleTrait(.boldFontMask) }
    @objc func toggleItalic(_ sender: Any?) { toggleTrait(.italicFontMask) }
    private func toggleTrait(_ trait: NSFontTraitMask) {
        let range = selectedRange()
        let font = typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 12)
        let remove = NSFontManager.shared.traits(of: font).contains(trait)
        if range.length == 0 {
            typingAttributes[.font] = remove ? NSFontManager.shared.convert(font, toNotHaveTrait: trait) : NSFontManager.shared.convert(font, toHaveTrait: trait)
            return
        }
        transformSelection(action: trait == .boldFontMask ? "Bold" : "Italic") { value in
            value.enumerateAttribute(.font, in: NSRange(location: 0, length: value.length)) { font, range, _ in
                guard let font = font as? NSFont else { return }
                let changed = remove ? NSFontManager.shared.convert(font, toNotHaveTrait: trait) : NSFontManager.shared.convert(font, toHaveTrait: trait)
                value.addAttribute(.font, value: changed, range: range)
            }
        }
    }
    @objc func toggleStrike(_ sender: Any?) { toggleAttribute(.strikethroughStyle) }
    func toggleAttribute(_ key: NSAttributedString.Key) {
        let enabled = (typingAttributes[key] as? Int ?? 0) == 0
        if selectedRange().length == 0 { typingAttributes[key] = enabled ? 1 : 0; return }
        transformSelection(action: "Formatting") { $0.addAttribute(key, value: enabled ? 1 : 0, range: NSRange(location: 0, length: $0.length)) }
    }
    func transformSelection(action: String, _ transform: (NSMutableAttributedString) -> Void) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }
        let value = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        transform(value)
        replaceSelection(value, action: action); setSelectedRange(range)
    }
    @objc func insertPageBreak(_ sender: Any?) { insertText("\n\u{c}", replacementRange: selectedRange()) }
    @objc func insertSpecialCharacter(_ sender: Any?) { NSApp.orderFrontCharacterPalette(sender) }
    override func insertTab(_ sender: Any?) {
        if changeListLevel(by: 1) { return }; super.insertTab(sender)
    }
    override func insertBacktab(_ sender: Any?) {
        if changeListLevel(by: -1) { return }; super.insertBacktab(sender)
    }
    private func changeListLevel(by delta: Int) -> Bool {
        guard let data = typingAttributes[.scribeList] as? Data,
              var list = try? JSONDecoder().decode(ListDescriptor.self, from: data), let editor else { return false }
        list.level = max(0, min(8, list.level + delta))
        editor.applyList(list); return true
    }
}
#endif
