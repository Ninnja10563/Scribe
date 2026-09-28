import Foundation
import DocumentCore

/// A real Word TOC field surrounds the cached generated paragraphs. Heading links
/// remain ordinary Office bookmark links, so the cache is useful before field refresh.
struct DOCXTableOfContents {
    private var starts: [UUID: String] = [:]
    private var ends: Set<UUID> = []
    init(document: ScribeDocument) {
        let groups = Dictionary(grouping: document.paragraphs.filter { $0.toc != nil && $0.toc?.kind != .title }) { $0.toc!.tableID }
        for definition in document.tablesOfContents {
            guard let group = groups[definition.id], let first = group.first, let last = group.last else { continue }
            let instruction = " TOC \\o \"1-\(definition.maximumLevel)\" \\h \\z \\u "
            starts[first.id] = "<w:r><w:fldChar w:fldCharType=\"begin\" w:dirty=\"true\"/></w:r><w:r><w:instrText xml:space=\"preserve\">\(DOCX.xml(instruction))</w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
            ends.insert(last.id)
        }
    }
    func start(_ id: UUID) -> String { starts[id] ?? "" }
    func end(_ id: UUID) -> String { ends.contains(id) ? "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>" : "" }
}
