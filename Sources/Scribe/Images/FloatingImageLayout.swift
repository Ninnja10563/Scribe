#if canImport(AppKit)
import AppKit
import DocumentCore

/// Retains an immutable semantic image while its inline anchor occupies no image box.
@MainActor final class FloatingImageAnchorCell: NSTextAttachmentCell {
    let source: InlineImage
    lazy var renderedImage: NSImage? = (ImageProjection.attachment(source, forceInline: true)?.attachmentCell as? NSTextAttachmentCell)?.image
    init(_ image: InlineImage) { source = image; super.init(imageCell: nil) }
    required init(coder: NSCoder) { fatalError("Floating anchors are recreated from validated document data") }
}

@MainActor final class FloatingImageLayout {
    struct Entry {
        let image: InlineImage
        let bitmap: NSImage
        let range: NSRange
        let page: Int
        let frame: NSRect
        let writingHeight: CGFloat
    }
    private(set) var entries: [Entry] = []
    func clear() { entries = [] }
    func update(storage: NSTextStorage, layout: NSLayoutManager, page: PageSettings) -> String? {
        var result: [Entry] = [], warning: String?
        let indices = Dictionary(uniqueKeysWithValues: layout.textContainers.enumerated().map { (ObjectIdentifier($0.element), $0.offset) })
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let cell = (value as? NSTextAttachment)?.attachmentCell as? FloatingImageAnchorCell,
                  let placement = cell.source.placement else { return }
            guard let bitmap = cell.renderedImage else { warning = "A floating image could not be rendered."; return }
            for location in range.location..<NSMaxRange(range) {
                let anchor = NSRange(location: location, length: 1)
                let glyphs = layout.glyphRange(forCharacterRange: anchor, actualCharacterRange: nil)
                guard glyphs.length > 0, glyphs.location < layout.numberOfGlyphs,
                      let container = layout.textContainer(forGlyphAt: glyphs.location, effectiveRange: nil),
                      let index = indices[ObjectIdentifier(container)] else {
                    warning = "A floating image's text anchor could not be placed on a page."; continue
                }
                let frame = NSRect(x: placement.x, y: placement.y, width: cell.source.width, height: cell.source.height)
                if frame.maxX > page.contentWidth || frame.maxY > container.containerSize.height {
                    warning = "Move or resize the floating image to fit this page's writing area."
                }
                if placement.wrapping == .square { warning = "Square image wrapping is still being implemented." }
                result.append(Entry(image: cell.source, bitmap: bitmap, range: anchor, page: index, frame: frame, writingHeight: container.containerSize.height))
            }
        }
        entries = result.sorted {
            let first = $0.image.placement?.zOrder ?? 0, second = $1.image.placement?.zOrder ?? 0
            return first == second ? $0.range.location < $1.range.location : first < second
        }
        return warning
    }
    func draw(page index: Int, behindText: Bool, origin: NSPoint, writingWidth: CGFloat) {
        for entry in entries where entry.page == index && (entry.image.placement?.wrapping == .behindText) == behindText {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: origin.x, y: origin.y, width: writingWidth, height: entry.writingHeight)).addClip()
            entry.bitmap.draw(in: entry.frame.offsetBy(dx: origin.x, dy: origin.y), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

/// Page-coordinate foreground painting; native text views retain their input ownership.
@MainActor final class FloatingImageLayer: NSView {
    weak var editor: PaginatedEditor?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let editor else { return }
        let page = editor.canvas.pageSettings
        for index in 0..<editor.canvas.bodyPageCount {
            let rect = editor.canvas.pageRect(index)
            guard rect.intersects(dirtyRect) else { continue }
            editor.floatingImages.draw(page: index, behindText: false, origin: NSPoint(x: rect.minX + page.left, y: rect.minY + page.top), writingWidth: page.contentWidth)
        }
    }
}
#endif
