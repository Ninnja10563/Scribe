#if canImport(AppKit)
import AppKit
import DocumentCore

/// Screen, print and PDF share the same glyph layout and physical page dimensions.
@MainActor final class PrintRenderer: NSView {
    let editor: PaginatedEditor
    override var isFlipped: Bool { true }
    init(editor: PaginatedEditor) {
        self.editor = editor; editor.paginate()
        let page = editor.canvas.pageSettings
        super.init(frame: NSRect(x: 0, y: 0, width: page.width, height: page.height * Double(editor.textViews.count)))
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    override func knowsPageRange(_ range: NSRangePointer) -> Bool { range.pointee = NSRange(location: 1, length: editor.textViews.count); return true }
    override func rectForPage(_ page: Int) -> NSRect {
        let p = editor.canvas.pageSettings
        return NSRect(x: 0, y: CGFloat(page - 1) * p.height, width: p.width, height: p.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        for page in editor.textViews.indices where rectForPage(page + 1).intersects(dirtyRect) {
            NSGraphicsContext.saveGraphicsState()
            let transform = AffineTransform(translationByX: 0, byY: rectForPage(page + 1).minY)
            (transform as NSAffineTransform).concat(); drawPage(page)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    func drawPage(_ index: Int) {
        let p = editor.canvas.pageSettings
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: p.width, height: p.height).fill()
        let range = editor.layout.glyphRange(for: editor.layout.textContainers[index])
        let origin = NSPoint(x: p.left, y: p.top)
        // Search highlights are temporary and should not be included in output.
        editor.layout.drawBackground(forGlyphRange: range, at: origin)
        editor.layout.drawGlyphs(forGlyphRange: range, at: origin)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray]
        (editor.canvas.header as NSString).draw(at: NSPoint(x: p.left, y: 30), withAttributes: attrs)
        editor.canvas.drawPageNumber(index: index, origin: .zero)
        (editor.canvas.footer as NSString).draw(at: NSPoint(x: p.left, y: p.height - 38), withAttributes: attrs)
    }
    func exportPDF(to url: URL, title: String, author: String) throws {
        let p = editor.canvas.pageSettings
        var media = CGRect(x: 0, y: 0, width: p.width, height: p.height)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &media, [kCGPDFContextTitle: title, kCGPDFContextAuthor: author] as CFDictionary) else {
            throw DocumentError.invalid("could not create PDF output")
        }
        for index in editor.textViews.indices {
            context.beginPDFPage(nil); context.saveGState()
            context.translateBy(x: 0, y: p.height); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            drawPage(index)
            NSGraphicsContext.restoreGraphicsState(); context.restoreGState()
            let container = editor.layout.textContainers[index]
            let glyphs = editor.layout.glyphRange(for: container)
            let characters = editor.layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            editor.storage.enumerateAttribute(.link, in: characters) { value, range, _ in
                guard let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:)), ["http", "https", "mailto"].contains(url.scheme ?? "") else { return }
                let linkGlyphs = editor.layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = editor.layout.boundingRect(forGlyphRange: NSIntersectionRange(linkGlyphs, glyphs), in: container)
                context.setURL(url as CFURL, for: CGRect(x: p.left + rect.minX, y: p.height - p.top - rect.maxY, width: rect.width, height: rect.height))
            }
            context.endPDFPage()
        }
        context.closePDF(); try (data as Data).write(to: url, options: .atomic)
    }
}
#endif
