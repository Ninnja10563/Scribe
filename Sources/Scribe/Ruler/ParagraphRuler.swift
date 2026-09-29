#if canImport(AppKit)
import AppKit
import DocumentCore

/// A native scroll-view ruler. Only model-supported paragraph indents are editable.
@MainActor final class ParagraphRuler: NSRulerView {
    weak var editor: PaginatedEditor?
    private(set) var handles: [IndentHandle] = []
    private var writingOrigin: CGFloat = 0
    private var writingWidth: CGFloat = 0
    private var scale: CGFloat = 1
    private(set) var selectionRevision = 0
    private(set) var selectionRange = NSRange(location: 0, length: 0)
    override var isFlipped: Bool { true }
    init(editor: PaginatedEditor) {
        self.editor = editor
        super.init(scrollView: editor.scrollView, orientation: .horizontalRuler)
        clipsToBounds = true
        ruleThickness = 36; reservedThicknessForMarkers = 0
        clientView = editor.canvas
        for indent in ParagraphIndent.allCases {
            let handle = IndentHandle(indent: indent, ruler: self)
            handles.append(handle); addSubview(handle)
        }
        setAccessibilityLabel("Paragraph ruler, in points")
    }
    required init(coder: NSCoder) { fatalError("Programmatic ruler only") }
    func refresh() {
        guard let editor, !editor.textViews.isEmpty else { return }
        // A drag owns its preview until mouse-up or cancellation.
        guard !handles.contains(where: \.isDragging) else { updateGeometry(); return }
        let view = editor.activeTextView, selection = view.selectedRange()
        selectionRevision = editor.revision; selectionRange = selection
        var formats: [ParagraphFormatting] = [], supported = true
        func collect(_ attributes: [NSAttributedString.Key: Any]) {
            if attributes[.scribeList] != nil || attributes[.scribeCell] != nil || attributes[.scribeTOC] != nil { supported = false }
            let p = attributes[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle.default
            var format = ParagraphFormatting()
            format.firstLineIndent = p.firstLineHeadIndent; format.headIndent = p.headIndent; format.tailIndent = -p.tailIndent
            formats.append(format)
        }
        if selection.location < editor.storage.length {
            let range = NSRange(location: selection.location, length: max(1, min(selection.length, editor.storage.length - selection.location)))
            editor.storage.enumerateAttributes(in: range) { attributes, _, _ in collect(attributes) }
        } else { collect(view.typingAttributes) }
        for handle in handles {
            let values = formats.map { handle.indent.value(in: $0) }
            handle.value = values.first ?? 0
            handle.maximum = formats.map { handle.indent.maximum(in: $0, width: editor.canvas.pageSettings.contentWidth) }.min() ?? 0
            handle.isEnabled = supported && !formats.isEmpty
            handle.isMixed = values.contains { abs($0 - handle.value) > 0.01 }
            handle.updateAccessibility()
        }
        toolTip = supported ? "Measurements in points. Drag a marker; use arrow keys for 1 point or Shift-arrow for 6 points. Escape cancels a drag." : "Use list, table or table-of-contents controls for this selection."
        updateGeometry()
    }
    func updateGeometry() {
        guard let editor, !editor.textViews.isEmpty else { return }
        let page = editor.canvas.pageRect(0), settings = editor.canvas.pageSettings
        let start = convert(NSPoint(x: page.minX + settings.left, y: 0), from: editor.canvas)
        let end = convert(NSPoint(x: page.minX + settings.left + settings.contentWidth, y: 0), from: editor.canvas)
        writingOrigin = start.x; writingWidth = end.x - start.x
        scale = writingWidth / settings.contentWidth
        for handle in handles {
            let position = handle.indent == .right ? settings.contentWidth - handle.value : handle.value
            handle.frame = NSRect(x: writingOrigin + position * scale - 8, y: handle.indent == .firstLine ? 0 : 22, width: 16, height: 14)
            handle.needsDisplay = true
        }
        needsDisplay = true
    }
    func value(at point: NSPoint, for indent: ParagraphIndent) -> Double {
        guard scale > 0 else { return 0 }
        let distance = (point.x - writingOrigin) / scale
        return indent == .right ? (editor?.canvas.pageSettings.contentWidth ?? 0) - distance : distance
    }
    func commit(_ handle: IndentHandle, value: Double, revision: Int? = nil, selection: NSRange? = nil) {
        guard let editor, let owner = editor.owner, handle.isEnabled else { return }
        if let revision, revision != editor.revision { refresh(); return }
        if let selection, selection != editor.activeTextView.selectedRange() { refresh(); return }
        let indices = editor.selectedParagraphIndices(), snapshot = owner.snapshot()
        let paragraphs = snapshot.paragraphs
        let ids = Set(indices.compactMap { paragraphs.indices.contains($0) ? paragraphs[$0].id : nil })
        do {
            var after = snapshot
            try after.setParagraphIndent(handle.indent, to: min(handle.maximum, max(0, value)), paragraphIDs: ids)
            owner.performEdit(handle.indent.label) { $0 = after }
        } catch { owner.editorController?.showStatus(error.localizedDescription); NSSound.beep() }
        refresh()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); dirtyRect.intersection(bounds).fill()
        NSColor.textBackgroundColor.setFill()
        NSRect(x: writingOrigin, y: 0, width: writingWidth, height: bounds.height).intersection(bounds).fill()
        guard scale > 0 else { return }
        let step = max(18, ceil(36 / scale / 18) * 18)
        let width = editor?.canvas.pageSettings.contentWidth ?? 0
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
        for value in stride(from: 0.0, through: width, by: step) {
            let x = writingOrigin + value * scale
            guard x >= bounds.minX - 20, x <= bounds.maxX + 20 else { continue }
            NSColor.separatorColor.setFill(); NSRect(x: x, y: 25, width: 1, height: 7).fill()
            let label = String(Int(value)) as NSString
            label.draw(at: NSPoint(x: x - label.size(withAttributes: attrs).width / 2, y: 12), withAttributes: attrs)
        }
        NSColor.separatorColor.setFill(); NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}
#endif
