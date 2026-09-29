#if canImport(AppKit)
import AppKit
import DocumentCore

/// A separate native text flow follows the body. Linked containers allow long
/// endnotes to continue across real pages without changing their semantic owner.
@MainActor final class EndnoteLayout {
    let storage: NSTextStorage
    let layout: NSLayoutManager
    let containers: [NSTextContainer]
    init(notes: [NumberedNote], styles: [ParagraphStyle], page: PageSettings, maximumPages: Int) throws {
        guard !notes.isEmpty, maximumPages > 0 else { throw DocumentError.invalid("no space remains for endnote pages") }
        let heading = NSMutableParagraphStyle(); heading.paragraphSpacing = 12
        let value = NSMutableAttributedString(string: "Endnotes\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.black, .paragraphStyle: heading])
        for (index, note) in notes.enumerated() {
            if index > 0 { value.append(NSAttributedString(string: "\n", attributes: value.attributes(at: value.length - 1, effectiveRange: nil))) }
            value.append(try NoteTextLayout(note: note, styles: styles, width: page.contentWidth).storage)
        }
        let storage = NSTextStorage(attributedString: value), layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var containers: [NSTextContainer] = []
        func appendContainer() {
            let container = NSTextContainer(containerSize: NSSize(width: page.contentWidth, height: page.contentHeight))
            container.lineFragmentPadding = 0; container.widthTracksTextView = false; container.heightTracksTextView = false
            layout.addTextContainer(container); containers.append(container)
        }
        appendContainer()
        for index in 0..<maximumPages {
            if index == containers.count { appendContainer() }
            let container = containers[index]
            layout.ensureLayout(for: container)
            var range = layout.glyphRange(for: container)
            if NSMaxRange(range) < layout.numberOfGlyphs, index == containers.count - 1, index + 1 < maximumPages {
                appendContainer(); layout.textContainerChangedGeometry(container); layout.ensureLayout(for: container)
                range = layout.glyphRange(for: container)
            }
            guard range.length > 0, layout.usedRect(for: container).maxY <= page.contentHeight + 1 else {
                throw DocumentError.invalid("an endnote object cannot fit within the page writing area")
            }
            if NSMaxRange(range) == layout.numberOfGlyphs {
                while containers.count > index + 1 { containers.removeLast(); layout.removeTextContainer(at: layout.textContainers.count - 1) }
                self.storage = storage; self.layout = layout; self.containers = containers
                return
            }
        }
        throw DocumentError.invalid("endnotes exceed the current 2,000-page document layout limit")
    }
    func draw(page: Int, at origin: NSPoint) {
        guard containers.indices.contains(page) else { return }
        let range = layout.glyphRange(for: containers[page])
        layout.drawBackground(forGlyphRange: range, at: origin)
        layout.drawGlyphs(forGlyphRange: range, at: origin)
    }
}
#endif
