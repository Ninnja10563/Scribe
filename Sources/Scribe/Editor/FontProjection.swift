#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum FontProjection {
    static func requestedFace(_ format: TextFormatting, over base: TextFormatting) -> String? {
        format.fontFace ?? (format.fontFamily == nil ? base.fontFace : nil)
    }
    static func font(_ format: TextFormatting, over base: TextFormatting) -> NSFont {
        let size = format.fontSize ?? base.fontSize ?? 12
        let family = format.fontFamily ?? base.fontFamily ?? "Helvetica Neue"
        let face = requestedFace(format, over: base)
        var result = face.flatMap { NSFont(name: $0, size: size) }
            ?? NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)
        // A concrete face already defines its weight/slant. Only direct trait overrides
        // alter it; inherited family-only formatting retains the original behavior.
        let bold = format.bold ?? (face == nil ? base.bold : nil)
        let italic = format.italic ?? (face == nil ? base.italic : nil)
        for (enabled, trait) in [(bold, NSFontTraitMask.boldFontMask), (italic, .italicFontMask)] {
            guard let enabled, NSFontManager.shared.traits(of: result).contains(trait) != enabled else { continue }
            result = enabled ? NSFontManager.shared.convert(result, toHaveTrait: trait)
                : NSFontManager.shared.convert(result, toNotHaveTrait: trait)
        }
        return result
    }
}
#endif
