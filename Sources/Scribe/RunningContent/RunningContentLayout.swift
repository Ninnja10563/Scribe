#if canImport(AppKit)
import AppKit

@MainActor enum RunningContentLayout {
    static var attributes: [NSAttributedString.Key: Any] { [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray] }
    static func warning(for canvas: PageCanvas) -> String? {
        for page in 0..<min(canvas.pageCount, 3) {
            for isHeader in [true, false] {
                let text = canvas.runningText(isHeader: isHeader, pageIndex: page)
                guard !text.isEmpty else { continue }
                let name = isHeader ? "header" : "footer"
                if (isHeader ? canvas.pageSettings.top < 48 : canvas.pageSettings.bottom < 44) {
                    return "The page margin is too small for the \(name). Increase the \(isHeader ? "top" : "bottom") margin in Page Layout before PDF export or printing."
                }
                if text.rangeOfCharacter(from: .newlines) != nil || (text as NSString).size(withAttributes: attributes).width > canvas.pageSettings.contentWidth + 0.01 {
                    return "The \(name) on page \(page + 1) does not fit on one line. Shorten it in Headers and Footers or increase the page width before PDF export or printing."
                }
            }
        }
        return nil
    }
    static func draw(_ text: String, at point: NSPoint, width: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: point.x, y: point.y, width: width, height: 18)).addClip()
        (text as NSString).draw(at: point, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
}
#endif
