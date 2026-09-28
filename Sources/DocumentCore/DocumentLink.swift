import Foundation

/// Stable internal destinations use paragraph IDs, never mutable heading names or offsets.
public enum DocumentLink {
    public static func paragraph(_ id: UUID) -> String { "scribe://paragraph/" + id.uuidString }
    public static func paragraphID(_ value: String) -> UUID? {
        guard let url = URL(string: value), url.scheme?.lowercased() == "scribe",
              url.host == "paragraph", url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2 else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
    public static func officeBookmark(_ id: UUID) -> String {
        "Scribe_" + id.uuidString.replacingOccurrences(of: "-", with: "")
    }
}
