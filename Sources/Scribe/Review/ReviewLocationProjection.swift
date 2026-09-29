#if canImport(AppKit)
import AppKit
import DocumentCore

/// Review navigation shares the physical body/note presentation used by Find,
/// but its source of truth is a semantic revision extent, never a text query.
@MainActor enum ReviewLocationProjection {
    static func match(for location: RevisionLocation, in storage: NSAttributedString,
                      document: ScribeDocument) -> DocumentSearchMatch? {
        let paragraphs: [Paragraph]
        if let id = location.noteID {
            guard let note = document.notes.first(where: { $0.id == id }) else { return nil }
            paragraphs = note.paragraphs
        } else { paragraphs = document.paragraphs }
        guard let index = paragraphs.firstIndex(where: { $0.id == location.paragraphID }) else { return nil }
        let paragraph = paragraphs[index], length = paragraph.text.utf16.count, range = location.range
        guard range.location >= 0, range.length >= 0, range.location <= length else { return nil }
        if location.isParagraphSeparator {
            guard range.location == length, range.length == 1, index + 1 < paragraphs.count else { return nil }
        } else if range.length > length - range.location { return nil }

        if let id = location.noteID {
            var reference: NSRange?
            storage.enumerateAttribute(.scribeNote, in: NSRange(location: 0, length: storage.length)) { value, extent, stop in
                guard let data = value as? Data, data.count <= NativeFormat.maximumBytes,
                      let note = try? JSONDecoder().decode(DocumentNote.self, from: data), note.id == id,
                      note.paragraphs == paragraphs else { return }
                reference = extent; stop.pointee = true
            }
            guard let reference else { return nil }
            let start = paragraphs.prefix(index).reduce(0) { $0 + $1.text.utf16.count + 1 }
            return .note(id: id, range: NSRange(location: start + range.location, length: range.length), reference: reference)
        }
        // Map paragraph content first, then add the semantic offset. Mapping
        // a separator to the next paragraph would select its generated label.
        let anchor = TextAnchor(paragraphID: paragraph.id, offset: 0, length: length)
        guard let content = CommentProjection.range(for: anchor, in: storage, document: document),
              (storage.string as NSString).substring(with: content) == paragraph.text else { return nil }
        let target = NSRange(location: content.location + range.location, length: range.length)
        guard NSMaxRange(target) <= storage.length else { return nil }
        if location.isParagraphSeparator, (storage.string as NSString).substring(with: target) != "\n" { return nil }
        return .body(target)
    }
}
#endif
