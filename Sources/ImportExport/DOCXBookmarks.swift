import Foundation
import DocumentCore

/// Office bookmark names have a restricted alphabet and length. Native names are
/// retained when possible; legacy/imported names are normalized without collisions.
struct DOCXBookmarks {
    private var markers: [UUID: String] = [:]
    private var names: [UUID: String] = [:]
    init(_ document: ScribeDocument, startingID: Int, reservedNames: Set<String>) {
        var used = Set(reservedNames.map { $0.lowercased() }), next = startingID
        let paragraphs = Set(document.paragraphs.map(\.id))
        for bookmark in document.bookmarks where paragraphs.contains(bookmark.anchor.paragraphID) {
            var base = String(bookmark.name.unicodeScalars.map { scalar -> Character in
                let value = scalar.value
                return (65...90).contains(value) || (97...122).contains(value) || (48...57).contains(value) || value == 95 ? Character(String(scalar)) : "_"
            }.prefix(40))
            if base.isEmpty || !(base.first!.isLetter) { base = "B_" + base }
            base = String(base.prefix(40))
            var name = base, suffix = 1
            while used.contains(name.lowercased()) {
                let ending = "_\(suffix)"; name = String(base.prefix(40 - ending.count)) + ending; suffix += 1
            }
            used.insert(name.lowercased()); names[bookmark.id] = name
            markers[bookmark.anchor.paragraphID, default: ""] += "<w:bookmarkStart w:id=\"\(next)\" w:name=\"\(DOCX.xml(name))\"/><w:bookmarkEnd w:id=\"\(next)\"/>"
            next += 1
        }
    }
    func markers(at paragraphID: UUID) -> String { markers[paragraphID] ?? "" }
    func name(for bookmarkID: UUID) -> String? { names[bookmarkID] }
}
