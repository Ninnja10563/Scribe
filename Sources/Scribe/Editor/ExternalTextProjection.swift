#if canImport(AppKit)
import AppKit

@MainActor enum ExternalTextProjection {
    static func render(_ value: NSAttributedString, includeImages: Bool) throws -> NSAttributedString {
        let text = ScriptProjection.external(value)
        return includeImages ? try ExternalImageProjection.render(text) : text
    }
}
#endif
