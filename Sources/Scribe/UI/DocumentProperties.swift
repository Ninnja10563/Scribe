#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class DocumentPropertiesOptions {
    let title: NSTextField
    let author: NSTextField
    let language = NSPopUpButton()
    let view: NSGridView
    private(set) var identifiers: [String] = []
    init(document: ScribeDocument) {
        title = NSTextField(string: document.title); author = NSTextField(string: document.author)
        title.identifier = NSUserInterfaceItemIdentifier("document-title"); author.identifier = NSUserInterfaceItemIdentifier("document-author")
        let installed = Set(NSSpellChecker.shared.availableLanguages.compactMap { try? DocumentMetadata.languageIdentifier($0) })
        identifiers = ["und"] + installed.sorted { DocumentSpelling.label(for: $0).localizedStandardCompare(DocumentSpelling.label(for: $1)) == .orderedAscending }
        if !identifiers.contains(document.language) { identifiers.append(document.language) }
        language.addItems(withTitles: identifiers.map { id in
            DocumentSpelling.label(for: id) + (id == "und" || installed.contains(id) ? "" : " (dictionary unavailable)")
        })
        language.selectItem(at: identifiers.firstIndex(of: document.language) ?? 0)
        for (index, id) in identifiers.enumerated() { language.item(at: index)?.representedObject = id }
        title.setAccessibilityLabel("Document title"); author.setAccessibilityLabel("Author"); language.setAccessibilityLabel("Spelling language")
        view = NSGridView(views: [[NSTextField(labelWithString: "Title"), title], [NSTextField(labelWithString: "Author"), author], [NSTextField(labelWithString: "Spelling language"), language]])
        view.columnSpacing = 24; view.rowSpacing = 14
        view.column(at: 0).width = 125; view.column(at: 1).width = 300
        for row in 0..<3 { view.row(at: row).height = 26 }
        view.frame = NSRect(x: 0, y: 0, width: 449, height: 110)
    }
    var selectedLanguage: String { identifiers[max(0, language.indexOfSelectedItem)] }
}

extension EditorWindowController {
    @objc func documentProperties() {
        let options = DocumentPropertiesOptions(document: fileDocument.snapshot()), alert = NSAlert()
        alert.messageText = "Document Properties"
        alert.informativeText = "Title and author are used by DOCX and PDF exports. The spelling language applies to this document. Automatic uses macOS language detection."
        alert.accessoryView = options.view; alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        while alert.runModal() == .alertFirstButtonReturn {
            do { try applyDocumentProperties(title: options.title.stringValue, author: options.author.stringValue, language: options.selectedLanguage); return }
            catch { alert.informativeText = error.localizedDescription }
        }
    }
    func applyDocumentProperties(title: String, author: String, language: String) throws {
        var updated = fileDocument.snapshot()
        try updated.setMetadata(title: title, author: author, language: language)
        fileDocument.performEdit("Document Properties") { $0 = updated }
        synchronizeWindowTitleWithDocumentName(); updateStatus()
        editor.activeTextView.checkText(in: NSRange(location: 0, length: editor.storage.length), types: NSTextCheckingResult.CheckingType.spelling.rawValue, options: [:])
    }
}
#endif
