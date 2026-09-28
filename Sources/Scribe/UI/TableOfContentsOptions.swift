#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum TableOfContentsOptions {
    static func show(_ definition: DocumentTOC, inserting: Bool) -> DocumentTOC? {
        let alert = NSAlert(); alert.messageText = inserting ? "Insert Table of Contents" : "Table of Contents Options"
        alert.informativeText = (inserting ? "Insert after the current paragraph. " : "Refresh this table with the new options. ") + "Update Tables refreshes generated entries from heading styles and page layout. Keep your own notes outside the generated entries."
        let title = NSTextField(string: definition.title), levels = NSPopUpButton()
        title.setAccessibilityLabel("Contents title"); levels.setAccessibilityLabel("Heading levels")
        levels.addItems(withTitles: (1...9).map { $0 == 1 ? "Heading 1 only" : "Heading levels 1–\($0)" })
        levels.selectItem(at: definition.maximumLevel - 1)
        let stack = NSStackView(views: [NSTextField(labelWithString: "Title (optional)"), title, levels])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        title.widthAnchor.constraint(equalToConstant: 320).isActive = true
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 85); alert.accessoryView = stack
        alert.addButton(withTitle: inserting ? "Insert" : "Apply"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        var result = definition; result.title = title.stringValue; result.maximumLevel = levels.indexOfSelectedItem + 1
        return result
    }
}
#endif
