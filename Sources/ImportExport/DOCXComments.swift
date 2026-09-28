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
    private func paragraphID(_ index: Int) -> String { String(format: "%08X", index + 1) }
    var extendedXML: String {
        let values = comments.enumerated().map { index, comment in
            "<w15:commentEx w15:paraId=\"\(paragraphID(index))\" w15:done=\"\(comment.resolved ? 1 : 0)\"/>"
        }.joined()
        return "<w15:commentsEx xmlns:w15=\"http://schemas.microsoft.com/office/word/2012/wordml\">\(values)</w15:commentsEx>"
    }
    var xml: String {
        let contents = comments.enumerated().map { id, comment in
            let lines = comment.text.components(separatedBy: "\n")
            let paragraphs = lines.enumerated().map { index, text in
                let identifier = index == lines.count - 1 ? " w14:paraId=\"\(paragraphID(id))\"" : ""
                return "<w:p\(identifier)><w:r><w:t xml:space=\"preserve\">\(DOCX.xml(text))</w:t></w:r></w:p>"
            }.joined()
            return "<w:comment w:id=\"\(id)\" w:author=\"\(DOCX.xml(comment.author))\">\(paragraphs)</w:comment>"
        }.joined()
        return "<w:comments xmlns:w=\"\(DOCX.wordNS)\" xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\" xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" mc:Ignorable=\"w14\">\(contents)</w:comments>"
    }
}

final class DOCXCommentsReader: NSObject, XMLParserDelegate {
    struct Value { let id: String; let text: String; let author: String; let paragraphID: String? }
    var values: [Value] = []
    private var id: String?, paragraphID: String?, author = "", text = "", collecting = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        guard namespaceURI == DOCX.wordNS else { return }
        switch name {
        case "comment": id = a["w:id"] ?? a["id"]; author = a["w:author"] ?? a["author"] ?? ""; text = ""; paragraphID = nil
        case "p": if id != nil { paragraphID = a["w14:paraId"]?.uppercased() }
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
            if let id { values.append(Value(id: id, text: text.hasSuffix("\n") ? String(text.dropLast()) : text, author: author, paragraphID: paragraphID)) }
            id = nil; collecting = false
        default: break
        }
    }
}

/// Word 2013's commentEx joins to the final comment paragraph through w14:paraId.
final class DOCXCommentResolutionReader: NSObject, XMLParserDelegate {
    var resolved: [String: Bool] = [:]
    var hasReplies = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        guard namespaceURI == "http://schemas.microsoft.com/office/word/2012/wordml", name == "commentEx", let id = a["w15:paraId"] ?? a["paraId"] else { return }
        resolved[id.uppercased()] = ["1", "true", "on"].contains(a["w15:done"] ?? a["done"] ?? "0")
        if a["w15:paraIdParent"] != nil || a["paraIdParent"] != nil { hasReplies = true }
    }
}
