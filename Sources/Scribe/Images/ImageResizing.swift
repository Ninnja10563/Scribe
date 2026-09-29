#if canImport(AppKit)
import AppKit
import DocumentCore

extension ScribeTextView {
    var selectedImageFrame: NSRect? {
        let range = selectedRange()
        guard range.length == 1, let storage = textStorage, range.location < storage.length,
              storage.attribute(.attachment, at: range.location, effectiveRange: nil) != nil,
              let layoutManager, let textContainer else { return nil }
        if (storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment)?.attachmentCell is FloatingImageAnchorCell { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0, layoutManager.textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) === textContainer else { return nil }
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }
    func drawImageSelection() {
        guard let rect = selectedImageFrame else { return }
        NSColor.controlAccentColor.setStroke(); NSBezierPath(rect: rect).stroke()
        NSColor.controlAccentColor.setFill()
        for point in [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)] {
            NSRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6).fill()
        }
    }
    /// Tracks a native mouse gesture; only the final size becomes one undoable edit.
    func resizeImageIfNeeded(with event: NSEvent) -> Bool {
        guard let rect = selectedImageFrame, let editor, let window, let storage = textStorage else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let corners = [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)]
        guard let corner = corners.first(where: { NSRect(x: $0.x - 7, y: $0.y - 7, width: 14, height: 14).contains(point) }) else { return false }
        let range = selectedRange(), original = storage.attributes(at: selectedRange().location, effectiveRange: nil)
        guard let data = original[.scribeImage] as? Data, let image = try? JSONDecoder().decode(InlineImage.self, from: data),
              let attachment = ImageProjection.attachment(image), let cell = attachment.attachmentCell as? NSTextAttachmentCell else { return false }
        var updated = image
        let startInWindow = event.locationInWindow, gestureScale = editor.zoom
        let horizontalDirection: CGFloat = corner.x == rect.minX ? -1 : 1
        let verticalDirection: CGFloat = corner.y == rect.minY ? -1 : 1
        let maxWidth = editor.canvas.pageSettings.contentWidth
        let maxHeight = editor.canvas.pageSettings.contentHeight - 24
        var deferredKey: NSEvent?
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .keyDown {
                updated = image
                if next.keyCode != 53 { deferredKey = next }
                break
            }
            if next.type == .leftMouseUp { break }
            // The original text view may disappear when a smaller image moves to an earlier page.
            let horizontalChange = (next.locationInWindow.x - startInWindow.x) / gestureScale
            let verticalChange = (startInWindow.y - next.locationInWindow.y) / gestureScale
            let scale = ImageResizeGeometry.scale(width: image.width, height: image.height, horizontalChange: horizontalChange * horizontalDirection, verticalChange: verticalChange * verticalDirection, maximumWidth: maxWidth, maximumHeight: maxHeight)
            updated.width = image.width * scale; updated.height = image.height * scale
            cell.image?.size = NSSize(width: updated.width, height: updated.height)
            storage.addAttribute(.attachment, value: attachment, range: range)
            layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            editor.paginate(); needsDisplay = true
        }
        storage.setAttributes(original, range: range)
        if updated != image, let finalAttachment = ImageProjection.attachment(updated) {
            var attributes = original; attributes[.attachment] = finalAttachment; attributes[.scribeImage] = try? JSONEncoder().encode(updated)
            editor.select(range)
            let target = editor.activeTextView
            target.replaceSelection(NSAttributedString(string: "\u{FFFC}", attributes: attributes), action: "Resize Image")
            target.setSelectedRange(range)
        }
        editor.paginate(); needsDisplay = true
        if let deferredKey { NSApp.sendEvent(deferredKey) }
        return true
    }
}
#endif
