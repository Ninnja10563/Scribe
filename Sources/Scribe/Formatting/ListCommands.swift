#if canImport(AppKit)
import AppKit
import DocumentCore

extension ScribeTextView {
    /// Generated markers are not part of the semantic paragraph text.
    func listContext(for supplied: NSRange? = nil) -> (index: Int, start: Int, contentStart: Int, end: Int)? {
        guard let storage = textStorage else { return nil }
        let text = storage.string as NSString, selection = supplied ?? selectedRange()
        guard selection.location <= text.length else { return nil }
        let prefix = text.substring(to: selection.location)
        let index = prefix.components(separatedBy: "\n").count - 1
        let start = (prefix as NSString).range(of: "\n", options: .backwards)
        let location = start.location == NSNotFound ? 0 : NSMaxRange(start)
        let remaining = text.substring(from: location) as NSString
        let newline = remaining.range(of: "\n")
        let end = newline.location == NSNotFound ? text.length : location + newline.location
        var contentStart = location
        if contentStart < end, text.character(at: contentStart) == 12 { contentStart += 1 }
        if contentStart < end, text.character(at: contentStart) == 9 {
            let afterTab = NSRange(location: contentStart + 1, length: end - contentStart - 1)
            let tab = text.range(of: "\t", options: [], range: afterTab)
            if tab.location != NSNotFound { contentStart = NSMaxRange(tab) }
        }
        return (index, location, contentStart, end)
    }
    func insertListNewline() -> Bool {
        guard !hasMarkedText(), let editor, let owner = editor.owner, let context = listContext() else { return false }
        let model = owner.snapshot(), paragraphs = model.paragraphs, selection = selectedRange()
        guard paragraphs.indices.contains(context.index), paragraphs[context.index].list != nil,
              selection.location >= context.contentStart, NSMaxRange(selection) <= context.end else { return false }
        let id = paragraphs[context.index].id
        let range = NSRange(location: selection.location - context.contentStart, length: selection.length)
        if let author = editor.reviewEditing.author {
            do {
                var updated = model
                let target = try updated.splitTrackedListItem(id: id, range: range, author: author)
                owner.applyReviewedStructure(updated, replacing: model, name: "New List Item")
                editor.reviewEditing.resetGrouping(); editor.selectListContent(id: target)
            } catch { NSApp.presentError(error) }
            return true
        }
        var target: UUID?
        owner.performEdit("New List Item") { target = $0.splitListItem(id: id, range: range) }
        if let target { editor.selectListContent(id: target) }
        return true
    }
    func removeListAtStart() -> Bool {
        guard !hasMarkedText(), selectedRange().length == 0, let editor, let owner = editor.owner,
              let context = listContext(), selectedRange().location == context.contentStart else { return false }
        let paragraphs = owner.snapshot().paragraphs
        guard paragraphs.indices.contains(context.index), var list = paragraphs[context.index].list else { return false }
        list.level -= 1; list.restart = nil
        owner.performEdit("Outdent List") { $0.sections[0].paragraphs[context.index].list = list.level < 0 ? nil : list }
        editor.selectListContent(id: paragraphs[context.index].id)
        return true
    }
}
extension PaginatedEditor {
    func selectListContent(id: UUID) {
        jump(to: id)
        if let context = activeTextView.listContext() { select(NSRange(location: context.contentStart, length: 0)) }
    }
}
extension EditorWindowController {
    @objc func listSettings() {
        let view = editor.activeTextView
        guard let context = view.listContext() else { return }
        let paragraphs = fileDocument.snapshot().paragraphs
        guard paragraphs.indices.contains(context.index) else { return }
        let existing = paragraphs[context.index].list ?? ListDescriptor(kind: .decimal)
        let kinds: [ListDescriptor.Kind] = [.bullet, .decimal, .lowerAlpha, .upperAlpha, .lowerRoman, .upperRoman]
        let format = NSPopUpButton(); format.addItems(withTitles: ["Bullets", "1, 2, 3", "a, b, c", "A, B, C", "i, ii, iii", "I, II, III"])
        format.selectItem(at: kinds.firstIndex(of: existing.kind)!)
        let level = NSTextField(string: String(existing.level + 1)), start = NSTextField(string: String(existing.start))
        let restart = NSButton(checkboxWithTitle: "Restart numbering at selection", target: nil, action: nil)
        restart.state = existing.restart == true ? .on : .off
        let stack = NSStackView(views: [format, NSTextField(labelWithString: "Nesting level (1–9)"), level, NSTextField(labelWithString: "Starting number"), start, restart])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: 185)
        level.setAccessibilityLabel("Nesting level"); start.setAccessibilityLabel("Starting number")
        let alert = NSAlert(); alert.messageText = "List Options"; alert.accessoryView = stack
        alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Remove List")
        let result = alert.runModal()
        if result == .alertThirdButtonReturn { editor.applyList(nil); return }
        guard result == .alertFirstButtonReturn, let depth = Int(level.stringValue), (1...9).contains(depth),
              let number = Int(start.stringValue), (1...1_000_000).contains(number) else { return }
        editor.applyList(.init(kind: kinds[format.indexOfSelectedItem], level: depth - 1, start: number,
                               seriesID: existing.seriesID, restart: restart.state == .on ? true : nil))
    }
    @objc func continueList() {
        guard let context = editor.activeTextView.listContext(), context.index > 0 else { return }
        let paragraphs = fileDocument.snapshot().paragraphs
        guard paragraphs.indices.contains(context.index), let previous = paragraphs[..<context.index].lastIndex(where: { $0.list != nil }),
              var list = paragraphs[previous].list else { return }
        let id = list.seriesID ?? UUID(); list.seriesID = id; list.restart = nil
        fileDocument.performEdit("Continue Numbering") { document in
            // Give the previous contiguous list an identity before crossing intervening body text.
            var index = previous
            while index >= 0, document.sections[0].paragraphs[index].list != nil {
                if document.sections[0].paragraphs[index].list?.seriesID == nil { document.sections[0].paragraphs[index].list?.seriesID = id }
                if index == 0 { break }; index -= 1
            }
            document.sections[0].paragraphs[context.index].list = list
        }
        editor.selectListContent(id: paragraphs[context.index].id)
    }
}
#endif
