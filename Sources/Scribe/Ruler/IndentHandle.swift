#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class IndentHandle: NSControl {
    let indent: ParagraphIndent
    weak var ruler: ParagraphRuler?
    var value = 0.0
    var maximum = 0.0
    var isMixed = false
    private(set) var isDragging = false
    private var originalValue = 0.0
    private var dragRevision = 0
    private var dragSelection = NSRange(location: 0, length: 0)
    override var acceptsFirstResponder: Bool { isEnabled }
    override var isFlipped: Bool { true }
    init(indent: ParagraphIndent, ruler: ParagraphRuler) {
        self.indent = indent; self.ruler = ruler
        super.init(frame: .zero)
        cell = NSActionCell()
        setAccessibilityElement(true); setAccessibilityRole(.slider)
        setAccessibilityLabel(indent.label)
        setAccessibilityHelp("Measurements in points. Arrow keys change by one point; Shift-arrow changes by six points.")
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("Programmatic handle only") }
    func updateAccessibility() {
        super.setAccessibilityValue(NSNumber(value: value)); setAccessibilityMinValue(0); setAccessibilityMaxValue(NSNumber(value: maximum))
        setAccessibilityEnabled(isEnabled)
        toolTip = "\(indent.label): \(String(format: "%.1f", value)) pt\(isMixed ? " (mixed selection)" : "")"
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        if indent == .firstLine { path.move(to: NSPoint(x: 3, y: 3)); path.line(to: NSPoint(x: 13, y: 3)); path.line(to: NSPoint(x: 8, y: 11)) }
        else { path.move(to: NSPoint(x: 3, y: 11)); path.line(to: NSPoint(x: 13, y: 11)); path.line(to: NSPoint(x: 8, y: 3)) }
        path.close()
        (isEnabled ? NSColor.controlAccentColor : NSColor.disabledControlTextColor).set()
        if isMixed { path.lineWidth = 1.5; path.stroke() } else { path.fill() }
        if window?.firstResponder === self { NSColor.keyboardFocusIndicatorColor.setStroke(); NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).stroke() }
    }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let ruler else { return }
        ruler.refresh(); window?.makeFirstResponder(self)
        originalValue = value; dragRevision = ruler.selectionRevision; dragSelection = ruler.selectionRange
        isDragging = true; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let ruler else { return }
        let raw = ruler.value(at: ruler.convert(event.locationInWindow, from: nil), for: indent)
        value = min(maximum, max(0, event.modifierFlags.contains(.option) ? raw : raw.rounded()))
        ruler.updateGeometry(); updateAccessibility()
        if let editor = ruler.editor, let page = editor.textViews.firstIndex(where: { $0 === editor.activeTextView }) {
            editor.canvas.indentGuide = (page, indent == .right ? editor.canvas.pageSettings.contentWidth - value : value)
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false; ruler?.editor?.canvas.indentGuide = nil
        ruler?.commit(self, value: value, revision: dragRevision, selection: dragSelection)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, isDragging { isDragging = false; value = originalValue; ruler?.editor?.canvas.indentGuide = nil; ruler?.refresh(); return }
        guard isEnabled else { super.keyDown(with: event); return }
        let step = event.modifierFlags.contains(.shift) ? 6.0 : 1.0
        switch event.keyCode {
        case 48:
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        case 53: window?.makeFirstResponder(ruler?.editor?.activeTextView)
        case 123: adjust(by: indent == .right ? step : -step)
        case 124: adjust(by: indent == .right ? -step : step)
        case 125: adjust(by: -step)
        case 126: adjust(by: step)
        default: super.keyDown(with: event)
        }
    }
    private func adjust(by delta: Double) {
        guard isEnabled, !isDragging else { return }
        ruler?.commit(self, value: value + delta)
        window?.makeFirstResponder(self); needsDisplay = true
    }
    override func accessibilityPerformIncrement() -> Bool { guard isEnabled else { return false }; adjust(by: 1); return true }
    override func accessibilityPerformDecrement() -> Bool { guard isEnabled else { return false }; adjust(by: -1); return true }
    override func setAccessibilityValue(_ value: Any?) {
        guard let number = value as? NSNumber, number.doubleValue.isFinite, isEnabled else { return }
        ruler?.commit(self, value: number.doubleValue)
    }
}
#endif
