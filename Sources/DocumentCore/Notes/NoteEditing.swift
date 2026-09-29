import Foundation

public extension ScribeDocument {
    /// Use after an intentional body edit, never to silently repair a decoded file.
    mutating func reconcileNotes() {
        let referenced = Set(paragraphs.flatMap(\.runs).compactMap(\.noteID))
        notes.removeAll { !referenced.contains($0.id) }
    }
    mutating func updateNote(_ note: DocumentNote) throws {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { throw DocumentError.invalid("the note no longer exists") }
        var candidate = self; candidate.notes[index] = note
        try NativeFormat.validate(candidate)
        self = candidate
    }
}
