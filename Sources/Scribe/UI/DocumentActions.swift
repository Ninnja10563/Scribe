#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
import DocumentCore
import ImportExport

extension EditorWindowController {
    func exportDocument(format: String) {
        guard let window else { return }
        let model = fileDocument.snapshot()
        if ["txt", "md", "docx"].contains(format) || (format == "rtf" && model.paragraphs.contains { $0.runs.contains { $0.image != nil || $0.equation != nil } }) {
            let alert = NSAlert(); alert.messageText = "Export a \(format.uppercased()) copy?"
            alert.informativeText = format == "txt" ? "Plain text removes all formatting, page layout, and document metadata. Your Scribe document is kept intact." : "This export preserves supported text formatting. Some Scribe metadata and layout features may not transfer. Your Scribe document is kept intact."
            if format == "rtf" { alert.informativeText = "RTF export omits images. Use Word Document or PDF to retain them. Your Scribe document is kept intact." }
            if ["rtf", "txt", "md"].contains(format), model.paragraphs.contains(where: { $0.runs.contains(where: { $0.equation != nil }) }) { alert.informativeText += " Equations are exported as readable mathematical source, without their visual layout." }
            if format == "docx", model.paragraphs.contains(where: { $0.runs.contains(where: { $0.equation != nil }) }) { alert.informativeText += " Equation font sizes and spacing can vary across editors; PDF preserves Scribe’s layout." }
            if format == "docx", model.comments.contains(where: { $0.isDetached == true }) { alert.informativeText += " Detached comments are retained in the package, but other editors may hide them." }
            if format == "docx", model.styles.contains(where: { $0.text.fontFace != nil }) || model.paragraphs.contains(where: { $0.runs.contains(where: { $0.format.fontFace != nil }) }) {
                alert.informativeText += " Specific font faces and intermediate weights may be approximated by their family and bold/italic traits in Word."
            }
            if format == "docx", model.bookmarks.contains(where: { model.destinationParagraphID(for: DocumentLink.bookmark($0.id)) == nil }) {
                alert.informativeText += " Bookmarks with deleted destinations are omitted; their linked text is retained."
            }
            if format == "docx", model.sections.contains(where: { $0.runningContent?.differentOddEvenPages == true && ($0.pageNumbering?.start ?? $0.runningContent?.startingPageNumber ?? 1).isMultiple(of: 2) }) {
                alert.informativeText += " Odd/even headers with an even starting page number can alternate differently in other editors. PDF preserves Scribe's layout."
            }
            alert.addButton(withTitle: "Export Copy"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.init(filenameExtension: format) ?? .data]
        panel.nameFieldStringValue = (fileDocument.fileURL?.deletingPathExtension().lastPathComponent ?? model.title) + "." + format
        let pdfOptions: PDFExportAccessory?
        if format == "pdf" {
            editor.paginate()
            let options = PDFExportAccessory(pageCount: editor.canvas.pageCount, title: model.title, author: model.author)
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
                    let value = try ExternalTextProjection.render(self.editor.storage, includeImages: false)
                    let data = try value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                    try data.write(to: url, options: .atomic)
                default: try model.plainText.write(to: url, atomically: true, encoding: .utf8)
                }
                self.showStatus("Exported \(url.lastPathComponent)")
            } catch { self.presentError(error) }
        }
    }
    func printDocument() {
        editor.paginate()
        if let warning = editor.outputWarning { presentError(DocumentError.invalid(warning)); return }
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
        alert.informativeText = "Measurements are in points (72 points = 1 inch). Choose a preset or enter custom dimensions. Oversized tables and images shrink to fit the new writing area."
        let options = PageLayoutOptions(settings: fileDocument.snapshot().sections[0].page)
        alert.accessoryView = options.view; alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                let settings = try options.settings()
                var updated = fileDocument.snapshot()
                try updated.applyPageLayout(settings, sectionID: updated.sections[0].id)
                fileDocument.performEdit("Page Layout") { $0 = updated }
                return
            } catch { alert.informativeText = error.localizedDescription }
        }
    }
    @objc func editHeaderFooter() {
        let alert = NSAlert(); alert.messageText = "Headers and Footers"
        let options = RunningContentOptions(section: fileDocument.snapshot().sections[0])
        alert.accessoryView = options.view; alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            fileDocument.performEdit("Headers and Footers") { options.apply(to: &$0.sections[0]) }
        }
    }

    @objc func deleteStyle() {
        let index = stylePicker.indexOfSelectedItem; guard fileDocument.model.styles.indices.contains(index) else { return }
        let style = fileDocument.model.styles[index]
        guard !style.isBuiltIn else { NSSound.beep(); return }
        fileDocument.performEdit("Delete Style") { $0.deleteStyle(id: style.id) }
    }
    @objc func documentStatistics() {
        let stats = DocumentStatistics(text: editor.semanticText.statisticsText)
        let alert = NSAlert(); alert.messageText = "Document Statistics"
        alert.informativeText = "\(stats.words.formatted()) words\n\(stats.characters.formatted()) characters\n\(stats.charactersWithoutSpaces.formatted()) characters excluding spaces\n\(stats.paragraphs.formatted()) paragraphs\n\(editor.canvas.pageCount) pages"
        if editor.semanticText.statisticsText != editor.semanticText.text { alert.informativeText += "\n\nIncludes footnotes and endnotes." }
        alert.runModal()
    }
}
#endif
