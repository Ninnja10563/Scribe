import Foundation
import DocumentCore

/// Internal interchange development gate. Public DOCX export continues to reject
/// pending revisions until the complete review workflow can round-trip them.
enum DOCXRevisionExport {
    case disabled
    case runChanges
}

final class DOCXRevisionWriter {
    private var nextID = 0
    private let dates = ISO8601DateFormatter()

    static func validate(_ document: ScribeDocument, mode: DOCXRevisionExport) throws {
        guard document.hasPendingRevisions else { return }
        guard mode == .runChanges else {
            throw DocumentError.invalid("tracked-change DOCX export is still being implemented")
        }
        for paragraph in document.paragraphs + document.notes.flatMap(\.paragraphs) {
            if let history = paragraph.formattingReview, !history.pendingIDs.isEmpty {
                guard history.changes.count == 1, let change = history.changes.first,
                      change.before.list == nil, change.after.list == nil, paragraph.toc == nil else {
                    throw DocumentError.invalid("DOCX layered, list and generated paragraph revisions are not yet supported")
                }
                let before = change.before.formatting ?? change.inheritedBefore
                let after = change.after.formatting ?? change.inheritedAfter
                let beforeGap: Double = before.lineHeight == nil ? 3 : 0
                let afterGap: Double = after.lineHeight == nil ? 3 : 0
                guard before.lineSpacing == after.lineSpacing,
                      before.lineSpacing == beforeGap, after.lineSpacing == afterGap else {
                    throw DocumentError.invalid("DOCX cannot preserve this additional-line-spacing revision")
                }
                try validateIdentity(change.identity)
            }
            for identity in [paragraph.breakReview?.insertion, paragraph.breakReview?.deletion].compactMap({ $0 }) {
                try validateIdentity(identity)
            }
            for run in paragraph.runs {
                guard let review = run.review, !review.isEmpty else { continue }
                for identity in [review.insertion, review.deletion].compactMap({ $0 }) + review.formatting.map(\.identity) {
                    try validateIdentity(identity)
                }
                guard review.formatting.count <= 1 else {
                    throw DocumentError.invalid("DOCX layered formatting revision export is not yet supported")
                }
                guard review.formatting.isEmpty || (run.image == nil && run.equation == nil && run.noteID == nil) else {
                    throw DocumentError.invalid("DOCX object formatting revision export is not yet supported")
                }
            }
        }
    }

    private static func validateIdentity(_ identity: RevisionIdentity) throws {
        try DocumentMetadata.validateText(identity.author.name)
        guard (-62_135_596_800..<253_402_300_800).contains(identity.date.timeIntervalSince1970) else {
            throw DocumentError.invalid("DOCX revision dates must be within years 1 through 9999")
        }
    }

    func paragraphMark(_ review: RunReview?) -> String {
        var content = ""
        if let insertion = review?.insertion { content += "<w:ins \(attributes(insertion))/>" }
        if let deletion = review?.deletion { content += "<w:del \(attributes(deletion))/>" }
        return content.isEmpty ? "" : "<w:rPr>\(content)</w:rPr>"
    }

    func paragraphProperties(_ review: ParagraphFormattingReview?) -> String {
        guard let change = review?.changes.first(where: { !$0.accepted }) else { return "" }
        let before = change.before
        var properties = "<w:pStyle w:val=\"\(DOCX.xml(before.styleID))\"/>"
        if before.pageBreakBefore { properties += "<w:pageBreakBefore/>" }
        if let format = before.formatting { properties += DOCX.paragraphProperties(format) }
        return "<w:pPrChange \(attributes(change.identity))><w:pPr>\(properties)</w:pPr></w:pPrChange>"
    }

    /// Every emitted XML annotation has a distinct numeric ID, including when
    /// comment boundaries split a native revision. Native compound group IDs are
    /// not represented by this initial Office text-revision prototype.
    func wrap(_ content: String, review: RunReview?) -> String {
        var content = content
        if let deletion = review?.deletion {
            content = "<w:del \(attributes(deletion))>\(content)</w:del>"
        }
        if let insertion = review?.insertion {
            content = "<w:ins \(attributes(insertion))>\(content)</w:ins>"
        }
        return content
    }

    func properties(_ run: TextRun) -> String {
        var properties = DOCX.runProperties(run.format)
        if let change = run.review?.formatting.first {
            properties += "<w:rPrChange \(attributes(change.identity))><w:rPr>\(DOCX.runProperties(change.before))</w:rPr></w:rPrChange>"
        }
        return properties
    }

    private func attributes(_ identity: RevisionIdentity) -> String {
        let id = nextID; nextID += 1
        let author = DOCX.xml(identity.author.name)
            .replacingOccurrences(of: "\t", with: "&#9;")
            .replacingOccurrences(of: "\n", with: "&#10;")
            .replacingOccurrences(of: "\r", with: "&#13;")
        return "w:id=\"\(id)\" w:author=\"\(author)\" w:date=\"\(dates.string(from: identity.date))\""
    }
}
