#if canImport(AppKit)
import AppKit
import DocumentCore

extension EditorWindowController {
    @objc func insertTableOfContents() {
        let alert = NSAlert(); alert.messageText = "Insert Table of Contents"
        alert.informativeText = "Insert after the current paragraph. Update Table refreshes generated entries from heading styles and page layout. Keep your own notes outside the generated entries."
        let title = NSTextField(string: "Contents"), levels = NSPopUpButton()
        title.setAccessibilityLabel("Contents title"); levels.setAccessibilityLabel("Heading levels")
        levels.addItems(withTitles: (1...9).map { $0 == 1 ? "Heading 1 only" : "Heading levels 1–\($0)" }); levels.selectItem(at: 2)
        let stack = NSStackView(views: [NSTextField(labelWithString: "Title (optional)"), title, levels])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        title.widthAnchor.constraint(equalToConstant: 320).isActive = true
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 85); alert.accessoryView = stack
        alert.addButton(withTitle: "Insert"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        addTableOfContents(title: title.stringValue, maximumLevel: levels.indexOfSelectedItem + 1)
    }

    func addTableOfContents(title: String, maximumLevel: Int) {
        let model = fileDocument.snapshot(), range = editor.activeTextView.selectedRange()
        let id: UUID?
        if range.location < editor.storage.length {
            id = (editor.storage.attribute(.scribeParagraphID, at: range.location, effectiveRange: nil) as? String).flatMap(UUID.init(uuidString:))
        } else { id = model.paragraphs.last?.id }
        guard let id else { return }
        let undo = fileDocument.undoManager; undo?.beginUndoGrouping()
        var inserted: UUID?
        fileDocument.performEdit("Insert Table of Contents") { inserted = $0.insertTableOfContents(after: id, title: title, maximumLevel: maximumLevel) }
        updateContentsPages()
        undo?.endUndoGrouping(); undo?.setActionName("Insert Table of Contents")
        if let inserted, let title = fileDocument.model.paragraphs.first(where: { $0.toc?.tableID == inserted }) { editor.jump(to: title.id) }
    }

    @objc func updateTableOfContents() {
        guard !fileDocument.snapshot().tablesOfContents.isEmpty else { showStatus("Insert a table of contents first."); return }
        let undo = fileDocument.undoManager; undo?.beginUndoGrouping()
        updateContentsPages()
        undo?.endUndoGrouping(); undo?.setActionName("Update Table of Contents")
    }

    @objc func removeTableOfContents() {
        let model = fileDocument.snapshot(), range = editor.activeTextView.selectedRange()
        guard range.location < editor.storage.length,
              let paragraphID = editor.storage.attribute(.scribeParagraphID, at: range.location, effectiveRange: nil) as? String,
              let entry = model.paragraphs.first(where: { $0.id.uuidString == paragraphID })?.toc,
              model.tablesOfContents.contains(where: { $0.id == entry.tableID }) else { showStatus("Place the cursor in the table of contents to remove it."); return }
        fileDocument.performEdit("Remove Table of Contents") { $0.removeTableOfContents(id: entry.tableID) }
    }

    private func updateContentsPages() {
        // Cached page labels can change layout. Repeat until the actual heading pages
        // settle; the whole update remains a single undoable operation.
        for _ in 0..<6 {
            editor.paginate()
            let model = fileDocument.snapshot(), before = contentsPageLabels(model)
            let ids = model.tablesOfContents.map(\.id)
            fileDocument.performEdit("Update Table of Contents") { value in
                for id in ids { value.refreshTableOfContents(id: id, pages: before) }
            }
            editor.paginate()
            if contentsPageLabels(fileDocument.snapshot()) == before { showStatus("Table of contents updated."); return }
        }
        showStatus("Contents refreshed; page numbers need another Update Table after layout settles.")
    }

    func contentsPageLabels(_ model: ScribeDocument) -> [UUID: String] {
        let headings = Set(model.outline.map(\.id)); var result: [UUID: String] = [:]
        let numbering = model.sections[0].pageNumbering ?? PageNumbering(format: .decimal)
        let labels = PageNumbering(format: numbering.format == .roman ? .roman : .decimal, start: numbering.start)
        editor.storage.enumerateAttribute(.scribeParagraphID, in: NSRange(location: 0, length: editor.storage.length)) { value, range, _ in
            guard let value = value as? String, let id = UUID(uuidString: value), headings.contains(id), result[id] == nil else { return }
            let location = editor.navigationLocation(in: range)
            guard location < editor.storage.length else { return }
            let glyph = editor.layout.glyphIndexForCharacter(at: location)
            guard glyph < editor.layout.numberOfGlyphs,
                  let container = editor.layout.textContainer(forGlyphAt: glyph, effectiveRange: nil),
                  let page = editor.layout.textContainers.firstIndex(where: { $0 === container }) else { return }
            result[id] = labels.label(pageIndex: page, pageCount: editor.textViews.count)
        }
        if let last = model.paragraphs.last, last.text.isEmpty, headings.contains(last.id),
           let container = editor.layout.extraLineFragmentTextContainer,
           let page = editor.layout.textContainers.firstIndex(where: { $0 === container }) {
            result[last.id] = labels.label(pageIndex: page, pageCount: editor.textViews.count)
        }
        return result
    }
}
#endif
