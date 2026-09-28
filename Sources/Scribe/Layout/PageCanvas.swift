#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class PageCanvas: NSView {
    var pageSettings = PageSettings()
    var pageCount = 1
    let gap: CGFloat = 24
    var header = ""
    var footer = ""
    var pageNumbering: PageNumbering?
    override var isFlipped: Bool { true }
    var pageSize: NSSize { NSSize(width: pageSettings.width, height: pageSettings.height) }
    func pageRect(_ index: Int) -> NSRect {
        NSRect(x: max(gap, (bounds.width - pageSize.width) / 2), y: gap + CGFloat(index) * (pageSize.height + gap), width: pageSize.width, height: pageSize.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); dirtyRect.fill()
        for i in 0..<pageCount {
            let rect = pageRect(i)
            guard rect.intersects(dirtyRect) else { continue }
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.13)
            shadow.shadowBlurRadius = 3; shadow.shadowOffset = NSSize(width: 0, height: -1); shadow.set()
            NSColor.white.setFill(); rect.fill()
            NSGraphicsContext.restoreGraphicsState()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray]
            (header as NSString).draw(at: NSPoint(x: rect.minX + pageSettings.left, y: rect.minY + 30), withAttributes: attrs)
            (footer as NSString).draw(at: NSPoint(x: rect.minX + pageSettings.left, y: rect.maxY - 38), withAttributes: attrs)
            drawPageNumber(index: i, origin: rect.origin)
        }
    }
    func drawPageNumber(index: Int, origin: NSPoint) {
        guard let numbering = pageNumbering else { return }
        let label = numbering.label(pageIndex: index, pageCount: pageCount) as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray]
        let width = label.size(withAttributes: attrs).width
        let x: CGFloat
        switch numbering.position {
        case .topLeft, .bottomLeft: x = pageSettings.left
        case .topCenter, .bottomCenter: x = (pageSettings.width - width) / 2
        case .topRight, .bottomRight: x = pageSettings.width - pageSettings.right - width
        }
        let y = [.topLeft, .topCenter, .topRight].contains(numbering.position) ? 30.0 : pageSettings.height - 38
        label.draw(at: NSPoint(x: origin.x + x, y: origin.y + y), withAttributes: attrs)
    }
}

