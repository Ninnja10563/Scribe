#if canImport(AppKit)
import AppKit

/// Find highlights belong to the editing surface, never to printed content.
@MainActor final class ScreenTextAttributes: NSObject, NSLayoutManagerDelegate {
    nonisolated func layoutManager(_ layoutManager: NSLayoutManager, shouldUseTemporaryAttributes attributes: [NSAttributedString.Key: Any], forDrawingToScreen toScreen: Bool, atCharacterIndex index: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any]? {
        toScreen ? attributes : nil
    }
}
#endif
