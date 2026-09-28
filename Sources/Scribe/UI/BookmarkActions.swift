#if canImport(AppKit)
import AppKit
import DocumentCore

extension EditorWindowController {
    @objc func insertBookmark() {
        let model = fileDocument.snapshot(), selection = editor.activeTextView.selectedRange()
        guard let anchor = CommentProjection.anchor(for: selection, in: editor.storage, document: model) else { return }
        let name = NSTextField(string: ""); name.placeholderString = "Research_notes"; name.setAccessibilityLabel("Bookmark name")
        name.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        let alert = NSAlert(); alert.messageText = "Bookmark This Paragraph"
        alert.informativeText = "A bookmark follows this paragraph when its text changes. Use up to 40 letters, digits or underscores, starting with a letter. Names must be unique."
        alert.accessoryView = name; alert.addButton(withTitle: "Add Bookmark"); alert.addButton(withTitle: "Cancel")
        while alert.runModal() == .alertFirstButtonReturn {
            if addBookmark(named: name.stringValue, paragraphID: anchor.paragraphID) { return }
            alert.informativeText = "Choose a unique name starting with a letter, using letters, digits or underscores (40 characters maximum). The Scribe_ prefix is reserved."
        }
    }

    @discardableResult func addBookmark(named name: String, paragraphID: UUID) -> Bool {
        var added = false
        fileDocument.performEdit("Add Bookmark") { added = $0.addParagraphBookmark(name: name, paragraphID: paragraphID) != nil }
        if added { showStatus("Bookmark added: \(name)") }
        return added
    }

    @objc func manageBookmarks() {
        let model = fileDocument.snapshot()
        guard !model.bookmarks.isEmpty else { showStatus("Use Insert → Bookmark This Paragraph to add a named destination."); return }
        let selection = editor.activeTextView.selectedRange()
        let bookmarks = model.bookmarks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let targets = NSPopUpButton(); targets.menu = NSMenu(); targets.setAccessibilityLabel("Bookmark")
        let ids = Set(model.paragraphs.map(\.id))
        for bookmark in bookmarks {
            targets.menu?.addItem(NSMenuItem(title: bookmark.name + (ids.contains(bookmark.anchor.paragraphID) ? "" : " — missing paragraph"), action: nil, keyEquivalent: ""))
        }
        targets.selectItem(at: 0)
        let action = NSPopUpButton(); action.addItems(withTitles: ["Go to Bookmark", "Insert Link", "Rename Bookmark", "Delete Bookmark"]); action.setAccessibilityLabel("Bookmark action")
        let text = NSTextField(string: ""); text.placeholderString = "New name or link text"; text.setAccessibilityLabel("New bookmark name or link text")
        let stack = NSStackView(views: [targets, action, NSTextField(labelWithString: "New name / link text (optional for links)"), text])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        for control in [targets as NSView, action, text] { control.widthAnchor.constraint(equalToConstant: 340).isActive = true }
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 120)
        let alert = NSAlert(); alert.messageText = "Bookmarks"; alert.accessoryView = stack
        alert.informativeText = "Bookmarks identify paragraph starts. Renaming preserves links. A deleted paragraph remains listed as missing until restored or its bookmark is deleted."
        alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        while alert.runModal() == .alertFirstButtonReturn {
            guard bookmarks.indices.contains(targets.indexOfSelectedItem) else { return }
            let bookmark = bookmarks[targets.indexOfSelectedItem]
            switch action.indexOfSelectedItem {
            case 0:
                if !editor.jump(to: bookmark.anchor.paragraphID) { showStatus("This bookmark’s paragraph has been deleted.") }
            case 1:
                if !applyBookmarkLink(to: bookmark.id, text: text.stringValue.isEmpty ? bookmark.name : text.stringValue, selection: selection) {
                    alert.informativeText = "This destination is missing. Restore its paragraph before inserting a link."; continue
                }
            case 2:
                guard fileDocument.snapshot().canNameBookmark(text.stringValue, excluding: bookmark.id) else {
                    alert.informativeText = "Enter a unique new name: up to 40 letters, digits or underscores, starting with a letter. The Scribe_ prefix is reserved."; continue
                }
                fileDocument.performEdit("Rename Bookmark") { $0.renameBookmark(id: bookmark.id, name: text.stringValue) }
            case 3: fileDocument.performEdit("Delete Bookmark") { $0.bookmarks.removeAll { $0.id == bookmark.id } }
            default: return
            }
            return
        }
    }

    @discardableResult func applyBookmarkLink(to id: UUID, text: String, selection: NSRange) -> Bool {
        let link = DocumentLink.bookmark(id)
        guard !text.isEmpty, fileDocument.snapshot().destinationParagraphID(for: link) != nil else { return false }
        let view = editor.activeTextView
        var attributes = view.typingAttributes; attributes[.link] = link
        view.setSelectedRange(selection)
        view.replaceSelection(NSAttributedString(string: text, attributes: attributes), action: "Insert Bookmark Link")
        window?.makeFirstResponder(view); return true
    }
}
#endif
