import Foundation

extension NativeFormat {
    static func validateReviews(_ document: ScribeDocument) throws {
        var identities: [UUID: (RevisionIdentity, Int)] = [:]
        var groups: [UUID: RevisionIdentity] = [:]
        func record(_ identity: RevisionIdentity, kind: Int) throws {
            guard identity.author.name.utf8.count <= 1024, identity.date.timeIntervalSince1970.isFinite else { throw DocumentError.invalid("invalid revision author or date") }
            if let existing = identities[identity.id] {
                guard existing.0 == identity, existing.1 == kind else { throw DocumentError.invalid("conflicting revision identity") }
            } else { identities[identity.id] = (identity, kind) }
            if let group = identity.groupID {
                if let existing = groups[group] {
                    guard existing.author == identity.author, existing.date == identity.date else {
                        throw DocumentError.invalid("conflicting revision group author or date")
                    }
                } else { groups[group] = identity }
            }
            guard identities.count <= 100_000 else { throw DocumentError.invalid("too many tracked changes") }
        }
        for flow in document.sections.map(\.paragraphs) + document.notes.map(\.paragraphs) {
            for (index, paragraph) in flow.enumerated() {
                guard let review = paragraph.breakReview else { continue }
                guard index + 1 < flow.count, review.formatting.isEmpty, review.formattingBase == nil,
                      paragraph.tableCell == flow[index + 1].tableCell,
                      paragraph.toc == nil, flow[index + 1].toc == nil else {
                    throw DocumentError.invalid("invalid tracked paragraph separator")
                }
                if let insertion = review.insertion { try record(insertion, kind: 0) }
                if let deletion = review.deletion { try record(deletion, kind: 1) }
            }
        }
        for paragraph in document.paragraphs + document.notes.flatMap(\.paragraphs) {
            if let review = paragraph.formattingReview {
                guard !review.pendingIDs.isEmpty, review.changes.count <= 1024 else { throw DocumentError.invalid("invalid paragraph formatting history") }
                func validate(_ state: ParagraphRevisionState) throws {
                    guard document.styles.contains(where: { $0.id == state.styleID }) else { throw DocumentError.invalid("missing revision paragraph style") }
                    if let format = state.formatting { try validateParagraph(format) }
                    if let list = state.list, !(0...8).contains(list.level) || !(1...1_000_000).contains(list.start) { throw DocumentError.invalid("invalid revision list") }
                }
                try validate(review.base); try validateParagraph(review.inheritedBase)
                var seen = Set<UUID>()
                for change in review.changes {
                    guard seen.insert(change.identity.id).inserted, change.before != change.after else { throw DocumentError.invalid("duplicate or empty paragraph formatting revision") }
                    try record(change.identity, kind: 3)
                    try validate(change.before); try validate(change.after)
                    try validateParagraph(change.inheritedBefore); try validateParagraph(change.inheritedAfter)
                }
                guard review.state == ParagraphRevisionState(paragraph) else { throw DocumentError.invalid("paragraph formatting does not match its history") }
            }
            for run in paragraph.runs {
                guard let review = run.review else { continue }
                guard !run.text.isEmpty, review.formatting.count <= 1024 else { throw DocumentError.invalid("invalid revision extent or formatting history") }
                if let insertion = review.insertion { try record(insertion, kind: 0) }
                if let deletion = review.deletion { try record(deletion, kind: 1) }
                guard review.formatting.isEmpty == (review.formattingBase == nil) else { throw DocumentError.invalid("missing revision formatting baseline") }
                if let base = review.formattingBase {
                    guard review.formatting.contains(where: { !$0.accepted }) else { throw DocumentError.invalid("resolved formatting history must be compacted") }
                    try validateText(base)
                    var effective = base, seen = Set<UUID>()
                    for change in review.formatting {
                        guard seen.insert(change.identity.id).inserted else { throw DocumentError.invalid("duplicate formatting revision on a run") }
                        try record(change.identity, kind: 2)
                        try validateText(change.before); try validateText(change.after)
                        effective = effective.applyingDifference(from: change.before, to: change.after)
                    }
                    let inherited = document.style(for: paragraph).text
                    guard effective.materialized(over: inherited) == run.format.materialized(over: inherited) else { throw DocumentError.invalid("revision formatting does not match its history") }
                }
            }
        }
    }
}
