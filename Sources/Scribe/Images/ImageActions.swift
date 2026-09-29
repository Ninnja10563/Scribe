#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
import DocumentCore

extension EditorWindowController {
    @objc func insertImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]; panel.allowsMultipleSelection = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do { try self.editor.activeTextView.insertImageData(Data(contentsOf: url), altText: url.deletingPathExtension().lastPathComponent) }
            catch { self.presentError(error) }
        }
    }

}
extension ScribeTextView {
    func insertImageData(_ data: Data, altText: String = "") throws {
        guard let editor else { return }
        let image = try ImageProjection.image(from: data, maximumWidth: editor.canvas.pageSettings.contentWidth, maximumHeight: editor.canvas.pageSettings.contentHeight - 24, altText: altText)
        guard let attachment = ImageProjection.attachment(image) else { return }
        var attributes = typingAttributes
        attributes.removeValue(forKey: .scribeEquation)
        attributes[.attachment] = attachment; attributes[.scribeImage] = try JSONEncoder().encode(image)
        replaceSelection(NSAttributedString(string: "\u{FFFC}", attributes: attributes), action: "Insert Image")
        typingAttributes.removeValue(forKey: .attachment); typingAttributes.removeValue(forKey: .scribeImage); typingAttributes.removeValue(forKey: .scribeEquation)
    }
}
#endif
