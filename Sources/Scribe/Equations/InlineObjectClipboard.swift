#if canImport(AppKit)
import AppKit
import DocumentCore

/// Optional, bounded JSON accompanies standard RTFD. No object unarchiving is used.
@MainActor enum InlineObjectClipboard {
    static let type = NSPasteboard.PasteboardType("org.scribe.inline-objects.v1")
    private struct Entry: Codable {
        let location: Int
        let equation: Equation?
        let image: InlineImage?
        let note: DocumentNote?
    }
    private struct Payload: Codable {
        let version: Int
        let text: String
        let objects: [Entry]
    }
    static func encode(_ value: NSAttributedString, styles: [ParagraphStyle] = ParagraphStyle.defaults) throws -> Data {
        var objects: [Entry] = []
        let text = value.string as NSString
        var tooMany = false
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, stop in
            let equation = (attributes[.scribeEquation] as? Data).flatMap { try? JSONDecoder().decode(Equation.self, from: $0) }
            let image = (attributes[.scribeImage] as? Data).flatMap { try? JSONDecoder().decode(InlineImage.self, from: $0) }
            let note = (attributes[.scribeNote] as? Data).flatMap { try? JSONDecoder().decode(DocumentNote.self, from: $0) }.map { NoteClipboard.normalized($0, styles: styles) }
            guard equation != nil || image != nil || note != nil else { return }
            for location in range.location..<NSMaxRange(range) where text.character(at: location) == 0xFFFC {
                guard objects.count < 10000 else { tooMany = true; stop.pointee = true; break }
                objects.append(Entry(location: location, equation: equation, image: image, note: note))
            }
        }
        guard !tooMany else { throw DocumentError.invalid("too many clipboard objects") }
        let payload = Payload(version: objects.contains { $0.note != nil } ? 2 : 1, text: value.string, objects: objects)
        try validate(payload)
        let data = try JSONEncoder().encode(payload)
        guard data.count <= NativeFormat.maximumBytes else { throw DocumentError.tooLarge }
        return data
    }
    static func restore(_ data: Data, in value: NSAttributedString, styles: [ParagraphStyle] = ParagraphStyle.defaults) throws -> NSAttributedString {
        guard data.count <= NativeFormat.maximumBytes else { throw DocumentError.tooLarge }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        try validate(payload)
        let expected = NSMutableString(string: payload.text)
        var expansions: [(NSRange, String)] = []
        var offset = 0
        for object in payload.objects.sorted(by: { $0.location < $1.location }) {
            guard let note = object.note else { continue }
            let fallback = NoteClipboard.fallback(note)
            let length = (fallback as NSString).length
            expansions.append((NSRange(location: object.location + offset, length: length), fallback))
            expected.replaceCharacters(in: NSRange(location: object.location + offset, length: 1), with: fallback)
            offset += length - 1
        }
        guard expected as String == value.string else { throw DocumentError.invalid("clipboard text and objects do not match") }
        let result = NSMutableAttributedString(attributedString: value)
        for (range, _) in expansions.reversed() { result.replaceCharacters(in: range, with: "\u{fffc}") }
        for object in payload.objects {
            let range = NSRange(location: object.location, length: 1)
            result.removeAttribute(.scribeNote, range: range); result.removeAttribute(.scribeNoteNumber, range: range)
            result.removeAttribute(.scribeEquation, range: range); result.removeAttribute(.scribeImage, range: range)
            if let source = object.note {
                let note = NoteClipboard.newCopy(NoteClipboard.normalized(source, styles: ParagraphStyle.defaults, targetStyles: styles))
                let numbered = try NoteNumbering.resolve(referenceIDs: [note.id], notes: [note])[0]
                let font = ScriptProjection.logicalFont(in: result.attributes(at: range.location, effectiveRange: nil)) ?? .systemFont(ofSize: 12)
                result.addAttributes([.attachment: NoteProjection.attachment(numbered, baseFont: font), .scribeNote: try JSONEncoder().encode(note), .scribeNoteNumber: 1], range: range)
            } else if let equation = object.equation {
                result.addAttributes([.attachment: EquationProjection.attachment(equation), .scribeEquation: try JSONEncoder().encode(equation)], range: range)
            } else if let image = object.image, let attachment = ImageProjection.attachment(image) {
                result.addAttributes([.attachment: attachment, .scribeImage: try JSONEncoder().encode(image)], range: range)
            }
        }
        return result
    }
    private static func validate(_ payload: Payload) throws {
        let text = payload.text as NSString
        guard [1, 2].contains(payload.version), payload.objects.count <= 10000,
              payload.text.utf8.count <= NativeFormat.maximumBytes,
              Set(payload.objects.map(\.location)).count == payload.objects.count else { throw DocumentError.invalid("invalid clipboard object list") }
        var estimatedBytes = payload.text.utf8.count
        var check = ScribeDocument(); check.sections[0].paragraphs[0].runs = []
        for object in payload.objects {
            let imageBytes: Int = object.image?.data.count ?? 0
            let sourceBytes: Int = object.equation?.source.utf8.count ?? 0
            estimatedBytes += imageBytes * 4 / 3
            estimatedBytes += sourceBytes * 6 + 1024
            if let note = object.note { estimatedBytes += try JSONEncoder().encode(note).count }
            guard estimatedBytes <= NativeFormat.maximumBytes else { throw DocumentError.tooLarge }
            guard object.location >= 0, object.location < text.length, text.character(at: object.location) == 0xFFFC,
                  [object.equation != nil, object.image != nil, object.note != nil].filter({ $0 }).count == 1 else { throw DocumentError.invalid("invalid clipboard object position") }
            var run = TextRun("\u{FFFC}"); run.equation = object.equation; run.image = object.image
            if let note = object.note { run.noteID = note.id; check.notes.append(note) }
            check.sections[0].paragraphs[0].runs.append(run)
        }
        try NativeFormat.validate(check)
    }
}
#endif
