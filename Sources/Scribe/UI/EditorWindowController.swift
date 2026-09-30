#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class EditorWindowController: NSWindowController {
    let editor: PaginatedEditor
    let outline = DocumentOutlineView(frame: .zero)
    let sidebar = NSView()
    let commentsSidebar = CommentsSidebar()
    let reviewSidebar = ReviewSidebar()
    private var reviewBeforeFocus = false
    private var commentsBeforeFocus = false
    private var rulerBeforeFocus = true
    let status = NSTextField(labelWithString: "")
    let stylePicker = NSPopUpButton()
    let zoomPicker = NSPopUpButton()
    let toolbar = NSStackView()
    let formattingSidebar = FormattingSidebar(frame: .zero)
    var copiedCharacterAppearance: [NSAttributedString.Key: Any]?
    private var formattingBeforeFocus = false
    let searchBar = SearchBar()
    lazy var reviewNavigation = ReviewNavigation(owner: self)
    private let outlineHint = NSTextField(wrappingLabelWithString: "Apply heading styles to build your document outline.")
    var isFocused = false
    private var statsWork: DispatchWorkItem?
    private var statsTask: Task<Void, Never>?
    private(set) var isClosing = false
    var fileDocument: ScribeFileDocument { document as! ScribeFileDocument }
    init(document: ScribeFileDocument) {
        editor = PaginatedEditor(document: document)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 500); window.title = "Scribe"
        window.tabbingMode = .preferred; window.tabbingIdentifier = "ScribeDocuments"
        window.setFrameAutosaveName("ScribeDocumentWindow"); window.center()
        super.init(window: window)
        // Register the controller through NSDocument; assigning document first
        // makes addWindowController treat it as already attached without listing it.
        document.addWindowController(self)
        buildInterface()
        editor.onChange = { [weak self] in self?.fileDocument.didEdit(); self?.scheduleStatistics(); if self?.searchBar.isHidden == false { self?.searchBar.search() } }
        editor.onSelection = { [weak self] in self?.updateStatus() }
        searchBar.editor = editor
        editor.onLayout = { [weak self] in self?.searchBar.refreshHighlights() }
        refreshOutline(); updateStatus()
        window.initialFirstResponder = editor.textViews.first
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosing), name: NSWindow.willCloseNotification, object: window)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic windows only") }
    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        guard !isClosing, let document = document as? ScribeFileDocument,
              document.isRecoveredCopy, document.fileURL == nil else { return displayName }
        return document.model.title.hasSuffix(" — Recovered") ? document.model.title : document.model.title + " — Recovered"
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func windowClosing() { prepareForClose() }
    private func buildInterface() {
        guard let window else { return }
        let content = ChromeView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = content
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 0; stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor), stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true
        toolbar.orientation = .horizontal; toolbar.spacing = 10; toolbar.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        toolbar.addArrangedSubview(button("sidebar.left", "Show or hide outline", #selector(toggleSidebar)))
        stylePicker.target = self; stylePicker.action = #selector(changeStyle); stylePicker.setAccessibilityLabel("Paragraph style")
        stylePicker.widthAnchor.constraint(equalToConstant: 125).isActive = true; toolbar.addArrangedSubview(stylePicker)
        toolbar.addArrangedSubview(button("textformat", "Font and formatting sidebar (⌘T)", #selector(showFonts)))
        toolbar.addArrangedSubview(divider())
        toolbar.addArrangedSubview(button("bold", "Bold (⌘B)", #selector(ScribeTextView.toggleBold(_:)), responder: true))
        toolbar.addArrangedSubview(button("italic", "Italic (⌘I)", #selector(ScribeTextView.toggleItalic(_:)), responder: true))
        toolbar.addArrangedSubview(button("underline", "Underline (⌘U)", #selector(NSTextView.underline(_:)), responder: true))
        toolbar.addArrangedSubview(divider())
        toolbar.addArrangedSubview(button("text.alignleft", "Align left", #selector(NSTextView.alignLeft(_:)), responder: true))
        toolbar.addArrangedSubview(button("text.aligncenter", "Align centre", #selector(NSTextView.alignCenter(_:)), responder: true))
        toolbar.addArrangedSubview(button("text.alignright", "Align right", #selector(NSTextView.alignRight(_:)), responder: true))
        toolbar.addArrangedSubview(button("list.bullet", "Bullet list", #selector(bulletList)))
        toolbar.addArrangedSubview(button("list.number", "Numbered list", #selector(numberedList)))
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); toolbar.addArrangedSubview(spacer)
        toolbar.addArrangedSubview(button("magnifyingglass", "Find and replace (⌘F)", #selector(showFind)))
        toolbar.addArrangedSubview(button("arrow.up.left.and.arrow.down.right", "Focus mode", #selector(toggleFocus)))
        stack.addArrangedSubview(toolbar)
        stack.addArrangedSubview(searchBar); searchBar.isHidden = true
        let split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin
        split.addArrangedSubview(sidebar); split.addArrangedSubview(editor.scrollView)
        commentsSidebar.owner = self; split.addArrangedSubview(commentsSidebar); commentsSidebar.isHidden = true
        commentsSidebar.widthAnchor.constraint(equalToConstant: 300).isActive = true
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 2)
        reviewSidebar.owner = self; split.addArrangedSubview(reviewSidebar); reviewSidebar.isHidden = true
        reviewSidebar.widthAnchor.constraint(equalToConstant: 300).isActive = true
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 3)
        formattingSidebar.owner = self; split.addArrangedSubview(formattingSidebar); formattingSidebar.isHidden = true
        formattingSidebar.widthAnchor.constraint(equalToConstant: 320).isActive = true
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 4)
        setupOutline()
        sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        sidebar.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        stack.addArrangedSubview(split)
        split.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        let footer = NSStackView(); footer.heightAnchor.constraint(equalToConstant: 32).isActive = true; footer.orientation = .horizontal; footer.spacing = 14
        footer.edgeInsets = NSEdgeInsets(top: 7, left: 16, bottom: 7, right: 16)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.setAccessibilityLabel("Document statistics"); footer.addArrangedSubview(status)
        let flex = NSView(); flex.setContentHuggingPriority(.defaultLow, for: .horizontal); footer.addArrangedSubview(flex)
        zoomPicker.addItems(withTitles: ["50%", "75%", "100%", "125%", "150%", "200%", "Actual Size", "Fit Width", "Fit Page"])
        zoomPicker.selectItem(withTitle: "100%"); zoomPicker.target = self; zoomPicker.action = #selector(changeZoom)
        zoomPicker.setAccessibilityLabel("Document zoom"); footer.addArrangedSubview(zoomPicker)
        stack.addArrangedSubview(footer)
        for child in [toolbar, searchBar, split, footer] { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        split.setPosition(200, ofDividerAt: 0)
        content.layoutSubtreeIfNeeded(); editor.resizeCanvas()
        // Adding the ruler retiles the clip view; new documents still start at the page top.
        editor.scrollView.contentView.scroll(to: .zero)
        editor.scrollView.reflectScrolledClipView(editor.scrollView.contentView)
    }
    private func setupOutline() {
        let title = NSTextField(labelWithString: "OUTLINE"); title.font = .systemFont(ofSize: 10, weight: .semibold); title.textColor = .secondaryLabelColor
        let hint = outlineHint
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = true; scroll.backgroundColor = .windowBackgroundColor
        outline.navigate = { [weak self] id, focus in self?.editor.jump(to: id, focus: focus) }
        outline.returnToDocument = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.editor.activeTextView)
        }
        scroll.documentView = outline
        let stack = NSStackView(views: [title, hint, scroll]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14), stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12), stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 18), stack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -10), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor)])
    }
    private func button(_ symbol: String, _ label: String, _ action: Selector, responder: Bool = false) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: responder ? nil : self, action: action)
        button.bezelStyle = .texturedRounded; button.isBordered = false; button.toolTip = label
        button.setAccessibilityLabel(label); button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }
    private func divider() -> NSView { let view = NSBox(); view.boxType = .separator; view.widthAnchor.constraint(equalToConstant: 1).isActive = true; view.heightAnchor.constraint(equalToConstant: 18).isActive = true; return view }
    func refreshOutline(using snapshot: ScribeDocument? = nil) {
        guard !isClosing else { return }
        let model = snapshot ?? fileDocument.snapshot(); commentsSidebar.reload(model); let entries = model.outline; outlineHint.isHidden = !entries.isEmpty; outline.refresh(entries)
        if !reviewSidebar.isHidden { reviewSidebar.reload(model) }
        let selected = stylePicker.titleOfSelectedItem
        stylePicker.removeAllItems(); stylePicker.addItems(withTitles: model.styles.map(\.name))
        if let selected { stylePicker.selectItem(withTitle: selected) }
        scheduleStatistics()
        updateStatus()
    }
    func scheduleStatistics() {
        guard !isClosing else { return }
        statsTask?.cancel()
        statsWork?.cancel(); let job = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let text = self.editor.semanticText.statisticsText, revision = self.editor.revision
            self.statsTask = Task { [weak self] in
                let words = await Task.detached { DocumentStatistics(text: text).words }.value
                guard !Task.isCancelled, let self, !self.isClosing, revision == self.editor.revision else { return }
                self.cachedWords = words; self.updateStatus()
            }
        }
        statsWork = job; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: job)
    }
    private var cachedWords = 0
    func updateStatus() {
        guard !isClosing else { return }
        editor.paragraphRuler?.refresh()
        if !formattingSidebar.isHidden { formattingSidebar.refresh() }
        if let warning = editor.outputWarning { status.stringValue = warning; return }
        let view = editor.activeTextView
        let selection = view.selectedRange()
        let notePage = searchBar.selectedNotePage ?? reviewNavigation.selectedNotePage
        let page = notePage ?? editor.textViews.firstIndex(where: { $0 === view }).map { $0 + 1 } ?? 1
        let selectedWords = notePage == nil && selection.length > 0 && NSMaxRange(selection) <= editor.storage.length ? DocumentStatistics(text: editor.semanticText.text(inSourceRange: selection)).words : nil
        status.stringValue = "Page \(page) of \(editor.canvas.pageCount)    ·    \(cachedWords.formatted()) words\(selectedWords.map { " (\($0) selected)" } ?? "")    ·    \(DocumentSpelling.label(for: fileDocument.model.language))    ·    \(Int((editor.zoom * 100).rounded()))%"
        let selectedStyle = selection.location < editor.storage.length ? editor.storage.attribute(.scribeStyle, at: selection.location, effectiveRange: nil) : view.typingAttributes[.scribeStyle]
        if let id = selectedStyle as? String, let style = fileDocument.model.styles.first(where: { $0.id == id }) { stylePicker.selectItem(withTitle: style.name) }
    }
    func showStatus(_ message: String) { if !isClosing { status.stringValue = message } }
    func prepareForClose() {
        guard !isClosing else { return }
        isClosing = true; statsWork?.cancel(); statsTask?.cancel()
        searchBar.cancelPendingWork()
        outline.navigate = nil; outline.returnToDocument = nil
        outline.delegate = nil; outline.dataSource = nil
        reviewSidebar.table.delegate = nil; reviewSidebar.table.dataSource = nil
        for view in editor.textViews where view.reviewComposition != nil { view.cancelReviewComposition() }
        window?.makeFirstResponder(nil)
        editor.prepareForClose()
    }
    @objc func focusOutline() {
        if isFocused { toggleFocus() }
        sidebar.isHidden = false
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.makeFirstResponder(outline)
        if outline.selectedRow < 0, outline.numberOfRows > 0 { outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }
    @objc func changeStyle() {
        let index = stylePicker.indexOfSelectedItem; guard fileDocument.model.styles.indices.contains(index) else { return }
        editor.applyStyle(fileDocument.model.styles[index].id)
    }
    @objc func showFonts() {
        if isFocused { toggleFocus() }
        formattingSidebar.refresh(); ChromeAnimation.reveal(formattingSidebar)
        window?.contentView?.layoutSubtreeIfNeeded()
    }
    @objc func bulletList() { editor.applyList(ListDescriptor()) }
    @objc func numberedList() { editor.applyList(ListDescriptor(kind: .decimal)) }
    @objc func toggleSidebar() { sidebar.isHidden.toggle() }
    @objc func focusRuler() {
        editor.scrollView.rulersVisible = true; editor.paragraphRuler?.refresh()
        if let handle = editor.paragraphRuler?.handles.first(where: { $0.isEnabled }) { window?.makeFirstResponder(handle) }
    }
    @objc func toggleRuler() {
        editor.scrollView.rulersVisible.toggle(); editor.paragraphRuler?.refresh(); editor.viewportChanged()
    }
    @objc func toggleFocus() {
        if !isFocused { formattingBeforeFocus = !formattingSidebar.isHidden; formattingSidebar.isHidden = true }
        else { formattingSidebar.isHidden = !formattingBeforeFocus }
        if !isFocused { rulerBeforeFocus = editor.scrollView.rulersVisible; editor.scrollView.rulersVisible = false }
        else { editor.scrollView.rulersVisible = rulerBeforeFocus }
        if !isFocused { commentsBeforeFocus = !commentsSidebar.isHidden; commentsSidebar.isHidden = true }
        else { commentsSidebar.isHidden = !commentsBeforeFocus }
        if !isFocused { reviewBeforeFocus = !reviewSidebar.isHidden; reviewSidebar.isHidden = true }
        else { reviewSidebar.isHidden = !reviewBeforeFocus }
        isFocused.toggle(); sidebar.isHidden = isFocused; toolbar.isHidden = isFocused; if isFocused { searchBar.isHidden = true }; window?.makeFirstResponder(editor.activeTextView) }
    @objc func findNext() { searchBar.isHidden = false; searchBar.next() }
    @objc func findPrevious() { searchBar.isHidden = false; searchBar.previous() }
    @objc func showFind() { ChromeAnimation.reveal(searchBar); window?.makeFirstResponder(searchBar.query) }
    @objc func changeZoom() {
        let title = zoomPicker.titleOfSelectedItem ?? "100%"
        if title == "Fit Width" { editor.selectZoom(.fitWidth) }
        else if title == "Fit Page" { editor.selectZoom(.fitPage) }
        else { editor.zoom = CGFloat(Double(title.replacingOccurrences(of: "%", with: "")) ?? 100) / 100 }
    }
}
@MainActor private final class ChromeView: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); dirtyRect.fill() }
}
#endif
