import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import DocumentCore

struct DOCXCommentsWriter {
    private var starts: [UUID: [Int: [Int]]] = [:], ends: [UUID: [Int: [Int]]] = [:]
    let comments: [Comment]
    init(document: ScribeDocument) {
        comments = document.comments
        let index = DocumentTextIndex(paragraphs: document.paragraphs)
        for (id, comment) in comments.enumerated() where comment.isDetached != true {
            guard index.range(for: comment.anchor) != nil else { continue }
            let anchor = comment.anchor
            starts[anchor.paragraphID, default: [:]][anchor.offset, default: []].append(id)
            let endID = anchor.endParagraphID ?? anchor.paragraphID, endOffset = anchor.endOffset ?? anchor.offset + anchor.length
            ends[endID, default: [:]][endOffset, default: []].append(id)
        }
    }
    func boundaries(paragraphID: UUID) -> [Int] {
        Array(Set(Array(starts[paragraphID]?.keys ?? Dictionary<Int, [Int]>().keys) + Array(ends[paragraphID]?.keys ?? Dictionary<Int, [Int]>().keys))).sorted()
    }
    func markers(paragraphID: UUID, offset: Int) -> String {
        let start = (starts[paragraphID]?[offset] ?? []).map { "<w:commentRangeStart w:id=\"\($0)\"/>" }.joined()
        let end = (ends[paragraphID]?[offset] ?? []).map { "<w:commentRangeEnd w:id=\"\($0)\"/><w:r><w:commentReference w:id=\"\($0)\"/></w:r>" }.joined()
        return start + end
    }
    var xml: String {
        let contents = comments.enumerated().map { id, comment in
            let paragraphs = comment.text.components(separatedBy: "\n").map { text in
                "<w:p><w:r><w:t xml:space=\"preserve\">\(DOCX.xml(text))</w:t></w:r></w:p>"
            }.joined()
            return "<w:comment w:id=\"\(id)\" w:author=\"\(DOCX.xml(comment.author))\">\(paragraphs)</w:comment>"
        }.joined()
        return "<w:comments xmlns:w=\"\(DOCX.wordNS)\">\(contents)</w:comments>"
    }
}

final class DOCXCommentsReader: NSObject, XMLParserDelegate {
    struct Value { let id: String; let text: String; let author: String }
    var values: [Value] = []
    private var id: String?, author = "", text = "", collecting = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        guard namespaceURI == DOCX.wordNS else { return }
        switch name {
        case "comment": id = a["w:id"] ?? a["id"]; author = a["w:author"] ?? a["author"] ?? ""; text = ""
        case "t": collecting = id != nil
        case "tab": if id != nil { text += "\t" }
        case "br": if id != nil { text += "\n" }
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if collecting { text += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard namespaceURI == DOCX.wordNS else { return }
        switch name {
        case "t": collecting = false
        case "p": if id != nil { text += "\n" }
        case "comment":
            if let id { values.append(Value(id: id, text: text.hasSuffix("\n") ? String(text.dropLast()) : text, author: author)) }
            id = nil; collecting = false
        default: break
        }
    }
}
