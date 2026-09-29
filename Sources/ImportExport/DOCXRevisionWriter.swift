import Foundation
import DocumentCore

/// Internal interchange development gate. Public DOCX export continues to reject
/// pending revisions until the complete review workflow can round-trip them.
enum DOCXRevisionExport {
    case disabled
    case textChanges
}

final class DOCXRevisionWriter {
    private var nextID = 0
    private let dates = ISO8601DateFormatter()

    static func validate(_ document: ScribeDocument, mode: DOCXRevisionExport) throws {
        guard document.hasPendingRevisions else { return }
        guard mode == .textChanges else {
            throw DocumentError.invalid("tracked-change DOCX export is still being implemented")
        }
        for paragraph in document.paragraphs + document.notes.flatMap(\.paragraphs) {
            guard paragraph.breakReview?.pendingIDs.isEmpty ?? true,
                  paragraph.formattingReview?.pendingIDs.isEmpty ?? true else {
                throw DocumentError.invalid("DOCX paragraph revision export is not yet supported")
            }
            for run in paragraph.runs {
                guard let review = run.review, !review.isEmpty else { continue }
                for identity in [review.insertion, review.deletion].compactMap({ $0 }) {
                    try DocumentMetadata.validateText(identity.author.name)
                    guard (-62_135_596_800..<253_402_300_800).contains(identity.date.timeIntervalSince1970) else {
                        throw DocumentError.invalid("DOCX revision dates must be within years 1 through 9999")
                    }
                }
                guard review.formatting.isEmpty else {
                    throw DocumentError.invalid("DOCX formatting revision export is not yet supported")
                }
                guard review.insertion == nil || review.deletion == nil else {
                    throw DocumentError.invalid("DOCX overlapping insertion and deletion export is not yet supported")
                }
                guard run.image == nil, run.equation == nil, run.noteID == nil else {
                    throw DocumentError.invalid("DOCX object revision export is not yet supported")
                }
            }
        }
    }

    /// Every emitted XML annotation has a distinct numeric ID, including when
    /// comment boundaries split a native revision. Native compound group IDs are
    /// not represented by this initial Office text-revision prototype.
    func wrap(_ content: String, review: RunReview?) -> String {
        guard let identity = review?.deletion ?? review?.insertion else { return content }
        let tag = review?.deletion == nil ? "ins" : "del"
        let id = nextID; nextID += 1
        let author = DOCX.xml(identity.author.name)
            .replacingOccurrences(of: "\t", with: "&#9;")
            .replacingOccurrences(of: "\n", with: "&#10;")
            .replacingOccurrences(of: "\r", with: "&#13;")
        return "<w:\(tag) w:id=\"\(id)\" w:author=\"\(author)\" w:date=\"\(dates.string(from: identity.date))\">\(content)</w:\(tag)>"
    }
}
