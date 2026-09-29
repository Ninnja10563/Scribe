#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class PageCanvas: NSView {
    var pageSettings = PageSettings()
    var pageCount = 1
    var footnotes: [Int: FootnoteLayout.Page] = [:]
    var endnotes: EndnoteLayout?
    var bodyPageCount = 1
    let gap: CGFloat = 24
    var header = ""
    var footer = ""
    var pageNumbering: PageNumbering?
    var runningContent: RunningContentVariants?
    var indentGuide: (page: Int, offset: Double)? { didSet { needsDisplay = true } }
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
            RunningContentLayout.draw(runningText(isHeader: true, pageIndex: i), at: NSPoint(x: rect.minX + pageSettings.left, y: rect.minY + 30), width: pageSettings.contentWidth)
            RunningContentLayout.draw(runningText(isHeader: false, pageIndex: i), at: NSPoint(x: rect.minX + pageSettings.left, y: rect.maxY - 38), width: pageSettings.contentWidth)
            drawPageNumber(index: i, origin: rect.origin)
            if let notes = footnotes[i] {
                notes.draw(at: NSPoint(x: rect.minX + pageSettings.left, y: rect.maxY - pageSettings.bottom - notes.height), width: pageSettings.contentWidth)
            }
            endnotes?.draw(page: i - bodyPageCount, at: NSPoint(x: rect.minX + pageSettings.left, y: rect.minY + pageSettings.top))
            if let guide = indentGuide, guide.page == i {
                let line = NSBezierPath(); line.lineWidth = 0.75
                line.move(to: NSPoint(x: rect.minX + pageSettings.left + guide.offset, y: rect.minY + pageSettings.top))
                line.line(to: NSPoint(x: rect.minX + pageSettings.left + guide.offset, y: rect.maxY - pageSettings.bottom))
                NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke(); line.stroke()
            }
        }
    }
    func runningText(isHeader: Bool, pageIndex: Int) -> String {
        let fallback = isHeader ? header : footer
        return runningContent?.text(defaultText: fallback, isHeader: isHeader, pageIndex: pageIndex, startingNumber: pageNumbering?.start ?? runningContent?.startingPageNumber ?? 1) ?? fallback
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

@MainActor final class PaginatedEditor: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate, NSTextStorageDelegate {
    let storage = NSTextStorage()
    let layout = NSLayoutManager()
    let canvas = PageCanvas()
    let noteControls = PageNoteControls()
    let reviewEditing = NativeReviewEditing()
    let scrollView = NSScrollView()
    private(set) var paragraphRuler: ParagraphRuler?
    private(set) var textViews: [ScribeTextView] = []
    private(set) var layoutWarning: String?
    var outputWarning: String? {
        return layoutWarning ?? RunningContentLayout.warning(for: canvas)
    }
    private weak var selectionView: ScribeTextView?
    var onChange: (() -> Void)?
    var onSelection: (() -> Void)?
    var onLayout: (() -> Void)?
    weak var owner: ScribeFileDocument?
    private var relayout: DispatchWorkItem?
    private var isLayingOut = false
    private var noteReferencesMayExist = false
    private var firstDirtyPage = 0
    private var pageCharacterRanges: [NSRange] = []
    private var paginationStability = PaginationStability()
    private(set) var lastPaginationVisitedPages = 0
    private var overflowingPages = Set<Int>()
    private let tableValidation = TableLayoutValidation()
    var drawingPrintLinks = false
    private(set) var revision = 0
    private var semanticCache: (revision: Int, snapshot: SemanticTextSnapshot)?
    var semanticText: SemanticTextSnapshot {
        if let cache = semanticCache, cache.revision == revision { return cache.snapshot }
        let snapshot = SemanticTextSnapshot(storage)
        semanticCache = (revision, snapshot)
        return snapshot
    }
    var zoomMode: DocumentZoomMode = .factor(1)
    var isUpdatingZoom = false
    var activeTextView: ScribeTextView {
        if let focused = canvas.window?.firstResponder as? ScribeTextView, focused.editor === self { return focused }
        if let selected = selectionView, selected.superview === canvas { return selected }
        return textViews.first!
    }
    init(document: ScribeFileDocument, projectedContent: NSAttributedString? = nil) {
        owner = document
        super.init()
        canvas.pageSettings = document.model.sections[0].page
        canvas.pageNumbering = document.model.sections[0].pageNumbering
        canvas.runningContent = document.model.sections[0].runningContent
        canvas.header = document.model.sections[0].header; canvas.footer = document.model.sections[0].footer
        noteControls.editor = self
        storage.delegate = self
        storage.addLayoutManager(layout); layout.delegate = self
        layout.allowsNonContiguousLayout = true
        storage.setAttributedString(projectedContent ?? AttributedDocument.render(document.model))
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true; scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true; scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.025; scrollView.maxMagnification = 2
        scrollView.drawsBackground = true; scrollView.backgroundColor = .windowBackgroundColor
        addPage(); paginate()
        let ruler = ParagraphRuler(editor: self); paragraphRuler = ruler
        scrollView.horizontalRulerView = ruler; scrollView.hasHorizontalRuler = true
        scrollView.rulersVisible = true; ruler.refresh()
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(rulerViewportChanged), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged), name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(userMagnificationChanged), name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    func prepareForClose() {
        relayout?.cancel(); onChange = nil; onSelection = nil; onLayout = nil
        noteControls.clear()
        paragraphRuler?.editor = nil; paragraphRuler?.clientView = nil
        NotificationCenter.default.removeObserver(self)
        for view in textViews { view.cancelSpellingCheck(); view.delegate = nil; view.editor = nil }
        layout.delegate = nil; storage.delegate = nil; owner = nil
    }
    private func addPage() {
        let p = canvas.pageSettings
        let container = NSTextContainer(containerSize: NSSize(width: p.contentWidth, height: p.contentHeight))
        container.widthTracksTextView = false; container.heightTracksTextView = false; container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let savedTypingAttributes = textViews.first?.typingAttributes
        let view = ScribeTextView(frame: NSRect(x: 0, y: 0, width: p.contentWidth, height: p.contentHeight), textContainer: container)
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
        if let savedTypingAttributes { view.typingAttributes = savedTypingAttributes }
        else if storage.length > 0 {
            var attributes = storage.attributes(at: 0, effectiveRange: nil)
            for key in [NSAttributedString.Key.attachment, .scribeImage, .scribeEquation, .scribeNote, .scribeNoteNumber, .scribePageBreakMarker] { attributes.removeValue(forKey: key) }
            view.typingAttributes = attributes
        } else if let document = owner?.model, let paragraph = document.paragraphs.first {
            view.typingAttributes = AttributedDocument.editingAttributes(for: paragraph, in: document)
        } else { view.typingAttributes = AttributedDocument.attributes(style: .normal) }
        view.setAccessibilityLabel("Document page \(textViews.count + 1)")
        textViews.append(view); canvas.addSubview(view)
    }
    func paginate() {
        guard !isLayingOut, firstDirtyPage != Int.max else { return }
        isLayingOut = true; defer { isLayingOut = false; paginationStability.invalidate() }
        lastPaginationVisitedPages = 0
        var stabilized = false
        // TextKit invalidates from the edited glyph; existing page containers are reused.
        layoutWarning = nil
        let hasNotes = noteReferencesMayExist && storage.containsNoteReferences
        noteReferencesMayExist = hasNotes
        var noteLayout: FootnoteLayout?
        if hasNotes {
            paginationStability.invalidate()
            do {
                try NoteProjection.refreshNumbers(in: storage)
                noteLayout = try FootnoteLayout(storage: storage, styles: owner?.model.styles ?? ParagraphStyle.defaults, width: canvas.pageSettings.contentWidth) }
            catch { layoutWarning = error.localizedDescription }
        }
        let hadNotes = !canvas.footnotes.isEmpty
        if hasNotes || hadNotes {
            for container in layout.textContainers {
                container.containerSize.height = canvas.pageSettings.contentHeight
                layout.textContainerChangedGeometry(container)
            }
        }
        canvas.footnotes.removeAll()
        let start = hasNotes || hadNotes ? 0 : max(0, min(firstDirtyPage, textViews.count - 1))
        var required = start + 1
        var lastEnd = -1
        for index in start..<2000 {
            lastPaginationVisitedPages += 1
            if index >= textViews.count { addPage() }
            let container = layout.textContainers[index]
            layout.ensureLayout(for: container)
            var range = layout.glyphRange(for: container)
            if index == textViews.count - 1, index < 1999, NSMaxRange(range) < layout.numberOfGlyphs {
                addPage()
                // A terminal container can fit a final line without its trailing spacing.
                // Once overflow has a successor, recompute this boundary with that
                // successor present, just as TextKit does during later edits.
                layout.textContainerChangedGeometry(container)
                layout.ensureLayout(for: container)
                range = layout.glyphRange(for: container)
            }
            if let noteLayout {
                required = index + 1
                do {
                    canvas.footnotes[index] = try noteLayout.fit(layout: layout, container: container, pageHeight: canvas.pageSettings.contentHeight)
                    range = layout.glyphRange(for: container)
                } catch {
                    layoutWarning = error.localizedDescription
                    break
                }
            }
            overflowingPages.remove(index)
            layout.enumerateLineFragments(forGlyphRange: range) { _, used, lineContainer, _, stop in
                if lineContainer === container && (used.minY < -1 || used.maxY > container.containerSize.height + 1) {
                    self.overflowingPages.insert(index); stop.pointee = true
                }
            }
            let characters = layout.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            if pageCharacterRanges.indices.contains(index) { pageCharacterRanges[index] = characters }
            else { pageCharacterRanges.append(characters) }
            required = index + 1
            if range.length == 0 && NSMaxRange(range) < layout.numberOfGlyphs && lastEnd == range.location && (canvas.footnotes[index]?.notes.isEmpty ?? true) {
                layoutWarning = "Content cannot fit on this page. Reduce its size or increase the writing area."
                break
            }
            lastEnd = NSMaxRange(range)
            if paginationStability.canStop(after: index, characterEnd: NSMaxRange(characters), documentLength: storage.length) {
                let following = paginationStability.remainingRanges(after: index)
                for (offset, range) in following.enumerated() { pageCharacterRanges[index + 1 + offset] = range }
                required = pageCharacterRanges.count; stabilized = true
                break
            }
            if NSMaxRange(range) >= layout.numberOfGlyphs {
                if noteLayout?.hasPendingNotes == true { continue }
                // A trailing newline may need a final empty page for its insertion point.
                if storage.string.hasSuffix("\n"), layout.extraLineFragmentTextContainer == nil, range.length > 0 {
                    continue
                }
                break
            }
        }
        if noteLayout?.hasPendingNotes == true, layoutWarning == nil { layoutWarning = "Footnotes exceed the current 2,000-page layout limit." }
        if layoutWarning == nil, owner?.model.tables.contains(where: { ($0.minimumRowHeights ?? []).compactMap { $0 }.contains { $0 > canvas.pageSettings.contentHeight } }) == true {
            layoutWarning = "A table row's minimum height exceeds the page writing area. Reduce it using Table → Row Height before PDF export or printing."
        }
        overflowingPages = overflowingPages.filter { $0 < required }
        let tallMerge = owner?.model.tables.contains { table in
            (table.mergedCells ?? []).contains { merge in
                (merge.row..<(merge.row + merge.rowSpan)).reduce(0.0) { total, row in
                    total + (table.minimumRowHeights?[row] ?? 0)
                } > canvas.pageSettings.contentHeight
            }
        } ?? false
        let tallCell = owner.map { tableValidation.hasOversizedCell(storage: storage, document: $0.model, pageHeight: canvas.pageSettings.contentHeight) } ?? false
        if layoutWarning == nil, !overflowingPages.isEmpty || tallMerge || tallCell {
            layoutWarning = "A table cell is taller than one page. Move some text to other rows or reduce its size before PDF export or printing."
        }
        if !stabilized && lastEnd < layout.numberOfGlyphs && layoutWarning == nil { layoutWarning = "This document exceeds the current 2,000-page layout limit." }
        while textViews.count > required {
            let last = textViews.removeLast()
            if canvas.window?.firstResponder === last { canvas.window?.makeFirstResponder(textViews.last) }
            last.removeFromSuperview(); layout.removeTextContainer(at: layout.textContainers.count - 1)
        }
        if pageCharacterRanges.count > required { pageCharacterRanges.removeLast(pageCharacterRanges.count - required) }
        if layoutWarning == nil { layoutWarning = EquationProjection.warning(in: self) }
        firstDirtyPage = Int.max
        canvas.endnotes = nil
        if let notes = noteLayout?.endnotes, !notes.isEmpty {
            do { canvas.endnotes = try EndnoteLayout(notes: notes, styles: owner?.model.styles ?? ParagraphStyle.defaults, page: canvas.pageSettings, maximumPages: 2000 - textViews.count) }
            catch { layoutWarning = error.localizedDescription }
        }
        canvas.bodyPageCount = textViews.count
        canvas.pageCount = textViews.count + (canvas.endnotes?.containers.count ?? 0); resizeCanvas()
        onLayout?()
        onSelection?()
    }
    @objc private func rulerViewportChanged() { paragraphRuler?.updateGeometry() }
    @objc func viewportChanged() { refreshZoom(); resizeCanvas() }
    func resizeCanvas() {
        let p = canvas.pageSettings
        let width = max(p.width + 48, scrollView.contentView.frame.width / scrollView.magnification)
        let size = NSSize(width: width, height: CGFloat(canvas.pageCount) * (p.height + canvas.gap) + canvas.gap)
        if canvas.frame.size != size { canvas.setFrameSize(size) }
        for (index, view) in textViews.enumerated() {
            let rect = canvas.pageRect(index)
            let frame = NSRect(x: rect.minX + p.left, y: rect.minY + p.top, width: p.contentWidth, height: layout.textContainers[index].containerSize.height)
            if view.frame != frame { view.frame = frame }
        }
        noteControls.update(in: canvas)
        canvas.needsDisplay = true
        paragraphRuler?.updateGeometry()
    }
    func setPageSettings(_ settings: PageSettings) {
        canvas.pageSettings = settings
        paginationStability.invalidate()
        firstDirtyPage = 0
        for container in layout.textContainers { container.containerSize = NSSize(width: settings.contentWidth, height: settings.contentHeight) }
        resizeCanvas()
        paginate(); refreshZoom()
    }
    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        MainActor.assumeIsolated {
            if !noteReferencesMayExist {
                let range = NSIntersectionRange(editedRange, NSRange(location: 0, length: textStorage.length))
                textStorage.enumerateAttribute(.scribeNote, in: range) { value, _, stop in
                    if value != nil { self.noteReferencesMayExist = true; stop.pointee = true }
                }
            }
            let ends = paginationStability.expectedEnds ?? pageCharacterRanges.map(NSMaxRange)
            let page = ends.firstIndex { $0 >= editedRange.location } ?? max(0, textViews.count - 1)
            let isInsertion = editedMask.contains(.editedCharacters) && delta > 0 && delta <= 128 && editedRange.length == delta && NSMaxRange(editedRange) <= textStorage.length
            let text = isInsertion ? (textStorage.string as NSString).substring(with: editedRange) : ""
            let hasFlowControl = text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || $0.value == 0x2028 || $0.value == 0x2029 || $0.value == 0xfffc }
            if isInsertion && !hasFlowControl && layoutWarning == nil && owner?.model.tables.isEmpty == true && !noteReferencesMayExist {
                paginationStability.insert(at: editedRange.location, length: delta, previousEnds: ends, startingClean: firstDirtyPage == Int.max)
            } else { paginationStability.invalidate() }
            firstDirtyPage = min(firstDirtyPage, max(0, page - 1))
            revision += 1
        }
    }
    func textDidChange(_ notification: Notification) {
        relayout?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.paginate() }
        relayout = job; DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: job)
        if !textViews.contains(where: { $0.reviewComposition != nil }) { onChange?() }
    }
    func rememberSelection(_ view: ScribeTextView) { selectionView = view }
    func textViewDidChangeSelection(_ notification: Notification) {
        // Linked text views broadcast the same selection. Only the focused view identifies
        // its page reliably; passive navigation records its target explicitly in select().
        if let view = notification.object as? ScribeTextView, canvas.window?.firstResponder === view { selectionView = view }
        onSelection?()
    }
    func undoManager(for view: NSTextView) -> UndoManager? { owner?.undoManager }
    nonisolated func layoutManager(_ layoutManager: NSLayoutManager, shouldUseTemporaryAttributes attributes: [NSAttributedString.Key: Any], forDrawingToScreen toScreen: Bool, atCharacterIndex index: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any]? {
        MainActor.assumeIsolated {
            if toScreen { return attributes }
            guard drawingPrintLinks else { return nil }
            return attributes.filter { [.foregroundColor, .underlineStyle, .underlineColor].contains($0.key) }
        }
    }
    nonisolated func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        MainActor.assumeIsolated {
            if (storage.string as NSString).character(at: charIndex) == 12 { return .containerBreak }
            return action
        }
    }
    func select(_ range: NSRange, focus: Bool = true) {
        guard range.location >= 0, range.length >= 0, range.location <= storage.length else { return }
        paginate()
        if storage.length == 0 {
            selectionView = textViews[0]
            if focus { canvas.window?.makeFirstResponder(textViews[0]) }
            textViews[0].setSelectedRange(NSRange(location: 0, length: 0)); return
        }
        let glyph = layout.glyphIndexForCharacter(at: min(range.location, max(0, storage.length - 1)))
        let container = layout.textContainer(forGlyphAt: glyph, effectiveRange: nil)
        let view = textViews.first { $0.textContainer === container } ?? textViews[0]
        selectionView = view
        if focus { canvas.window?.makeFirstResponder(view) }
        let safeRange = NSRange(location: range.location, length: min(range.length, storage.length - range.location))
        view.setSelectedRange(safeRange); view.scrollRangeToVisible(safeRange)
        selectionView = view; onSelection?()
    }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let value = (link as? URL)?.absoluteString ?? link as? String ?? ""
        guard DocumentLink.paragraphID(value) != nil || DocumentLink.bookmarkID(value) != nil else { return false }
        guard let id = owner?.snapshot().destinationParagraphID(for: value), jump(to: id) else {
            owner?.editorController?.showStatus("The linked destination has been deleted."); NSSound.beep(); return true
        }
        return true
    }
    func navigationLocation(in range: NSRange) -> Int {
        let text = storage.string as NSString
        var location = range.location
        while location < min(NSMaxRange(range), text.length), text.character(at: location) == 12 { location += 1 }
        return location
    }
    @discardableResult func jump(to id: UUID, focus: Bool = true) -> Bool {
        var found: NSRange?
        storage.enumerateAttribute(.scribeParagraphID, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value as? String == id.uuidString { found = range; stop.pointee = true }
        }
        if let found { select(NSRange(location: navigationLocation(in: found), length: 0), focus: focus); return true }
        if owner?.snapshot().paragraphs.last?.id == id { select(NSRange(location: storage.length, length: 0), focus: focus); return true }
        return false
    }
}
extension NSAttributedString {
    var containsNoteReferences: Bool {
        var found = false
        enumerateAttribute(.scribeNote, in: NSRange(location: 0, length: length)) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        return found
    }
}
#endif
