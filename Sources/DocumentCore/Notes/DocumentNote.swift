import Foundation

/// Notes own semantic paragraphs. Their placement is a layout concern, separate
/// from reference order and from the document's running header/footer content.
public struct DocumentNote: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case footnote, endnote }
    public var id: UUID
    public var kind: Kind
    public var paragraphs: [Paragraph]
    public init(id: UUID = UUID(), kind: Kind, text: String = "") {
        self.id = id; self.kind = kind; paragraphs = [Paragraph(text)]
    }
    public var plainText: String {
        paragraphs.map { paragraph in
            paragraph.runs.map { $0.equation.map { "[Equation: \($0.source)]" } ?? $0.image.map { $0.altText.isEmpty ? "[Image]" : "[Image: \($0.altText)]" } ?? $0.text }.joined()
        }.joined(separator: "\n")
    }
}

/// Recomputed from reference order, so moving or deleting a reference cannot
/// leave a stale stored number. Footnotes and endnotes have independent series.
public struct NumberedNote: Equatable, Sendable, Identifiable {
    public let note: DocumentNote
    public let number: Int
    public var id: UUID { note.id }
}

public enum NoteNumbering {
    public static func resolve(referenceIDs: [UUID], notes: [DocumentNote]) throws -> [NumberedNote] {
        guard notes.count <= 10000, referenceIDs.count <= 10000 else { throw DocumentError.invalid("too many document notes") }
        guard Set(notes.map(\.id)).count == notes.count else { throw DocumentError.invalid("duplicate note identifiers") }
        guard Set(referenceIDs).count == referenceIDs.count else { throw DocumentError.invalid("a note must have one document reference") }
        let catalog = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var footnotes = 0, endnotes = 0
        return try referenceIDs.map { id in
            guard let note = catalog[id], !note.paragraphs.isEmpty else { throw DocumentError.invalid("missing note content") }
            switch note.kind {
            case .footnote: footnotes += 1; return NumberedNote(note: note, number: footnotes)
            case .endnote: endnotes += 1; return NumberedNote(note: note, number: endnotes)
            }
        }
    }
}
