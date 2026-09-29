#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class StyleEditorOptions: NSObject, NSTextFieldDelegate {
    let original: ParagraphStyle
    let name: NSTextField
    let family = NSPopUpButton(), face = NSPopUpButton(), alignment = NSPopUpButton(), outline = NSPopUpButton()
    let size: NSTextField
    let bold = NSButton(checkboxWithTitle: "Bold", target: nil, action: nil)
    let italic = NSButton(checkboxWithTitle: "Italic", target: nil, action: nil)
    let underline = NSButton(checkboxWithTitle: "Underline", target: nil, action: nil)
    let strike = NSButton(checkboxWithTitle: "Strikethrough", target: nil, action: nil)
    let foreground = NSColorWell(), highlight = NSColorWell()
    let useHighlight = NSButton(checkboxWithTitle: "Highlight", target: nil, action: nil)
    let spacing: [NSTextField]
    let view = NSStackView()
    let preview = NSTextField(labelWithString: "Scribe — The quick brown fox")
    private var faceNames: [String?] = []
    init(style: ParagraphStyle) {
        original = style; name = NSTextField(string: style.name)
        size = NSTextField(string: String(style.text.fontSize ?? 12))
        let p = style.paragraph
        spacing = [p.lineSpacing, p.spaceBefore, p.spaceAfter, p.firstLineIndent, p.headIndent, p.tailIndent].map { NSTextField(string: String($0)) }
        super.init()
        var families = NSFontManager.shared.availableFontFamilies
        let current = style.text.fontFamily ?? "Helvetica Neue"
        if !families.contains(current) { families.append(current) }
        family.addItems(withTitles: families.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        family.selectItem(withTitle: current); family.target = self; family.action = #selector(familyChanged)
        bold.state = style.text.bold == true ? .on : .off; italic.state = style.text.italic == true ? .on : .off
        populateFaces(selected: style.text.fontFace); updateTraits()
        face.toolTip = "A concrete face defines weight and slant. Automatic uses the Bold and Italic controls."
        underline.state = style.text.underline == true ? .on : .off
        strike.state = style.text.strikethrough == true ? .on : .off
        foreground.color = NSColor(hex: style.text.foreground ?? "#1D1D1F")
        highlight.color = NSColor(hex: style.text.highlight ?? "#FFFF80")
        useHighlight.state = style.text.highlight == nil ? .off : .on
        alignment.addItems(withTitles: ["Left", "Centre", "Right", "Justified"])
        alignment.selectItem(at: Alignment.allCases.firstIndex(of: p.alignment) ?? 0)
        outline.addItems(withTitles: ["Body text"] + (1...9).map { "Heading level \($0)" })
        outline.selectItem(at: style.headingLevel ?? 0)
        let tabs = NSTabView(); tabs.translatesAutoresizingMaskIntoConstraints = false
        let text = grid([("Font family", family), ("Font face", face), ("Size (pt)", size), ("Traits", NSStackView(views: [bold, italic])), ("Text color", foreground), ("", underline), ("", strike), ("", useHighlight), ("Highlight color", highlight)])
        let paragraph = grid([("Alignment", alignment), ("Outline", outline)] + zip(["Additional line spacing", "Space before", "Space after", "First line indent", "Left indent", "Right indent"], spacing).map { ($0.0, $0.1 as NSView) })
        for (label, content) in [("Text", text), ("Paragraph", paragraph)] {
            let item = NSTabViewItem(identifier: label); item.label = label
            let wrapper = NSView(); content.translatesAutoresizingMaskIntoConstraints = false; wrapper.addSubview(content)
            NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16), content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16), content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 16)])
            item.view = wrapper; tabs.addTabViewItem(item)
        }
        view.orientation = .vertical; view.alignment = .leading; view.spacing = 14
        let title = grid([("Style name", name)])
        view.addArrangedSubview(title); view.addArrangedSubview(tabs); view.addArrangedSubview(preview)
        preview.setAccessibilityLabel("Style preview"); preview.heightAnchor.constraint(equalToConstant: 44).isActive = true
        for control in [size, bold, italic, underline, strike, foreground, highlight, useHighlight] as [NSControl] { control.target = self; control.action = #selector(updatePreview) }
        face.target = self; face.action = #selector(faceChanged); size.delegate = self
        updatePreview()
        NSLayoutConstraint.activate([title.widthAnchor.constraint(equalToConstant: 450), tabs.widthAnchor.constraint(equalToConstant: 450), tabs.heightAnchor.constraint(equalToConstant: 365)])
        view.frame = NSRect(x: 0, y: 0, width: 450, height: 465)
    }
    private func grid(_ rows: [(String, NSView)]) -> NSGridView {
        for (label, control) in rows where !label.isEmpty { control.setAccessibilityLabel(label); control.identifier = NSUserInterfaceItemIdentifier(label) }
        let grid = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
        grid.column(at: 0).width = 170; grid.columnSpacing = 12; grid.rowSpacing = 10
        for index in rows.indices { grid.row(at: index).height = 24 }
        return grid
    }
    @objc private func familyChanged() { populateFaces(selected: nil); updateTraits(); updatePreview() }
    @objc private func faceChanged() { updateTraits(); updatePreview() }
    func controlTextDidChange(_ notification: Notification) { updatePreview() }
    private func updateTraits() {
        let selected = faceNames.indices.contains(face.indexOfSelectedItem) ? faceNames[face.indexOfSelectedItem] : nil
        bold.isEnabled = selected == nil; italic.isEnabled = selected == nil
        if let selected, let font = NSFont(name: selected, size: 12) {
            let traits = NSFontManager.shared.traits(of: font)
            bold.state = traits.contains(.boldFontMask) ? .on : .off; italic.state = traits.contains(.italicFontMask) ? .on : .off
        }
    }
    @objc private func updatePreview() {
        highlight.isEnabled = useHighlight.state == .on
        guard let style = try? value(contentWidth: 10000) else { return }
        var attributes = AttributedDocument.attributes(style: style)
        if let font = attributes[.font] as? NSFont { attributes[.font] = NSFontManager.shared.convert(font, toSize: min(26, font.pointSize)) }
        preview.attributedStringValue = NSAttributedString(string: "Scribe — The quick brown fox", attributes: attributes)
    }
    private func populateFaces(selected: String?) {
        face.removeAllItems(); face.addItem(withTitle: "Automatic"); faceNames = [nil]
        for member in NSFontManager.shared.availableMembers(ofFontFamily: family.titleOfSelectedItem ?? "") ?? [] {
            guard let fontName = member.first as? String else { continue }
            face.addItem(withTitle: (member.count > 1 ? member[1] as? String : nil) ?? fontName); faceNames.append(fontName)
        }
        if let selected {
            if let index = faceNames.firstIndex(where: { $0 == selected }) { face.selectItem(at: index) }
            else { face.addItem(withTitle: selected + " (unavailable)"); faceNames.append(selected); face.selectItem(at: faceNames.count - 1) }
        }
    }
    func value(contentWidth: Double) throws -> ParagraphStyle {
        var result = original
        result.name = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty, result.name.utf8.count <= 512, !result.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let points = Double(size.stringValue), points.isFinite, (1...1000).contains(points) else { throw DocumentError.invalid("enter a style name and a font size from 1 to 1000 points") }
        result.text.fontSize = points; result.text.fontFamily = family.titleOfSelectedItem
        result.text.fontFace = faceNames.indices.contains(face.indexOfSelectedItem) ? faceNames[face.indexOfSelectedItem] : nil
        result.text.bold = bold.state == .on; result.text.italic = italic.state == .on
        result.text.underline = underline.state == .on; result.text.strikethrough = strike.state == .on
        result.text.clearHighlight = nil
        result.text.foreground = foreground.color.hex; result.text.highlight = useHighlight.state == .on ? highlight.color.hex : nil
        let numbers = spacing.compactMap { Double($0.stringValue) }
        guard numbers.count == 6, numbers.allSatisfy({ $0.isFinite && (0...4000).contains($0) }), max(numbers[3], numbers[4]) + numbers[5] < contentWidth - 30 else { throw DocumentError.invalid("spacing and indents must be non-negative and leave at least 30 points of writing width") }
        result.paragraph.alignment = Alignment.allCases[alignment.indexOfSelectedItem]
        result.headingLevel = outline.indexOfSelectedItem == 0 ? nil : outline.indexOfSelectedItem
        result.paragraph.lineSpacing = numbers[0]; result.paragraph.spaceBefore = numbers[1]; result.paragraph.spaceAfter = numbers[2]
        result.paragraph.firstLineIndent = numbers[3]; result.paragraph.headIndent = numbers[4]; result.paragraph.tailIndent = numbers[5]
        return result
    }
}
#endif
