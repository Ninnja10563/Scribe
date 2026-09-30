#if canImport(AppKit)
import AppKit

@MainActor enum ChromeAnimation {
    static func reveal(_ view: NSView, reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        guard view.isHidden else { return }
        view.isHidden = false
        guard !reduceMotion else { view.alphaValue = 1; return }
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            view.animator().alphaValue = 1
        }
    }
}
extension EditorWindowController {
    @objc func toggleFormatting() {
        if formattingSidebar.isHidden { showFonts() }
        else { formattingSidebar.isHidden = true; window?.makeFirstResponder(editor.activeTextView) }
    }
}
#endif
