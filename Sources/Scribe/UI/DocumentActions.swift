#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
import DocumentCore
import ImportExport

extension EditorWindowController {
    func exportDocument(format: String) {
        guard let window else { return }
        let model = fileDocument.snapshot()
        if ["txt", "md", "docx"].contains(format) {
            let alert = NSAlert(); alert.messageText = "Export a \(format.uppercased()) copy?"
            alert.informativeText = format == "txt" ? "Plain text removes all formatting, page layout, and document metadata. Your Scribe document is kept intact." : "This export preserves supported text formatting. Some Scribe metadata and layout features may not transfer. Your Scribe document is kept intact."
            alert.addButton(withTitle: "Export Copy"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.init(filenameExtension: format) ?? .data]
        panel.nameFieldStringValue = (fileDocument.fileURL?.deletingPathExtension().lastPathComponent ?? model.title) + "." + format
        let pdfOptions: PDFExportAccessory?
        if format == "pdf" {
            editor.paginate()
            let options = PDFExportAccessory(pageCount: editor.textViews.count, title: model.title, author: model.author)
            panel.accessoryView = options; panel.delegate = options; pdfOptions = options
        } else { pdfOptions = nil }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                switch format {
                case "pdf":
                    self.searchBar.close()
                    guard let options = pdfOptions else { return }
                    try PrintRenderer(editor: self.editor).exportPDF(to: url, title: options.title.stringValue, author: options.author.stringValue,
                        pages: options.selectedPages(), subject: options.subject.stringValue,
                        keywords: options.keywords.stringValue.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
                case "docx": try DOCX.encode(model).write(to: url, options: .atomic)
                case "md": try TextFormats.exportMarkdown(model).write(to: url, atomically: true, encoding: .utf8)
                case "rtf":
                    let data = try self.editor.storage.data(from: NSRange(location: 0, length: self.editor.storage.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                    try data.write(to: url, options: .atomic)
                default: try model.plainText.write(to: url, atomically: true, encoding: .utf8)
                }
                self.showStatus("Exported \(url.lastPathComponent)")
            } catch { self.presentError(error) }
        }
    }
    func printDocument() {
        editor.paginate()
        if let warning = editor.layoutWarning { presentError(DocumentError.invalid(warning)); return }
        searchBar.close()
        let p = editor.canvas.pageSettings
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: p.width, height: p.height)
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        let operation = NSPrintOperation(view: PrintRenderer(editor: editor), printInfo: info)
        operation.run()
    }
    @objc func pageSettings() {
        let alert = NSAlert(); alert.messageText = "Page Layout"
        alert.informativeText = "Paper size and margins apply to this document. Measurements are in points (72 points = 1 inch)."
        let size = NSPopUpButton(); size.addItems(withTitles: PageSettings.Paper.allCases.map(\.rawValue))
        let landscape = NSButton(checkboxWithTitle: "Landscape", target: nil, action: nil)
        let current = fileDocument.model.sections[0].page
        landscape.state = current.width > current.height ? .on : .off
        if max(current.width, current.height) > 950 { size.selectItem(at: 2) }
        else if abs(min(current.width, current.height) - 612) < 1 { size.selectItem(at: 1) }
        let margins = [current.top, current.bottom, current.left, current.right].map { NSTextField(string: String(Int($0))) }
        var views: [NSView] = [size, landscape]
        for (name, field) in zip(["Top", "Bottom", "Left", "Right"], margins) {
            field.widthAnchor.constraint(equalToConstant: 90).isActive = true
            views.append(NSStackView(views: [NSTextField(labelWithString: name), field]))
        }
        let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: 210); alert.accessoryView = stack
        alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var settings = PageSettings(paper: PageSettings.Paper.allCases[size.indexOfSelectedItem], landscape: landscape.state == .on)
        let values = margins.compactMap { Double($0.stringValue) }
        guard values.count == 4 else { presentError(DocumentError.invalid("enter numeric margins")); return }
        settings.top = values[0]; settings.bottom = values[1]; settings.left = values[2]; settings.right = values[3]
        guard settings.isValid else { presentError(DocumentError.invalid("margins leave less than one inch of writing space")); return }
        guard fileDocument.model.tables.allSatisfy({ Double($0.columnWidths.count) * 12 <= settings.contentWidth }) else { presentError(DocumentError.invalid("this page is too narrow for the document's tables")); return }
        fileDocument.performEdit("Page Layout") { model in
            model.sections[0].page = settings
            for i in model.tables.indices {
                let total = model.tables[i].columnWidths.reduce(0, +)
                if total > settings.contentWidth { model.tables[i].columnWidths = model.tables[i].columnWidths.map { $0 * settings.contentWidth / total } }
            }
            for p in model.sections[0].paragraphs.indices {
                for r in model.sections[0].paragraphs[p].runs.indices {
                    guard var image = model.sections[0].paragraphs[p].runs[r].image else { continue }
                    let scale = min(1, settings.contentWidth / image.width, (settings.contentHeight - 24) / image.height)
                    image.width *= scale; image.height *= scale
                    model.sections[0].paragraphs[p].runs[r].image = image
                }
            }
        }
    }
    @objc func editHeaderFooter() {
        let alert = NSAlert(); alert.messageText = "Headers and Footers"
        let header = NSTextField(string: fileDocument.model.sections[0].header), footer = NSTextField(string: fileDocument.model.sections[0].footer)
        header.placeholderString = "Header"; footer.placeholderString = "Footer"
        let stack = NSStackView(views: [NSTextField(labelWithString: "Header"), header, NSTextField(labelWithString: "Footer"), footer])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8; stack.frame = NSRect(x: 0, y: 0, width: 320, height: 110)
        header.widthAnchor.constraint(equalToConstant: 320).isActive = true; footer.widthAnchor.constraint(equalToConstant: 320).isActive = true
        alert.accessoryView = stack; alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            fileDocument.performEdit("Headers and Footers") { $0.sections[0].header = header.stringValue; $0.sections[0].footer = footer.stringValue }
        }
    }
    @objc func editStyle() {
        let index = stylePicker.indexOfSelectedItem
        guard fileDocument.model.styles.indices.contains(index) else { return }
        var style = fileDocument.model.styles[index]
        let alert = NSAlert(); alert.messageText = "Modify \(style.name)"
        alert.informativeText = "All paragraphs using this style update together. Direct formatting is preserved."
        let name = NSTextField(string: style.name), family = NSTextField(string: style.text.fontFamily ?? "Helvetica Neue")
        let size = NSTextField(string: String(style.text.fontSize ?? 12))
        let after = NSTextField(string: String(style.paragraph.spaceAfter))
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        for (label, field) in zip(["Name", "Font family", "Font size", "Spacing after"], [name, family, size, after]) {
            field.widthAnchor.constraint(equalToConstant: 180).isActive = true
            stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: label), field]))
        }
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 150); alert.accessoryView = stack
        alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let points = Double(size.stringValue), (1...200).contains(points), let spacing = Double(after.stringValue), (0...200).contains(spacing), !name.stringValue.isEmpty else { return }
        style.name = name.stringValue; style.text.fontFamily = family.stringValue; style.text.fontSize = points; style.paragraph.spaceAfter = spacing
        fileDocument.performEdit("Modify Style") { $0.updateStyle(style) }
    }
    @objc func createStyle() {
        let alert = NSAlert(); alert.messageText = "Create Paragraph Style"
        let name = NSTextField(string: "Custom Style"); name.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = name; alert.addButton(withTitle: "Create"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, !name.stringValue.isEmpty else { return }
        let style = ParagraphStyle(id: UUID().uuidString, name: name.stringValue)
        fileDocument.performEdit("Create Style") { $0.updateStyle(style) }
        editor.applyStyle(style.id)
    }
    @objc func deleteStyle() {
        let index = stylePicker.indexOfSelectedItem; guard fileDocument.model.styles.indices.contains(index) else { return }
        let style = fileDocument.model.styles[index]
        guard !style.isBuiltIn else { NSSound.beep(); return }
        fileDocument.performEdit("Delete Style") { $0.deleteStyle(id: style.id) }
    }
    @objc func documentStatistics() {
        let stats = DocumentStatistics(text: editor.storage.string)
        let alert = NSAlert(); alert.messageText = "Document Statistics"
        alert.informativeText = "\(stats.words.formatted()) words\n\(stats.characters.formatted()) characters\n\(stats.charactersWithoutSpaces.formatted()) characters excluding spaces\n\(stats.paragraphs.formatted()) paragraphs\n\(editor.textViews.count) pages"
        alert.runModal()
    }
}
#endif
