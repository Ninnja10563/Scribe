#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class ImagePropertiesOptions {
    let width: NSTextField
    let rotation: NSTextField
    let opacity: NSTextField
    let left: NSTextField, top: NSTextField, right: NSTextField, bottom: NSTextField
    let descriptionField: NSTextField
    let view: NSGridView
    init(image: InlineImage) {
        let crop = image.adjustments?.crop ?? ImageCrop()
        width = NSTextField(string: String(image.sourceDisplayWidth))
        rotation = NSTextField(string: String(image.adjustments?.rotation ?? 0))
        opacity = NSTextField(string: String((image.adjustments?.opacity ?? 1) * 100))
        left = NSTextField(string: String(crop.left * 100)); top = NSTextField(string: String(crop.top * 100))
        right = NSTextField(string: String(crop.right * 100)); bottom = NSTextField(string: String(crop.bottom * 100))
        descriptionField = NSTextField(string: image.altText)
        let rows: [(String, NSTextField)] = [("Original width (pt)", width), ("Clockwise rotation (°)", rotation), ("Opacity (%)", opacity), ("Crop left (%)", left), ("Crop top (%)", top), ("Crop right (%)", right), ("Crop bottom (%)", bottom), ("Accessibility description", descriptionField)]
        for (label, field) in rows { field.setAccessibilityLabel(label); field.identifier = NSUserInterfaceItemIdentifier(label) }
        view = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
        view.columnSpacing = 20; view.rowSpacing = 10
        view.column(at: 0).width = 155; view.column(at: 1).width = 270
        for row in 0..<rows.count { view.row(at: row).height = 24 }
        view.frame = NSRect(x: 0, y: 0, width: 445, height: 262)
    }
    func reset() { for field in [left, top, right, bottom, rotation] { field.stringValue = "0" }; opacity.stringValue = "100" }
    func adjusted(_ image: InlineImage, page: PageSettings) throws -> InlineImage {
        guard let width = Double(width.stringValue), let rotation = Double(rotation.stringValue), let opacity = Double(opacity.stringValue),
              let left = Double(left.stringValue), let top = Double(top.stringValue), let right = Double(right.stringValue), let bottom = Double(bottom.stringValue) else { throw DocumentError.invalid("enter numbers for width, rotation, opacity and crop percentages") }
        var result = try image.adjusted(crop: ImageCrop(left: left / 100, top: top / 100, right: right / 100, bottom: bottom / 100), rotation: rotation, opacity: opacity / 100, sourceWidth: width, maximumWidth: page.contentWidth, maximumHeight: page.contentHeight - 24)
        result.altText = descriptionField.stringValue
        return result
    }
}

extension EditorWindowController {
    @objc func imageProperties() {
        let view = editor.activeTextView, range = view.selectedRange()
        guard range.location < editor.storage.length, let encoded = editor.storage.attribute(.scribeImage, at: range.location, effectiveRange: nil) as? Data,
              let image = try? JSONDecoder().decode(InlineImage.self, from: encoded) else { showStatus("Select an image first."); return }
        let options = ImagePropertiesOptions(image: image), alert = NSAlert()
        alert.messageText = "Image Properties"
        alert.informativeText = "Crop percentages remove original edges. Width is measured before cropping and rotation; large images are reduced to fit the page. The source image stays intact."
        alert.accessoryView = options.view
        alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Reset Adjustments")
        while !isClosing {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                do { try applyImageProperties(options.adjusted(image, page: editor.canvas.pageSettings), at: range.location); return }
                catch { alert.informativeText = error.localizedDescription }
            case .alertThirdButtonReturn: options.reset()
            default: return
            }
        }
    }
    func applyImageProperties(_ image: InlineImage, at location: Int) throws {
        guard !isClosing, location < editor.storage.length, location >= 0 else { throw DocumentError.invalid("the selected image is no longer available") }
        var attributes = editor.storage.attributes(at: location, effectiveRange: nil)
        guard let data = attributes[.scribeImage] as? Data, let previous = try? JSONDecoder().decode(InlineImage.self, from: data), previous.id == image.id else { throw DocumentError.invalid("the selected image has changed") }
        var check = ScribeDocument(), run = TextRun("\u{FFFC}"); run.image = image
        check.sections[0].paragraphs[0].runs = [run]; try NativeFormat.validate(check)
        guard let attachment = ImageProjection.attachment(image) else { throw DocumentError.invalid("could not display this image") }
        attributes[.attachment] = attachment; attributes[.scribeImage] = try JSONEncoder().encode(image)
        let view = editor.activeTextView
        view.setSelectedRange(NSRange(location: location, length: 1))
        view.replaceSelection(NSAttributedString(string: "\u{FFFC}", attributes: attributes), action: "Image Properties")
        view.setSelectedRange(NSRange(location: location, length: 1))
    }
}
#endif
