#if canImport(AppKit)
import AppKit
import DocumentCore

extension EditorWindowController {
    @objc func pageNumbers() {
        let alert = NSAlert(); alert.messageText = "Page Numbers"
        let position = NSPopUpButton(), format = NSPopUpButton()
        position.addItems(withTitles: ["Top left", "Top centre", "Top right", "Bottom left", "Bottom centre", "Bottom right"])
        format.addItems(withTitles: ["1, 2, 3", "i, ii, iii", "Page 1", "Page 1 of 10"])
        let current = fileDocument.model.sections[0].pageNumbering ?? PageNumbering()
        position.selectItem(at: PageNumbering.Position.allCases.firstIndex(of: current.position)!)
        format.selectItem(at: PageNumbering.Format.allCases.firstIndex(of: current.format)!)
        let start = NSTextField(string: String(current.start)); start.setAccessibilityLabel("Starting page number")
        let stack = NSStackView(views: [position, format, NSTextField(labelWithString: "Start at"), start])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8; stack.frame = NSRect(x: 0, y: 0, width: 260, height: 120)
        alert.accessoryView = stack; alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Remove")
        let response = alert.runModal()
        if response == .alertThirdButtonReturn { fileDocument.performEdit("Remove Page Numbers") { $0.sections[0].pageNumbering = nil }; return }
        guard response == .alertFirstButtonReturn, let number = Int(start.stringValue), (1...1_000_000).contains(number) else { return }
        let numbering = PageNumbering(position: PageNumbering.Position.allCases[position.indexOfSelectedItem], format: PageNumbering.Format.allCases[format.indexOfSelectedItem], start: number)
        fileDocument.performEdit("Page Numbers") { $0.sections[0].pageNumbering = numbering }
    }
    @objc func insertLink() {
        let view = editor.activeTextView; let selection = view.selectedRange()
        let alert = NSAlert(); alert.messageText = "Insert Hyperlink"
        let url = NSTextField(string: "https://"), title = NSTextField(string: selection.length > 0 ? (editor.storage.string as NSString).substring(with: selection) : "Link text")
        let stack = NSStackView(views: [NSTextField(labelWithString: "Text"), title, NSTextField(labelWithString: "Web or email address"), url])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        for field in [url, title] { field.widthAnchor.constraint(equalToConstant: 320).isActive = true }
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 110); alert.accessoryView = stack
        alert.addButton(withTitle: "Insert"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let link = URL(string: url.stringValue), ["https", "http", "mailto"].contains(link.scheme?.lowercased() ?? ""), !title.stringValue.isEmpty else { return }
        var attributes = view.typingAttributes; attributes[.link] = link
        view.setSelectedRange(selection); view.replaceSelection(NSAttributedString(string: title.stringValue, attributes: attributes), action: "Insert Link")
    }
    @objc func paragraphSettings() {
        let view = editor.activeTextView
        let current = view.typingAttributes[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle.default
        let values = [current.lineSpacing, current.paragraphSpacingBefore, current.paragraphSpacing, current.firstLineHeadIndent, current.headIndent, -current.tailIndent]
        let labels = ["Additional line spacing", "Space before", "Space after", "First line indent", "Left indent", "Right indent"]
        let fields = values.map { NSTextField(string: String(format: "%.1f", $0)) }
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        for (label, field) in zip(labels, fields) {
            field.setAccessibilityLabel(label); field.widthAnchor.constraint(equalToConstant: 90).isActive = true
            stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: label), field]))
        }
        let alert = NSAlert(); alert.messageText = "Paragraph Spacing and Indents"; alert.informativeText = "Measurements are in points. A first-line indent smaller than the left indent creates a hanging indent."
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 200); alert.accessoryView = stack
        alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        while !isClosing, alert.runModal() == .alertFirstButtonReturn {
            do {
                let numbers = fields.compactMap { Double($0.stringValue) }
                try applyParagraphGeometry(numbers); return
            } catch { alert.informativeText = error.localizedDescription }
        }
    }
    func applyParagraphGeometry(_ numbers: [Double]) throws {
        guard numbers.count == 6, numbers.allSatisfy({ $0.isFinite && (0...4000).contains($0) }), max(numbers[3], numbers[4]) + numbers[5] < editor.canvas.pageSettings.contentWidth - 30 else {
            throw DocumentError.invalid("enter non-negative spacing and indents that leave at least 30 points of writing width")
        }
        let indices = editor.selectedParagraphIndices()
        fileDocument.performEdit("Paragraph Formatting") { model in
            for index in indices where model.sections[0].paragraphs.indices.contains(index) {
                let paragraph = model.sections[0].paragraphs[index]
                var format = paragraph.formatting ?? model.style(for: paragraph).paragraph
                format.lineSpacing = numbers[0]; format.spaceBefore = numbers[1]; format.spaceAfter = numbers[2]
                format.firstLineIndent = numbers[3]; format.headIndent = numbers[4]; format.tailIndent = numbers[5]
                model.sections[0].paragraphs[index].formatting = format
            }
        }
    }
}
#endif
