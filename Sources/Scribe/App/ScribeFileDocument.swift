#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
import DocumentCore
import ImportExport

@MainActor final class ScribeFileDocument: NSDocument {
    static let typeName = "org.scribe.document"
    static let recovery = RecoveryStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Scribe/Recovery", isDirectory: true))
    var model = ScribeDocument()
    var editorController: EditorWindowController?
    var importWarnings: [String] = []
    private var recoveryWork: DispatchWorkItem?
    private var isRestoring = false
    override class var autosavesInPlace: Bool { true }
    override class var readableTypes: [String] { [typeName] }
    override class var writableTypes: [String] { [typeName] }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }
    override init() { super.init(); hasUndoManager = true }
    override func makeWindowControllers() {
        let controller = EditorWindowController(document: self)
        editorController = controller; addWindowController(controller)
    }
    func snapshot() -> ScribeDocument {
        if let editor = editorController?.editor {
            let view = editor.activeTextView
            let insertion = view.selectedRange().location == editor.storage.length ? view.typingAttributes : nil
            model = AttributedDocument.capture(editor.storage, preserving: model, typingAttributes: insertion)
            var offset = 0
            let paragraphs = model.sections[0].paragraphs
            editor.storage.beginEditing()
            for (index, component) in editor.storage.string.components(separatedBy: "\n").enumerated() {
                let length = min((component as NSString).length + 1, editor.storage.length - offset)
                let id = paragraphs[index].id.uuidString
                if length > 0, editor.storage.attribute(.scribeParagraphID, at: offset, effectiveRange: nil) as? String != id {
                    editor.storage.addAttribute(.scribeParagraphID, value: id, range: NSRange(location: offset, length: length))
                }
                offset += (component as NSString).length + 1
            }
            editor.storage.endEditing()
        }
        return model
    }
    override func data(ofType typeName: String) throws -> Data { try NativeFormat.encode(snapshot()) }
    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = try NativeFormat.decode(data)
        guard decoded.sections.count == 1 else { throw DocumentError.invalid("this version cannot edit multiple native sections without losing their layout") }
        MainActor.assumeIsolated { model = decoded }
    }
    func didEdit() {
        guard !isRestoring else { return }
        updateChangeCount(.changeDone)
        recoveryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let snapshot = RecoverySnapshot(document: self.snapshot(), originalURL: self.fileURL)
            Task {
                do { try await Self.recovery.save(snapshot) }
                catch { self.editorController?.showStatus("Recovery copy failed: \(error.localizedDescription)") }
            }
            self.editorController?.refreshOutline()
        }
        recoveryWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
    func performEdit(_ name: String, change: (inout ScribeDocument) -> Void) {
        let before = snapshot(); var after = before; change(&after)
        guard before != after else { return }
        restore(after, undo: before, name: name)
    }
    private func restore(_ value: ScribeDocument, undo previous: ScribeDocument, name: String) {
        undoManager?.registerUndo(withTarget: self) { target in MainActor.assumeIsolated { target.restore(previous, undo: value, name: name) } }
        undoManager?.setActionName(name)
        isRestoring = true
        let selection = editorController?.editor.activeTextView.selectedRange() ?? NSRange(location: 0, length: 0)
        model = value
        if let editor = editorController?.editor {
            editor.storage.setAttributedString(AttributedDocument.render(value))
            editor.setPageSettings(value.sections[0].page)
            editor.canvas.pageNumbering = value.sections[0].pageNumbering
            editor.canvas.header = value.sections[0].header; editor.canvas.footer = value.sections[0].footer
            editor.select(NSRange(location: min(selection.location, editor.storage.length), length: min(selection.length, max(0, editor.storage.length - selection.location))))
            if selection.length == 0 {
                let prefix = (editor.storage.string as NSString).substring(to: min(selection.location, editor.storage.length))
                let index = min(prefix.components(separatedBy: "\n").count - 1, value.paragraphs.count - 1)
                let paragraph = value.paragraphs[index]
                if editor.storage.length > 0, selection.location < editor.storage.length {
                    editor.activeTextView.typingAttributes = editor.storage.attributes(at: selection.location, effectiveRange: nil)
                } else {
                    editor.activeTextView.typingAttributes = AttributedDocument.attributes(style: value.style(for: paragraph), paragraph: paragraph)
                }
            }
        }
        isRestoring = false; didEdit(); editorController?.refreshOutline()
    }
    override func close() {
        recoveryWork?.cancel()
        let id = model.id
        Task { try? await Self.recovery.remove(id: id) }
        super.close()
    }
    @objc func exportDocument(_ sender: NSMenuItem) { editorController?.exportDocument(format: sender.representedObject as? String ?? "pdf") }
    override func printDocument(_ sender: Any?) { editorController?.printDocument() }
}

@MainActor final class ScribeDocumentController: NSDocumentController {
    override var defaultType: String? { ScribeFileDocument.typeName }
    override func documentClass(forType typeName: String) -> AnyClass? { ScribeFileDocument.self }
    override func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "scribe") ?? .data, .plainText, .rtf, .init(filenameExtension: "docx") ?? .data, .init(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                if url.pathExtension.lowercased() == "scribe" {
                    self.openDocument(withContentsOf: url, display: true) { _, _, error in if let error { NSApp.presentError(error) } }
                } else { self.importDocument(url) }
            }
        }
    }
    func importDocument(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= NativeFormat.maximumBytes else { throw DocumentError.tooLarge }
            let document = ScribeFileDocument()
            switch url.pathExtension.lowercased() {
            case "docx":
                let result = try DOCX.decode(data); document.model = result.document; document.importWarnings = result.warnings
            case "rtf":
                let value = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
                value.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: value.length)) { style, _, stop in
                    if let style = style as? NSParagraphStyle, !style.textBlocks.isEmpty {
                        document.importWarnings.append("RTF table cells are imported as paragraphs; table geometry is not retained."); stop.pointee = true
                    }
                }
                document.model = AttributedDocument.capture(value, preserving: ScribeDocument())
            default:
                guard let string = String(data: data, encoding: .utf8) else { throw DocumentError.invalid("text must use UTF-8 encoding") }
                document.model = url.pathExtension.lowercased() == "md" ? TextFormats.markdown(string) : TextFormats.plainText(string)
            }
            document.model.title = url.deletingPathExtension().lastPathComponent
            addDocument(document); document.makeWindowControllers(); document.showWindows(); document.updateChangeCount(.changeDone)
            if !document.importWarnings.isEmpty {
                let alert = NSAlert(); alert.messageText = "Imported with limitations"
                alert.informativeText = document.importWarnings.joined(separator: "\n\n") + "\n\nYour original file has not been changed. Save this copy as a Scribe document."
                alert.beginSheetModal(for: document.editorController!.window!)
            }
        } catch { NSApp.presentError(error) }
    }
}
#endif
