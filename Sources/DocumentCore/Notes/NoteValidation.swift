import Foundation

/// Note content shares the document's named styles, but cannot recursively own
/// more notes, tables or generated contents. Validation never repairs source data.
enum NoteValidation {
    static func validate(_ document: ScribeDocument) throws {
        let references = document.paragraphs.flatMap(\.runs).compactMap(\.noteID)
        let numbered = try NoteNumbering.resolve(referenceIDs: references, notes: document.notes)
        guard numbered.count == document.notes.count else { throw DocumentError.invalid("unreferenced note content") }
        var paragraphIDs = Set(document.paragraphs.map(\.id))
        for note in document.notes {
            guard !note.paragraphs.isEmpty, note.paragraphs.count <= 1000 else { throw DocumentError.invalid("invalid note paragraph count") }
            for paragraph in note.paragraphs {
                guard paragraphIDs.insert(paragraph.id).inserted else { throw DocumentError.invalid("duplicate note paragraph identifier") }
                guard paragraph.tableCell == nil, paragraph.toc == nil, !paragraph.pageBreakBefore,
                      !paragraph.text.contains("\u{c}"), paragraph.runs.allSatisfy({ $0.noteID == nil }) else { throw DocumentError.invalid("notes cannot contain other notes, tables, contents or page breaks") }
            }
            // Reuse all normal run/style/image/equation checks without recursion:
            // the isolated document has an empty note registry and no references.
            var isolated = ScribeDocument(); isolated.styles = document.styles
            isolated.sections[0].paragraphs = note.paragraphs
            try NativeFormat.validate(isolated)
        }
    }
}
