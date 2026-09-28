#if canImport(AppKit)
import AppKit
import DocumentCore

extension EditorWindowController {
    @objc func insertHeadingLink() {
        let headings = fileDocument.snapshot().outline
        guard !headings.isEmpty else {
            let alert = NSAlert(); alert.messageText = "No headings in this document"
            alert.informativeText = "Apply a Heading style to a paragraph, then link to it here."
            alert.runModal(); return
        }
        let view = editor.activeTextView, selection = view.selectedRange()
        let title = NSTextField(string: selection.length > 0 ? editor.semanticText.text(inSourceRange: selection) : "")
        title.placeholderString = "Use heading text"; title.setAccessibilityLabel("Link text")
        let target = NSPopUpButton(); target.menu = NSMenu(); target.setAccessibilityLabel("Destination heading")
        for heading in headings {
            let item = NSMenuItem(title: String(repeating: "    ", count: heading.level - 1) + (heading.title.isEmpty ? "Untitled heading" : heading.title), action: nil, keyEquivalent: "")
            item.representedObject = heading.id; target.menu?.addItem(item)
        }
        target.selectItem(at: 0)
        let stack = NSStackView(views: [NSTextField(labelWithString: "Destination"), target, NSTextField(labelWithString: "Link text (optional)"), title])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        for control in [target as NSView, title] { control.widthAnchor.constraint(equalToConstant: 340).isActive = true }
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 115)
        let alert = NSAlert(); alert.messageText = "Link to Heading"; alert.accessoryView = stack
        alert.addButton(withTitle: "Insert Link"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, headings.indices.contains(target.indexOfSelectedItem) else { return }
        let heading = headings[target.indexOfSelectedItem]
        applyHeadingLink(to: heading.id, text: title.stringValue.isEmpty ? heading.title : title.stringValue, selection: selection)
    }

    func applyHeadingLink(to id: UUID, text: String, selection: NSRange) {
        guard !text.isEmpty, fileDocument.snapshot().paragraphs.contains(where: { $0.id == id }) else { return }
        let view = editor.activeTextView
        var attributes = view.typingAttributes; attributes[.link] = DocumentLink.paragraph(id)
        view.setSelectedRange(selection)
        view.replaceSelection(NSAttributedString(string: text, attributes: attributes), action: "Insert Heading Link")
        window?.makeFirstResponder(view)
    }
}
#endif
