#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class ScribeTextView: NSTextView {
    weak var editor: PaginatedEditor?
    private(set) var spellingTask: Task<Void, Never>?
    override func superscript(_ sender: Any?) { setScriptLevel(1) }
    override func `subscript`(_ sender: Any?) { setScriptLevel(-1) }
    override func unscript(_ sender: Any?) { setScriptLevel(0) }
    override func changeFont(_ sender: Any?) {
        let manager = sender as? NSFontManager ?? NSFontManager.shared
        transformLogicalFonts(action: "Font") { manager.convert($0) }
    }
    override func updateRuler() { editor?.paragraphRuler?.refresh() }
    override func updateFontPanel() {
        super.updateFontPanel()
        let range = selectedRange()
        let attributes = range.length > 0 && range.location < (textStorage?.length ?? 0) ? textStorage!.attributes(at: range.location, effectiveRange: nil) : typingAttributes
        guard usesFontPanel, let font = ScriptProjection.logicalFont(in: attributes) else { return }
        var multiple = false
        if range.length > 0, let textStorage, NSMaxRange(range) <= textStorage.length {
            textStorage.enumerateAttributes(in: range) { attributes, _, stop in
                if let other = ScriptProjection.logicalFont(in: attributes), other != font { multiple = true; stop.pointee = true }
            }
        }
        NSFontManager.shared.setSelectedFont(font, isMultiple: multiple)
    }
    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
        guard let textStorage, range.location >= 0, range.length >= 0,
              range.location <= textStorage.length, range.length <= textStorage.length - range.location,
              let native = super.accessibilityAttributedString(for: range) else { return nil }
        guard native.length == range.length else { return native }
        let result = NSMutableAttributedString(attributedString: native)
        textStorage.enumerateAttribute(.scribeScriptLevel, in: range) { value, subrange, _ in
            guard let level = value as? Int else { return }
            result.addAttribute(.accessibilitySuperscript, value: level, range: NSRange(location: subrange.location - range.location, length: subrange.length))
        }
        return result
    }
    override func checkSpelling(_ sender: Any?) {
        spellingTask?.cancel()
        spellingTask = Task { [weak self] in
            guard let self else { return }
            await DocumentSpelling.findNext(in: self)
        }
    }
    func cancelSpellingCheck() { spellingTask?.cancel(); spellingTask = nil }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { editor?.rememberSelection(self) }
        return accepted
    }
    override func draw(_ dirtyRect: NSRect) { super.draw(dirtyRect); drawImageSelection() }
    override func mouseDown(with event: NSEvent) { if !resizeImageIfNeeded(with: event) { super.mouseDown(with: event) } }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        for key in [NSAttributedString.Key.attachment, .scribeEquation, .scribeImage] { typingAttributes.removeValue(forKey: key) }
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        let ids = commentIDs(forReplacement: range)
        if ids.isEmpty { typingAttributes.removeValue(forKey: .scribeComments) }
        else { typingAttributes[.scribeComments] = ids }
        if let attributed = insertString as? NSAttributedString {
            let value = NSMutableAttributedString(attributedString: attributed)
            value.removeAttribute(.scribeComments, range: NSRange(location: 0, length: value.length))
            if !ids.isEmpty { value.addAttribute(.scribeComments, value: ids, range: NSRange(location: 0, length: value.length)) }
            super.insertText(value, replacementRange: replacementRange)
        } else { super.insertText(insertString, replacementRange: replacementRange) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if selectedRange().location < (textStorage?.length ?? 0), textStorage?.attribute(.scribeEquation, at: selectedRange().location, effectiveRange: nil) != nil {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Edit Equation…", action: #selector(EditorWindowController.editEquation), keyEquivalent: ""))
        }
        if selectedImageFrame != nil {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Image Properties…", action: #selector(EditorWindowController.imageProperties), keyEquivalent: ""))
        }
        menu.addItem(.separator()); menu.addItem(NSMenuItem(title: "Add Comment…", action: #selector(EditorWindowController.addComment), keyEquivalent: ""))
        return menu
    }
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = super.writablePasteboardTypes
        if isRichText, selectedRange().length > 0, !types.contains(.rtfd) { types.insert(.rtfd, at: 0) }
        if isRichText, selectedRange().length > 0 { types.insert(InlineObjectClipboard.type, at: 0) }
        return types
    }
    override func writeSelection(to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == InlineObjectClipboard.type, let textStorage {
            do { return pasteboard.setData(try InlineObjectClipboard.encode(textStorage.attributedSubstring(from: selectedRange())), forType: type) }
            catch { presentError(error); return false }
        }
        // AppKit still requests pre-UTI names during ordinary Copy.
        let richImages = type == .rtfd || type.rawValue == "NeXT RTFD pasteboard type"
        let richText = type == .rtf || type.rawValue == "NeXT Rich Text Format v1.0 pasteboard type"
        guard richImages || richText, let textStorage else { return super.writeSelection(to: pasteboard, type: type) }
        do {
            let value = try ExternalTextProjection.render(textStorage.attributedSubstring(from: selectedRange()), includeImages: richImages)
            let data = try value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: richImages ? NSAttributedString.DocumentType.rtfd : .rtf])
            return pasteboard.setData(data, forType: type)
        } catch { presentError(error); return false }
    }
    override func paste(_ sender: Any?) {
        // Normalize clipboard paragraphs and exclude unsupported attachments before they enter the model.
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .rtfd),
           let value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil) {
            let restored = pasteboard.data(forType: InlineObjectClipboard.type).flatMap { try? InlineObjectClipboard.restore($0, in: value) } ?? value
            let normalized = AttributedDocument.capture(restored, preserving: ScribeDocument())
            replaceSelection(AttributedDocument.render(normalized), action: "Paste"); return
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            do { try insertImageData(data) } catch { presentError(error) }; return
        }
        if let data = pasteboard.data(forType: .rtf),
           let value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
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
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if imageURL(from: sender.draggingPasteboard) != nil { return .copy }
        return super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = imageURL(from: sender.draggingPasteboard) {
            let point = convert(sender.draggingLocation, from: nil)
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
            do { try insertImageData(Data(contentsOf: url), altText: url.deletingPathExtension().lastPathComponent); return true }
            catch { presentError(error); return false }
        }
        return super.performDragOperation(sender)
    }
    private func imageURL(from pasteboard: NSPasteboard) -> URL? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first, ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }
    @objc func toggleBold(_ sender: Any?) { toggleTrait(.boldFontMask) }
    @objc func toggleItalic(_ sender: Any?) { toggleTrait(.italicFontMask) }
    private func toggleTrait(_ trait: NSFontTraitMask) {
        let range = selectedRange()
        let attributes = range.length > 0 && range.location < (textStorage?.length ?? 0) ? textStorage!.attributes(at: range.location, effectiveRange: nil) : typingAttributes
        let font = ScriptProjection.logicalFont(in: attributes) ?? NSFont.systemFont(ofSize: 12)
        let remove = NSFontManager.shared.traits(of: font).contains(trait)
        transformLogicalFonts(action: trait == .boldFontMask ? "Bold" : "Italic") { font in
            remove ? NSFontManager.shared.convert(font, toNotHaveTrait: trait) : NSFontManager.shared.convert(font, toHaveTrait: trait)
        }
    }
    @objc func toggleHighlight(_ sender: Any?) {
        let color = NSColor(srgbRed: 1, green: 0.92, blue: 0.5, alpha: 1)
        let enabled = typingAttributes[.backgroundColor] == nil
        if selectedRange().length == 0 {
            var attributes = typingAttributes
            if enabled { attributes[.backgroundColor] = color } else { attributes.removeValue(forKey: .backgroundColor) }
            applyTypingAttributes(attributes, action: "Highlight")
        } else {
            transformSelection(action: "Highlight") { value in
                let range = NSRange(location: 0, length: value.length)
                if enabled { value.addAttribute(.backgroundColor, value: color, range: range) } else { value.removeAttribute(.backgroundColor, range: range) }
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
        let original = storage.attributedSubstring(from: range)
        let value = NSMutableAttributedString(attributedString: original)
        transform(value)
        guard !value.isEqual(to: original) else { return }
        replaceSelection(value, action: action); setSelectedRange(range)
    }
    @objc func insertPageBreak(_ sender: Any?) { insertText("\u{c}", replacementRange: selectedRange()) }
    @objc func insertSpecialCharacter(_ sender: Any?) { NSApp.orderFrontCharacterPalette(sender) }
    override func insertNewline(_ sender: Any?) { if !insertListNewline() { super.insertNewline(sender) } }
    override func deleteBackward(_ sender: Any?) { if !removeListAtStart() { super.deleteBackward(sender) } }
    override func insertTab(_ sender: Any?) {
        if moveTableCell(by: 1) { return }
        if changeListLevel(by: 1) { return }; super.insertTab(sender)
    }
    override func insertBacktab(_ sender: Any?) {
        if moveTableCell(by: -1) { return }
        if changeListLevel(by: -1) { return }; super.insertBacktab(sender)
    }
    private func moveTableCell(by delta: Int) -> Bool {
        guard let editor, let storage = textStorage, storage.length > 0 else { return false }
        let attributes = storage.attributes(at: min(selectedRange().location, storage.length - 1), effectiveRange: nil)
        guard let data = attributes[.scribeCell] as? Data, let cell = try? JSONDecoder().decode(TableCellReference.self, from: data),
              let table = editor.owner?.model.tables.first(where: { $0.id == cell.tableID }) else { return false }
        let cells = table.cellAnchors
        guard let current = cells.firstIndex(of: cell) else { return false }
        let target = current + delta
        if target >= cells.count {
            editor.owner?.performEdit("Add Table Row") { $0.addTableRow(tableID: table.id, after: table.rows - 1) }
        }
        guard target >= 0 else { return true }
        guard let updated = editor.owner?.model.tables.first(where: { $0.id == table.id }), target < updated.cellAnchors.count else { return true }
        let reference = updated.cellAnchors[target]
        storage.enumerateAttribute(.scribeCell, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if let data = value as? Data, let current = try? JSONDecoder().decode(TableCellReference.self, from: data), current == reference {
                editor.select(NSRange(location: range.location, length: 0)); stop.pointee = true
            }
        }
        return true
    }
    private func changeListLevel(by delta: Int) -> Bool {
        guard let data = typingAttributes[.scribeList] as? Data,
              var list = try? JSONDecoder().decode(ListDescriptor.self, from: data), let editor else { return false }
        list.level = max(0, min(8, list.level + delta))
        editor.applyList(list); return true
    }
}
#endif
