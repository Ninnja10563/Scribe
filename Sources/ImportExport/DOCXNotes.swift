import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import DocumentCore

/// Reuses the ordinary paragraph/run reader inside each normal note. Separator
/// definitions are layout metadata, never user note content or body references.
final class DOCXNotesReader: NSObject, XMLParserDelegate {
    let kind: DocumentNote.Kind
    let makeReader: () -> WordReader
    private var current: WordReader?
    private var currentID: String?
    private var depth = 0
    private var seen = Set<String>()
    var notes: [String: DocumentNote] = [:]
    var warnings = Set<String>()
    init(kind: DocumentNote.Kind, makeReader: @escaping () -> WordReader) {
        self.kind = kind; self.makeReader = makeReader
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if depth > 0 {
            depth += 1
            current?.parser(parser, didStartElement: name, namespaceURI: namespaceURI, qualifiedName: qualifiedName, attributes: a)
            return
        }
        guard namespaceURI == DOCX.wordNS, name == kind.rawValue else { return }
        guard let rawID = a["w:id"] ?? a["id"], let number = Int(rawID), seen.insert(String(number)).inserted, seen.count <= 10003 else { parser.abortParsing(); return }
        depth = 1
        let type = a["w:type"] ?? a["type"] ?? "normal"
        guard type == "normal" else { return }
        currentID = String(number); current = makeReader()
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { current?.parser(parser, foundCharacters: string) }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard depth > 0 else { return }
        depth -= 1
        if depth > 0 {
            current?.parser(parser, didEndElement: name, namespaceURI: namespaceURI, qualifiedName: qualifiedName); return
        }
        guard let reader = current, let id = currentID else { return }
        var note = DocumentNote(kind: kind)
        note.paragraphs = reader.paragraphs.isEmpty ? [Paragraph()] : reader.paragraphs
        // Word convention places a space/tab after the automatic note label.
        if reader.hasLeadingNoteLabel, let first = note.paragraphs[0].runs.first, first.text.hasPrefix(" ") || first.text.hasPrefix("\t") {
            note.paragraphs[0].runs[0].text.removeFirst()
        }
        notes[id] = note; warnings.formUnion(reader.warnings)
        if !reader.commentStarts.isEmpty || !reader.commentReferences.isEmpty {
            warnings.insert("Comments within notes are retained as detached document comments; their note anchors are not retained.")
        }
        current = nil; currentID = nil
    }
}

final class DOCXNoteSettingsReader: NSObject, XMLParserDelegate {
    private var inProperties = false
    var warnings = Set<String>()
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        guard namespaceURI == DOCX.wordNS else { return }
        if name == "footnotePr" || name == "endnotePr" { inProperties = true }
        guard inProperties else { return }
        let value = a["w:val"] ?? a["val"] ?? ""
        if (name == "numFmt" && value != "decimal") || (name == "numRestart" && value != "continuous") || (name == "numStart" && value != "1") {
            warnings.insert("Note numbering is imported as continuous decimal numbering starting at one.")
        }
        if name == "pos", !["pageBottom", "docEnd"].contains(value) {
            warnings.insert("Footnotes use the page bottom and endnotes use the document end in Scribe.")
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if namespaceURI == DOCX.wordNS, name == "footnotePr" || name == "endnotePr" { inProperties = false }
    }
}
