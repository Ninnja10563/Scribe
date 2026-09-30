#if canImport(AppKit)
import AppKit
import DocumentCore

/// A document-local inspector: font controls never open a separate font window.
@MainActor final class FormattingSidebar: NSView {
    weak var owner: EditorWindowController?
    let family = NSPopUpButton()
    let face = NSPopUpButton()
    let size = NSComboBox()
    let selectionLabel = NSTextField(wrappingLabelWithString: "Changes apply to selected text or new typing.")
    private let lineHeight = NSPopUpButton()
    private let list = NSPopUpButton()
    private let textColour = NSPopUpButton()
    private let highlight = NSPopUpButton()
    private var faceNames: [String] = []
    private var displayedFamily = ""
    private let colours = ["#1D1D1F", "#FFFFFF", "#666666", "#B71C1C", "#D84315", "#F9A825", "#2E7D32", "#00838F", "#1565C0", "#283593", "#6A1B9A", "#AD1457", "#FFF176", "#A5D6A7", "#90CAF9", "#F8BBD0"]
    private let colourNames = ["Black", "White", "Grey", "Red", "Orange", "Gold", "Green", "Teal", "Blue", "Indigo", "Purple", "Magenta", "Light yellow", "Light green", "Light blue", "Light pink"]
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let content = FormattingContentStack(); content.orientation = .vertical; content.alignment = .leading; content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 20, right: 16)
        let title = NSTextField(labelWithString: "Format"); title.font = .systemFont(ofSize: 15, weight: .semibold)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close formatting sidebar")!, target: self, action: #selector(closeSidebar))
        close.isBordered = false; close.setAccessibilityLabel("Close formatting sidebar")
        let header = NSStackView(views: [title, NSView(), close]); content.addArrangedSubview(header)
        selectionLabel.font = .systemFont(ofSize: 11); selectionLabel.textColor = .secondaryLabelColor
        content.addArrangedSubview(selectionLabel)
        content.addArrangedSubview(section("Font"))
        family.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        configure(family, label: "Font family", action: #selector(changeFamily))
        configure(face, label: "Typeface and weight", action: #selector(changeFace))
        size.addItems(withObjectValues: ["8", "9", "10", "11", "12", "14", "16", "18", "20", "24", "28", "36", "48", "72"])
        size.target = self; size.action = #selector(changeSize); size.setAccessibilityLabel("Font size in points")
        content.addArrangedSubview(family); content.addArrangedSubview(face)
        content.addArrangedSubview(row([size, command("A−", "Decrease font size", "shrinkFont:"), command("A+", "Increase font size", "growFont:")]))
        content.addArrangedSubview(row([command("B", "Bold", "toggleBold:"), command("I", "Italic", "toggleItalic:"), command("U", "Underline", "underline:"), command("S̶", "Strikethrough", "toggleStrike:")]))
        content.addArrangedSubview(row([command("x²", "Superscript", "superscript:"), command("x₂", "Subscript", "subscript:"), command("Baseline", "Normal baseline", "unscript:")]))
        setupColours(textColour, highlight: false); setupColours(highlight, highlight: true)
        content.addArrangedSubview(labelled("Text colour", textColour)); content.addArrangedSubview(labelled("Highlight", highlight))
        content.addArrangedSubview(row([command("UPPERCASE", "Convert selection to uppercase", "uppercaseSelection:"), command("lowercase", "Convert selection to lowercase", "lowercaseSelection:")]))
        content.addArrangedSubview(command("Clear Character Formatting", "Restore the paragraph style’s character formatting", "clearCharacterFormatting:"))
        content.addArrangedSubview(row([controllerCommand("Copy Format", "copyCharacterFormatting"), controllerCommand("Paste Format", "pasteCharacterFormatting")]))
        content.addArrangedSubview(section("Paragraph"))
        content.addArrangedSubview(row([command("Left", "Align left", "alignLeft:"), command("Centre", "Align centre", "alignCenter:"), command("Right", "Align right", "alignRight:"), command("Justify", "Justify", "alignJustified:")]))
        lineHeight.addItems(withTitles: ["Line spacing…", "Single", "1.15 lines", "1.5 lines", "Double", "2.5 lines", "Triple"])
        configure(lineHeight, label: "Line spacing", action: #selector(changeLineHeight)); content.addArrangedSubview(lineHeight)
        content.addArrangedSubview(row([controllerCommand("Outdent", "decreaseIndent"), controllerCommand("Indent", "increaseIndent")]))
        list.addItems(withTitles: ["List format…", "No list", "Bullets", "1, 2, 3", "a, b, c", "A, B, C", "i, ii, iii", "I, II, III"])
        configure(list, label: "List format", action: #selector(changeList)); content.addArrangedSubview(list)
        content.addArrangedSubview(controllerCommand("List Levels and Numbering…", "listSettings"))
        content.addArrangedSubview(controllerCommand("Spacing and Indents…", "paragraphSettings"))
        content.addArrangedSubview(controllerCommand("Toggle Page Break Before", "togglePageBreakBefore"))
        content.addArrangedSubview(controllerCommand("Clear Paragraph Formatting", "clearParagraphFormatting"))
        content.addArrangedSubview(section("Styles"))
        content.addArrangedSubview(row([controllerCommand("Modify Style…", "editStyle"), controllerCommand("Create Style…", "createStyle")]))
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.documentView = content
        scroll.translatesAutoresizingMaskIntoConstraints = false; content.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor), content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)])
        for view in content.arrangedSubviews { view.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32).isActive = true }
    }
    required init?(coder: NSCoder) { fatalError("Programmatic views only") }
    private func section(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 11, weight: .semibold); label.textColor = .secondaryLabelColor; return label
    }
    private func row(_ views: [NSView]) -> NSStackView { let stack = NSStackView(views: views); stack.spacing = 6; stack.distribution = .fillEqually; return stack }
    private func labelled(_ text: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: 11)
        let stack = NSStackView(views: [label, control]); stack.spacing = 8; return stack
    }
    private func configure(_ control: NSPopUpButton, label: String, action: Selector) { control.target = self; control.action = action; control.setAccessibilityLabel(label) }
    private func command(_ title: String, _ help: String, _ selector: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(textAction(_:)))
        button.identifier = .init(selector); button.toolTip = help; button.setAccessibilityLabel(help); button.bezelStyle = .rounded; button.controlSize = .small
        return button
    }
    private func controllerCommand(_ title: String, _ selector: String) -> NSButton {
        let button = command(title, title, selector); button.action = #selector(controllerAction(_:)); return button
    }
    private func setupColours(_ popup: NSPopUpButton, highlight isHighlight: Bool) {
        popup.addItem(withTitle: isHighlight ? "No highlight" : "Text colour…")
        for (name, hex) in zip(colourNames, colours) {
            popup.addItem(withTitle: name)
            popup.lastItem?.image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in NSColor(hex: hex).setFill(); rect.fill(); return true }
        }
        configure(popup, label: isHighlight ? "Highlight colour" : "Text colour", action: #selector(changeColour(_:)))
    }
    func refresh() {
        guard let owner, !owner.isClosing else { return }
        let view = owner.editor.activeTextView
        let attributes = view.currentCharacterAttributes
        if let font = ScriptProjection.logicalFont(in: attributes) {
            let name = font.familyName ?? font.fontName
            if !family.itemTitles.contains(name) { family.addItem(withTitle: name) }
            family.selectItem(withTitle: name)
            if displayedFamily != name {
                displayedFamily = name; face.removeAllItems(); faceNames = []
                for member in NSFontManager.shared.availableMembers(ofFontFamily: name) ?? [] {
                    guard let postscript = member[0] as? String, let title = member[1] as? String else { continue }
                    face.addItem(withTitle: title); faceNames.append(postscript)
                }
            }
            if let index = faceNames.firstIndex(of: font.fontName) { face.selectItem(at: index) }
            if size.currentEditor() == nil { size.stringValue = String(format: "%g", font.pointSize) }
        }
        selectionLabel.stringValue = view.selectedRange().length == 0 ? "Formatting applies to new typing." : "Formatting applies to selected text. Mixed selections show the first character’s font."
    }
    @objc private func closeSidebar() { owner?.toggleFormatting() }
    @objc func changeFamily() {
        guard let name = family.titleOfSelectedItem else { return }
        owner?.editor.activeTextView.transformLogicalFonts(action: "Font Family") { NSFontManager.shared.convert($0, toFamily: name) }; refresh()
    }
    @objc func changeFace() {
        guard faceNames.indices.contains(face.indexOfSelectedItem) else { return }
        let name = faceNames[face.indexOfSelectedItem]
        owner?.editor.activeTextView.transformLogicalFonts(action: "Typeface") { NSFont(name: name, size: $0.pointSize) ?? $0 }; refresh()
    }
    @objc func changeSize() {
        guard let value = Double(size.stringValue), owner?.editor.activeTextView.setFontSize(value) == true else { NSSound.beep(); selectionLabel.stringValue = "Enter a font size from 1 to 1,000 points."; return }
        refresh()
    }
    @objc private func textAction(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue, let view = owner?.editor.activeTextView else { return }
        _ = view.perform(NSSelectorFromString(name), with: sender); refresh()
    }
    @objc private func controllerAction(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue else { return }
        _ = owner?.perform(NSSelectorFromString(name)); refresh()
    }
    @objc private func changeLineHeight() {
        let values = [1.0, 1.15, 1.5, 2, 2.5, 3], index = lineHeight.indexOfSelectedItem - 1
        if values.indices.contains(index) { owner?.setLineHeightMultiple(values[index]) }
        lineHeight.selectItem(at: 0)
    }
    @objc private func changeList() {
        let kinds: [ListDescriptor.Kind] = [.bullet, .decimal, .lowerAlpha, .upperAlpha, .lowerRoman, .upperRoman]
        let index = list.indexOfSelectedItem
        if index == 1 { owner?.editor.applyList(nil) }
        else if index >= 2 { owner?.editor.applyList(.init(kind: kinds[index - 2])) }
        list.selectItem(at: 0)
    }
    @objc private func changeColour(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem - 1
        if index >= 0 { owner?.editor.activeTextView.setCharacterColour(NSColor(hex: colours[index]), highlight: sender === highlight) }
        else if sender === highlight { owner?.editor.activeTextView.setCharacterColour(nil, highlight: true) }
        sender.selectItem(at: 0)
    }
}
@MainActor private final class FormattingContentStack: NSStackView {
    override var isFlipped: Bool { true }
}
#endif
