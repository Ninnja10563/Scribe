#if canImport(AppKit)
import AppKit
import PDFKit
import DocumentCore

/// Screen, print and PDF share the same glyph layout and physical page dimensions.
@MainActor final class PrintRenderer: NSView {
    let editor: PaginatedEditor
    override var isFlipped: Bool { true }
    init(editor: PaginatedEditor) {
        self.editor = editor; editor.paginate()
        let page = editor.canvas.pageSettings
        super.init(frame: NSRect(x: 0, y: 0, width: page.width, height: page.height * Double(editor.canvas.pageCount)))
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    override func knowsPageRange(_ range: NSRangePointer) -> Bool { range.pointee = NSRange(location: 1, length: editor.canvas.pageCount); return true }
    override func rectForPage(_ page: Int) -> NSRect {
        let p = editor.canvas.pageSettings
        return NSRect(x: 0, y: CGFloat(page - 1) * p.height, width: p.width, height: p.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        for page in 0..<editor.canvas.pageCount where rectForPage(page + 1).intersects(dirtyRect) {
            NSGraphicsContext.saveGraphicsState()
            let transform = AffineTransform(translationByX: 0, byY: rectForPage(page + 1).minY)
            (transform as NSAffineTransform).concat(); drawPage(page)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    func drawPage(_ index: Int) {
        let p = editor.canvas.pageSettings
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: p.width, height: p.height).fill()
        let origin = NSPoint(x: p.left, y: p.top)
        if index < editor.textViews.count {
            let range = editor.layout.glyphRange(for: editor.layout.textContainers[index])
            withLinkPresentation(on: index) {
                editor.layout.drawBackground(forGlyphRange: range, at: origin)
                editor.layout.drawGlyphs(forGlyphRange: range, at: origin)
            }
        } else { editor.canvas.endnotes?.draw(page: index - editor.textViews.count, at: origin) }
        if let notes = editor.canvas.footnotes[index] {
            notes.draw(at: NSPoint(x: p.left, y: p.height - p.bottom - notes.height), width: p.contentWidth)
        }
        RunningContentLayout.draw(editor.canvas.runningText(isHeader: true, pageIndex: index), at: NSPoint(x: p.left, y: 30), width: p.contentWidth)
        editor.canvas.drawPageNumber(index: index, origin: .zero)
        RunningContentLayout.draw(editor.canvas.runningText(isHeader: false, pageIndex: index), at: NSPoint(x: p.left, y: p.height - 38), width: p.contentWidth)
    }
    private func finalizingLinkAnnotations(from data: Data) throws -> Data {
        var hasLinks = false
        for storage in contentStorages {
            storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
                if value != nil { hasLinks = true; stop.pointee = true }
            }
        }
        guard hasLinks else { return data }
        guard let pdf = PDFDocument(data: data) else { throw DocumentError.invalid("could not finalize PDF links") }
        var changed = false
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            // AppKit emits URL annotations while drawing linked glyphs. The private
            // native scheme is replaced by the actual PDF destinations authored below.
            var seen = Set<String>()
            for annotation in page.annotations {
                guard let url = (annotation.action as? PDFActionURL)?.url else { continue }
                let bounds = annotation.bounds
                let geometry = [bounds.minX, bounds.minY, bounds.width, bounds.height].map { String(format: "%.3f", Double($0)) }.joined(separator: ",")
                let duplicate = !seen.insert(url.absoluteString + "|" + geometry).inserted
                if url.scheme?.lowercased() == "scribe" || duplicate {
                    page.removeAnnotation(annotation); changed = true
                }
            }
        }
        guard changed else { return data }
        guard let result = pdf.dataRepresentation() else { throw DocumentError.invalid("could not finalize PDF links") }
        return result
    }
    private func internalDestinations(in selected: Set<Int>) -> [UUID: (page: Int, point: CGPoint)] {
        let full = NSRange(location: 0, length: editor.storage.length)
        let resolver = editor.owner.map { DocumentLinkResolver($0.snapshot()) }
        var linked: Set<UUID> = []
        for storage in contentStorages {
            storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                let text = (value as? URL)?.absoluteString ?? value as? String ?? ""
                if let id = resolver?.paragraphID(for: text) { linked.insert(id) }
            }
        }
        var result: [UUID: (page: Int, point: CGPoint)] = [:]
        let p = editor.canvas.pageSettings
        editor.storage.enumerateAttribute(.scribeParagraphID, in: full) { value, range, _ in
            guard let value = value as? String, let id = UUID(uuidString: value), linked.contains(id), result[id] == nil else { return }
            let location = editor.navigationLocation(in: range)
            guard location < editor.storage.length else { return }
            let glyph = editor.layout.glyphIndexForCharacter(at: location)
            guard glyph < editor.layout.numberOfGlyphs,
                  let container = editor.layout.textContainer(forGlyphAt: glyph, effectiveRange: nil),
                  let page = editor.layout.textContainers.firstIndex(where: { $0 === container }), selected.contains(page) else { return }
            let rect = editor.layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            result[id] = (page, CGPoint(x: p.left + rect.minX, y: p.height - p.top - rect.minY))
        }
        if let last = editor.owner?.snapshot().paragraphs.last, last.text.isEmpty,
           linked.contains(last.id), result[last.id] == nil,
           let container = editor.layout.extraLineFragmentTextContainer,
           let page = editor.layout.textContainers.firstIndex(where: { $0 === container }), selected.contains(page) {
            let rect = editor.layout.extraLineFragmentRect
            result[last.id] = (page, CGPoint(x: p.left + rect.minX, y: p.height - p.top - rect.minY))
        }
        return result
    }
    func exportPDF(to url: URL, title: String, author: String, pages: [Int]? = nil, subject: String = "", keywords: [String] = []) throws {
        editor.paginate()
        let page = editor.canvas.pageSettings
        frame.size = NSSize(width: page.width, height: page.height * Double(editor.canvas.pageCount))
        let selected = pages ?? Array(0..<editor.canvas.pageCount)
        guard !selected.isEmpty, selected.allSatisfy({ (0..<editor.canvas.pageCount).contains($0) }), selected == Array(Set(selected)).sorted() else {
            throw DocumentError.invalid("invalid PDF page selection")
        }
        if let warning = editor.outputWarning { throw DocumentError.invalid(warning) }
        let p = editor.canvas.pageSettings
        var media = CGRect(x: 0, y: 0, width: p.width, height: p.height)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &media, [kCGPDFContextTitle: title, kCGPDFContextAuthor: author, kCGPDFContextSubject: subject, kCGPDFContextKeywords: keywords, kCGPDFContextCreator: "Scribe"] as CFDictionary) else {
            throw DocumentError.invalid("could not create PDF output")
        }
        let destinations = internalDestinations(in: Set(selected))
        let noteTargets = noteDestinations(in: selected)
        let resolver = editor.owner.map { DocumentLinkResolver($0.snapshot()) }
        for index in selected {
            context.beginPDFPage(nil); context.saveGState()
            context.translateBy(x: 0, y: p.height); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            drawPage(index)
            NSGraphicsContext.restoreGraphicsState(); context.restoreGState()
            for (id, destination) in destinations where destination.page == index {
                context.addDestination(DocumentLink.officeBookmark(id) as CFString, at: destination.point)
            }
            for (name, target) in noteTargets where target.page == index { context.addDestination(name as CFString, at: target.point) }
            for fragment in textFragments(on: index) {
                fragment.storage.enumerateAttribute(.link, in: fragment.characters) { value, range, _ in
                    guard let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:)) else { return }
                    let targetRect = fragment.bounds(for: range, pageHeight: p.height)
                    if let id = resolver?.paragraphID(for: url.absoluteString), destinations[id] != nil {
                        context.setDestination(DocumentLink.officeBookmark(id) as CFString, for: targetRect)
                    } else if ["http", "https", "mailto"].contains(url.scheme ?? "") { context.setURL(url as CFURL, for: targetRect) }
                }
                for key in [NSAttributedString.Key.scribeNote, .scribeNoteLabelID] {
                    fragment.storage.enumerateAttribute(key, in: fragment.characters) { value, range, _ in
                        let id = key == .scribeNote ? (value as? Data).flatMap { try? JSONDecoder().decode(DocumentNote.self, from: $0).id } : (value as? String).flatMap(UUID.init(uuidString:))
                        guard let id else { return }
                        let name = Self.noteAnchor(id, reference: key == .scribeNoteLabelID)
                        if noteTargets[name] != nil { context.setDestination(name as CFString, for: fragment.bounds(for: range, pageHeight: p.height)) }
                    }
                }
            }
            context.endPDFPage()
        }
        context.closePDF()
        try finalizingLinkAnnotations(from: data as Data).write(to: url, options: .atomic)
    }
}
#endif
