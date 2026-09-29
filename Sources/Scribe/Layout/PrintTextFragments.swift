#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor struct PrintTextFragment {
    let storage: NSAttributedString
    let layout: NSLayoutManager
    let container: NSTextContainer
    let glyphs: NSRange
    let origin: NSPoint
    var characters: NSRange { layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil) }
    func bounds(for characters: NSRange, pageHeight: CGFloat) -> CGRect {
        let range = NSIntersectionRange(layout.glyphRange(forCharacterRange: characters, actualCharacterRange: nil), glyphs)
        let rect = layout.boundingRect(forGlyphRange: range, in: container)
        return CGRect(x: origin.x + rect.minX, y: pageHeight - origin.y - rect.maxY, width: rect.width, height: rect.height)
    }
}
extension PrintRenderer {
    func textFragments(on index: Int) -> [PrintTextFragment] {
        let p = editor.canvas.pageSettings
        var result: [PrintTextFragment] = []
        if index < editor.textViews.count {
            let container = editor.layout.textContainers[index]
            result.append(PrintTextFragment(storage: editor.storage, layout: editor.layout, container: container, glyphs: editor.layout.glyphRange(for: container), origin: NSPoint(x: p.left, y: p.top)))
        } else if let notes = editor.canvas.endnotes {
            let container = notes.containers[index - editor.textViews.count]
            result.append(PrintTextFragment(storage: notes.storage, layout: notes.layout, container: container, glyphs: notes.layout.glyphRange(for: container), origin: NSPoint(x: p.left, y: p.top)))
        }
        if let page = editor.canvas.footnotes[index] {
            var y = p.height - p.bottom - page.height + 12
            for fragment in page.notes {
                result.append(PrintTextFragment(storage: fragment.note.storage, layout: fragment.note.layout, container: fragment.note.container, glyphs: fragment.glyphs, origin: NSPoint(x: p.left, y: y - fragment.top)))
                y += fragment.height + 6
            }
        }
        return result
    }
    var contentStorages: [NSAttributedString] {
        var seen = Set<ObjectIdentifier>()
        return (0..<editor.canvas.pageCount).flatMap { textFragments(on: $0) }.compactMap { fragment in
            seen.insert(ObjectIdentifier(fragment.storage)).inserted ? fragment.storage : nil
        }
    }
    func noteDestinations(in selected: [Int]) -> [String: (page: Int, point: CGPoint)] {
        var result: [String: (page: Int, point: CGPoint)] = [:]
        for index in selected {
            for fragment in textFragments(on: index) {
                for key in [NSAttributedString.Key.scribeNote, .scribeNoteContentID] {
                    fragment.storage.enumerateAttribute(key, in: fragment.characters) { value, range, _ in
                        let id = key == .scribeNote ? (value as? Data).flatMap { try? JSONDecoder().decode(DocumentNote.self, from: $0).id } : (value as? String).flatMap(UUID.init(uuidString:))
                        guard let id else { return }
                        let name = Self.noteAnchor(id, reference: key == .scribeNote)
                        guard result[name] == nil else { return }
                        let rect = fragment.bounds(for: NSRange(location: range.location, length: min(1, range.length)), pageHeight: editor.canvas.pageSettings.height)
                        result[name] = (index, CGPoint(x: rect.minX, y: rect.maxY))
                    }
                }
            }
        }
        return result
    }
    static func noteAnchor(_ id: UUID, reference: Bool) -> String { "Scribe_" + (reference ? "Reference_" : "Note_") + id.uuidString }
}
#endif
