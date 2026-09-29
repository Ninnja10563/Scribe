import Foundation

/// Chooses a prefix of measured TextKit lines, never estimated character counts.
/// A reference and its note must fit together. Reserving only the notes of a
/// previously laid-out page can oscillate when a reference moves to the next page.
struct FootnotePagePlan {
    struct Line {
        let bottom: Double
        let noteIDs: [UUID]
    }
    let lineCount: Int
    let bodyHeight: Double
    let noteIDs: [UUID]
    let noteHeight: Double
    let needsContinuation: Bool

    static func choose(lines: [Line], pageHeight: Double, noteHeights: [UUID: Double], separatorHeight: Double = 12) throws -> FootnotePagePlan {
        guard pageHeight.isFinite, pageHeight > 0, separatorHeight.isFinite, separatorHeight >= 0,
              noteHeights.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw PlanError.invalidGeometry }
        var previousBottom = 0.0, encountered = Set<UUID>()
        for line in lines {
            guard line.bottom.isFinite, line.bottom >= previousBottom else { throw PlanError.invalidGeometry }
            previousBottom = line.bottom
            for id in line.noteIDs {
                guard encountered.insert(id).inserted, noteHeights[id] != nil else { throw PlanError.invalidReferences }
            }
        }
        var count = 0, ids: [UUID] = [], height = 0.0
        for line in lines {
            let added = line.noteIDs.reduce(0.0) { $0 + noteHeights[$1]! }
            let candidate = height + added + (ids.isEmpty && !line.noteIDs.isEmpty ? separatorHeight : 0)
            guard line.bottom + candidate <= pageHeight else { break }
            count += 1; ids += line.noteIDs; height = candidate
        }
        let requiresContinuation = count == 0 && lines.first.map { !$0.noteIDs.isEmpty && $0.bottom <= pageHeight } == true
        // The next reference's line must remain outside this container, even if
        // it would fit without reserving the additional note it introduces.
        let nextLimit = count < lines.count ? max(0, lines[count].bottom - 0.01) : pageHeight
        return FootnotePagePlan(lineCount: count, bodyHeight: max(0, min(pageHeight - height, nextLimit)), noteIDs: ids, noteHeight: height, needsContinuation: requiresContinuation)
    }
    enum PlanError: Error { case invalidGeometry, invalidReferences }
}
