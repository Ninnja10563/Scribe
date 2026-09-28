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
    @objc func imageProperties() {
        let view = editor.activeTextView, range = view.selectedRange()
        guard range.location < editor.storage.length, let encoded = editor.storage.attribute(.scribeImage, at: range.location, effectiveRange: nil) as? Data,
              var image = try? JSONDecoder().decode(InlineImage.self, from: encoded) else { NSSound.beep(); return }
        let alert = NSAlert(); alert.messageText = "Image Properties"
        let width = NSTextField(string: String(Int(image.width))), alt = NSTextField(string: image.altText)
        let stack = NSStackView(views: [NSTextField(labelWithString: "Width in points (aspect ratio preserved)"), width, NSTextField(labelWithString: "Description for accessibility"), alt])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        alt.widthAnchor.constraint(equalToConstant: 330).isActive = true
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 120); alert.accessoryView = stack
        alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let w = Double(width.stringValue), (12...editor.canvas.pageSettings.contentWidth).contains(w), image.height * w / image.width <= editor.canvas.pageSettings.contentHeight else { return }
        image.height *= w / image.width; image.width = w; image.altText = alt.stringValue
        guard let attachment = ImageProjection.attachment(image) else { return }
        var attributes = editor.storage.attributes(at: range.location, effectiveRange: nil)
        attributes[.attachment] = attachment; attributes[.scribeImage] = try? JSONEncoder().encode(image)
        view.setSelectedRange(NSRange(location: range.location, length: 1))
        view.replaceSelection(NSAttributedString(string: "\u{FFFC}", attributes: attributes), action: "Image Properties")
    }
}
extension ScribeTextView {
    func insertImageData(_ data: Data, altText: String = "") throws {
        guard let editor else { return }
        let image = try ImageProjection.image(from: data, maximumWidth: editor.canvas.pageSettings.contentWidth, maximumHeight: editor.canvas.pageSettings.contentHeight - 24, altText: altText)
        guard let attachment = ImageProjection.attachment(image) else { return }
        var attributes = typingAttributes
        attributes[.attachment] = attachment; attributes[.scribeImage] = try JSONEncoder().encode(image)
        replaceSelection(NSAttributedString(string: "\u{FFFC}", attributes: attributes), action: "Insert Image")
        typingAttributes.removeValue(forKey: .attachment); typingAttributes.removeValue(forKey: .scribeImage)
    }
}
#endif
