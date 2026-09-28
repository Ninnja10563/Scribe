import Foundation

public struct DocumentTOC: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var title: String
    public var maximumLevel: Int
    public init(title: String = "Contents", maximumLevel: Int = 3) {
        self.title = title; self.maximumLevel = maximumLevel
    }
}

/// Generated paragraphs retain their association with a TOC and heading. Ordinary
/// paragraphs between entries are never discarded when a table is refreshed.
public struct TOCParagraph: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case title, entry, empty }
    public var tableID: UUID
    public var kind: Kind
    public var headingID: UUID?
    public var level: Int?
    public init(tableID: UUID, kind: Kind, headingID: UUID? = nil, level: Int? = nil) {
        self.tableID = tableID; self.kind = kind; self.headingID = headingID; self.level = level
    }
}

public extension ScribeDocument {
    @discardableResult mutating func insertTableOfContents(after paragraphID: UUID, title: String = "Contents", maximumLevel: Int = 3, pages: [UUID: String] = [:]) -> UUID? {
        guard (1...9).contains(maximumLevel),
              let section = sections.firstIndex(where: { $0.paragraphs.contains(where: { $0.id == paragraphID }) }),
              let position = sections[section].paragraphs.firstIndex(where: { $0.id == paragraphID }) else { return nil }
        let definition = DocumentTOC(title: title, maximumLevel: maximumLevel)
        tablesOfContents.append(definition)
        var insertion = position + 1
        if let tableID = sections[section].paragraphs[position].tableCell?.tableID {
            insertion = (sections[section].paragraphs.lastIndex(where: { $0.tableCell?.tableID == tableID }) ?? position) + 1
        }
        if let tocID = sections[section].paragraphs[position].toc?.tableID {
            insertion = (sections[section].paragraphs.lastIndex(where: { $0.toc?.tableID == tocID }) ?? position) + 1
        }
        var marker = Paragraph(); marker.toc = TOCParagraph(tableID: definition.id, kind: .empty)
        sections[section].paragraphs.insert(marker, at: insertion)
        refreshTableOfContents(id: definition.id, pages: pages)
        return definition.id
    }

    mutating func refreshTableOfContents(id: UUID, pages: [UUID: String]) {
        guard let definition = tablesOfContents.first(where: { $0.id == id }),
              let section = sections.firstIndex(where: { $0.paragraphs.contains(where: { $0.toc?.tableID == id }) }),
              let insertion = sections[section].paragraphs.firstIndex(where: { $0.toc?.tableID == id }) else { return }
        ensureTOCStyles()
        let old = paragraphs.filter { $0.toc?.tableID == id }
        var oldEntries: [UUID: Paragraph] = [:]
        for paragraph in old { if let id = paragraph.toc?.headingID, oldEntries[id] == nil { oldEntries[id] = paragraph } }
        let headings = outline.filter { $0.level <= definition.maximumLevel }
        var generated: [Paragraph] = []
        if !definition.title.isEmpty {
            var title = old.first(where: { $0.toc?.kind == .title }) ?? Paragraph()
            title.styleID = "scribe.toc.title"; title.runs = [TextRun(definition.title)]
            title.toc = TOCParagraph(tableID: id, kind: .title); generated.append(title)
        }
        for heading in headings {
            var entry = oldEntries[heading.id] ?? Paragraph()
            entry.styleID = "scribe.toc.entry"
            entry.toc = TOCParagraph(tableID: id, kind: .entry, headingID: heading.id, level: heading.level)
            entry.runs = [TextRun(heading.title.isEmpty ? "Untitled heading" : heading.title, link: DocumentLink.paragraph(heading.id)), TextRun("\t" + (pages[heading.id] ?? "—"))]
            generated.append(entry)
        }
        if headings.isEmpty {
            var empty = old.first(where: { $0.toc?.kind == .empty }) ?? Paragraph()
            empty.styleID = "scribe.toc.entry"; empty.runs = [TextRun("No headings to display.")]
            empty.toc = TOCParagraph(tableID: id, kind: .empty); generated.append(empty)
        }
        let generatedText = Dictionary(uniqueKeysWithValues: generated.map { ($0.id, $0.text) })
        let changed = Set(old.filter { generatedText[$0.id] != $0.text }.map(\.id))
        // Review text survives a regenerated field, but must not silently refer to different words.
        for index in comments.indices where changed.contains(comments[index].anchor.paragraphID) || comments[index].anchor.endParagraphID.map(changed.contains) == true {
            comments[index].isDetached = true
        }
        for index in sections.indices { sections[index].paragraphs.removeAll { $0.toc?.tableID == id } }
        sections[section].paragraphs.insert(contentsOf: generated, at: min(insertion, sections[section].paragraphs.count))
        reconcileCommentAnchors()
    }

    mutating func removeTableOfContents(id: UUID) {
        tablesOfContents.removeAll { $0.id == id }
        for index in sections.indices {
            sections[index].paragraphs.removeAll { $0.toc?.tableID == id }
            if sections[index].paragraphs.isEmpty { sections[index].paragraphs = [Paragraph()] }
        }
        reconcileCommentAnchors()
    }

    private mutating func ensureTOCStyles() {
        if !styles.contains(where: { $0.id == "scribe.toc.title" }) {
            var title = ParagraphStyle(id: "scribe.toc.title", name: "Contents Title", size: 20, bold: true)
            title.paragraph.spaceAfter = 12; styles.append(title)
        }
        if !styles.contains(where: { $0.id == "scribe.toc.entry" }) {
            var entry = ParagraphStyle(id: "scribe.toc.entry", name: "Contents Entry")
            entry.text = styles.first(where: { $0.id == "normal" })?.text ?? entry.text
            entry.paragraph.spaceAfter = 4; styles.append(entry)
        }
    }
}