@MainActor final class PaginatedEditor: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
    let storage = NSTextStorage()
    let layout = NSLayoutManager()
    let canvas = PageCanvas()
    let scrollView = NSScrollView()
    private(set) var textViews: [ScribeTextView] = []
    private(set) var layoutWarning: String?
    var onChange: (() -> Void)?
    var onSelection: (() -> Void)?
    weak var owner: ScribeFileDocument?
    private var relayout: DispatchWorkItem?
    private var isLayingOut = false
    var zoom: CGFloat = 1 { didSet { scrollView.setMagnification(zoom, centeredAt: scrollView.documentVisibleRect.origin); resizeCanvas() } }
    var activeTextView: ScribeTextView {
        (canvas.window?.firstResponder as? ScribeTextView) ?? textViews.first!
    }
    init(document: ScribeFileDocument) {
        owner = document
        super.init()
        canvas.pageSettings = document.model.sections[0].page
        canvas.pageNumbering = document.model.sections[0].pageNumbering
        canvas.header = document.model.sections[0].header; canvas.footer = document.model.sections[0].footer
        storage.addLayoutManager(layout); layout.delegate = self
        layout.allowsNonContiguousLayout = true
        storage.setAttributedString(AttributedDocument.render(document.model))
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true; scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true; scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.5; scrollView.maxMagnification = 2
        scrollView.drawsBackground = true; scrollView.backgroundColor = .windowBackgroundColor
        addPage(); paginate()
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged), name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        scrollView.contentView.postsFrameChangedNotifications = true
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    private func addPage() {
        let p = canvas.pageSettings
        let container = NSTextContainer(containerSize: NSSize(width: p.contentWidth, height: p.contentHeight))
        container.widthTracksTextView = false; container.heightTracksTextView = false; container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let view = ScribeTextView(frame: .zero, textContainer: container)
        view.delegate = self; view.editor = self
        view.registerForDraggedTypes([.fileURL])
        view.isRichText = true; view.importsGraphics = false; view.allowsUndo = true
        view.isVerticallyResizable = false; view.isHorizontallyResizable = false
        view.textContainerInset = .zero; view.drawsBackground = false
        view.insertionPointColor = .black; view.appearance = NSAppearance(named: .aqua)
        view.isContinuousSpellCheckingEnabled = true
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = true
        view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = true
        view.typingAttributes = AttributedDocument.attributes(style: owner?.model.styles.first ?? .normal)
        view.setAccessibilityLabel("Document page \(textViews.count + 1)")
        textViews.append(view); canvas.addSubview(view)
    }
    func paginate() {
        guard !isLayingOut else { return }
        isLayingOut = true; defer { isLayingOut = false }
        // TextKit invalidates from the edited glyph; existing page containers are reused.
        layoutWarning = nil
        var required = 1
        var lastEnd = -1
        for index in 0..<2000 {
            if index >= textViews.count { addPage() }
            let container = layout.textContainers[index]
            layout.ensureLayout(for: container)
            let range = layout.glyphRange(for: container)
            required = index + 1
            if range.length == 0 && NSMaxRange(range) < layout.numberOfGlyphs && lastEnd == range.location {
                layoutWarning = "Content cannot fit on this page. Reduce its size or increase the writing area."
                break
            }
            lastEnd = NSMaxRange(range)
            if NSMaxRange(range) >= layout.numberOfGlyphs {
                // A trailing newline may need a final empty page for its insertion point.
                if storage.string.hasSuffix("\n"), layout.extraLineFragmentTextContainer == nil, range.length > 0 {
                    continue
                }
                break
            }
        }
        if lastEnd < layout.numberOfGlyphs && layoutWarning == nil { layoutWarning = "This document exceeds the current 2,000-page layout limit." }
        while textViews.count > required {
            let last = textViews.removeLast()
            if canvas.window?.firstResponder === last { canvas.window?.makeFirstResponder(textViews.last) }
            last.removeFromSuperview(); layout.removeTextContainer(at: layout.textContainers.count - 1)
        }
        canvas.pageCount = textViews.count; resizeCanvas()
        onSelection?()
    }
    @objc func viewportChanged() { resizeCanvas() }
    func resizeCanvas() {
        let p = canvas.pageSettings
        let width = max(p.width + 48, scrollView.contentSize.width / scrollView.magnification)
        canvas.setFrameSize(NSSize(width: width, height: CGFloat(textViews.count) * (p.height + canvas.gap) + canvas.gap))
        for (index, view) in textViews.enumerated() {
            let rect = canvas.pageRect(index)
            view.frame = NSRect(x: rect.minX + p.left, y: rect.minY + p.top, width: p.contentWidth, height: p.contentHeight)
        }
        canvas.needsDisplay = true
    }
    func setPageSettings(_ settings: PageSettings) {
        canvas.pageSettings = settings
        for container in layout.textContainers { container.containerSize = NSSize(width: settings.contentWidth, height: settings.contentHeight) }
        paginate()
    }
    func textDidChange(_ notification: Notification) {
        relayout?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.paginate() }
        relayout = job; DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: job)
        onChange?()
    }
    func textViewDidChangeSelection(_ notification: Notification) { onSelection?() }
    func undoManager(for view: NSTextView) -> UndoManager? { owner?.undoManager }
    nonisolated func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        MainActor.assumeIsolated {
            if (storage.string as NSString).character(at: charIndex) == 12 { return .containerBreak }
            return action
        }
    }
    func select(_ range: NSRange) {
        guard range.location <= storage.length else { return }
        paginate()
        if storage.length == 0 { canvas.window?.makeFirstResponder(textViews[0]); textViews[0].setSelectedRange(NSRange(location: 0, length: 0)); return }
        let glyph = layout.glyphIndexForCharacter(at: min(range.location, max(0, storage.length - 1)))
        let container = layout.textContainer(forGlyphAt: glyph, effectiveRange: nil)
        let view = textViews.first { $0.textContainer === container } ?? textViews[0]
        canvas.window?.makeFirstResponder(view); view.setSelectedRange(range); view.scrollRangeToVisible(range)
    }
    func jump(to id: UUID) {
        var found: NSRange?
        storage.enumerateAttribute(.scribeParagraphID, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value as? String == id.uuidString { found = range; stop.pointee = true }
        }
        if let found { select(NSRange(location: found.location, length: 0)) }
    }
}
#endif
