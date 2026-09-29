#if canImport(AppKit)
import AppKit

/// Find and revision marks belong to the editing surface, not printed formatting.
@MainActor final class ScreenTextAttributes: NSObject, NSLayoutManagerDelegate {
    private let reviewDrawing = ReviewDrawingAttributes()
    nonisolated func layoutManager(_ layoutManager: NSLayoutManager, shouldUseTemporaryAttributes attributes: [NSAttributedString.Key: Any], forDrawingToScreen toScreen: Bool, atCharacterIndex index: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any]? {
        MainActor.assumeIsolated {
            toScreen ? reviewDrawing.attributes(attributes, storage: layoutManager.textStorage, at: index, effectiveRange: range) : nil
        }
    }
}
#endif
