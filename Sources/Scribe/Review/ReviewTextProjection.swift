#if canImport(AppKit)
import AppKit
import DocumentCore

/// Construct one native replacement before touching the live text storage. Old
/// rich content remains editable review data, including reference attachments.
@MainActor enum ReviewTextProjection {
    static func encoded(_ review: RunReview) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(review)
    }
    static func replacing(_ original: NSAttributedString, with inserted: NSAttributedString,
                          insertion: RevisionIdentity, deletion: RevisionIdentity) throws -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        try append(original, to: result, revision: deletion, deleting: true)
        try append(inserted, to: result, revision: insertion, deleting: false)
        return result
    }
    private static func append(_ source: NSAttributedString, to result: NSMutableAttributedString,
                               revision: RevisionIdentity, deleting: Bool) throws {
        var failure: Error?
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, range, stop in
            do {
                let value = (source.string as NSString).substring(with: range)
                let pieces = value.components(separatedBy: "\n")
                for (index, text) in pieces.enumerated() {
                    if !text.isEmpty { try appendPiece(text, attributes: attributes, separator: false, to: result, revision: revision, deleting: deleting) }
                    if index + 1 < pieces.count { try appendPiece("\n", attributes: attributes, separator: true, to: result, revision: revision, deleting: deleting) }
                }
            } catch { failure = error; stop.pointee = true }
        }
        if let failure { throw failure }
    }
    private static func appendPiece(_ text: String, attributes original: [NSAttributedString.Key: Any], separator: Bool,
                                    to result: NSMutableAttributedString, revision: RevisionIdentity, deleting: Bool) throws {
        let key: NSAttributedString.Key = separator ? .scribeBreakReview : .scribeReview
        var attributes = original, review = RunReview()
        if deleting, let data = original[key] as? Data { review = try JSONDecoder().decode(RunReview.self, from: data) }
        if deleting {
            if review.insertion?.author.id == revision.author.id, review.deletion == nil { return }
            if review.deletion == nil { review.deletion = revision }
        } else { review.insertion = revision }
        attributes.removeValue(forKey: .scribeReview); attributes.removeValue(forKey: .scribeBreakReview)
        attributes[key] = try encoded(review)
        result.append(NSAttributedString(string: text, attributes: attributes))
    }
}
#endif
