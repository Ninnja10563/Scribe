#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class PageLayoutOptions: NSObject, NSTextFieldDelegate {
    let paper = NSPopUpButton()
    let width: NSTextField
    let height: NSTextField
    let landscape = NSButton(checkboxWithTitle: "Landscape", target: nil, action: nil)
    let margins: [NSTextField]
    let view = NSStackView()
    init(settings: PageSettings) {
        width = NSTextField(string: String(settings.width)); height = NSTextField(string: String(settings.height))
        margins = [settings.top, settings.bottom, settings.left, settings.right].map { NSTextField(string: String($0)) }
        super.init()
        let fields = [width, height] + margins
        let labels = ["Width", "Height", "Top margin", "Bottom margin", "Left margin", "Right margin"]
        paper.addItems(withTitles: PageSettings.Paper.allCases.map(\.rawValue) + ["Custom"])
        paper.selectItem(at: 3)
        for (index, preset) in PageSettings.Paper.allCases.enumerated() {
            let size = PageSettings(paper: preset, landscape: settings.width > settings.height)
            if abs(size.width - settings.width) < 0.01 && abs(size.height - settings.height) < 0.01 { paper.selectItem(at: index) }
        }
        landscape.state = settings.width > settings.height ? .on : .off
        let grid = NSGridView(views: zip(labels, fields).map { [NSTextField(labelWithString: $0.0), $0.1] })
        grid.rowSpacing = 8; grid.columnSpacing = 16
        for row in 0..<grid.numberOfRows { grid.row(at: row).height = 24 }
        grid.column(at: 0).width = 145; grid.column(at: 1).width = 125
        for child in [paper as NSView, landscape, grid] { view.addArrangedSubview(child) }
        view.orientation = .vertical; view.alignment = .leading; view.spacing = 12
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 260)
        paper.target = self; paper.action = #selector(selectPaper); paper.setAccessibilityLabel("Paper size")
        landscape.target = self; landscape.action = #selector(rotate)
        width.delegate = self; height.delegate = self
        for (name, field) in zip(labels, fields) {
            field.widthAnchor.constraint(equalToConstant: 125).isActive = true; field.setAccessibilityLabel(name)
        }
    }
    @objc func selectPaper() {
        guard PageSettings.Paper.allCases.indices.contains(paper.indexOfSelectedItem) else { return }
        let size = PageSettings(paper: PageSettings.Paper.allCases[paper.indexOfSelectedItem], landscape: landscape.state == .on)
        width.stringValue = String(size.width); height.stringValue = String(size.height)
    }
    @objc func rotate() {
        guard let w = Double(width.stringValue), let h = Double(height.stringValue) else { return }
        if (w > h) != (landscape.state == .on) { width.stringValue = String(h); height.stringValue = String(w) }
    }
    func controlTextDidChange(_ notification: Notification) {
        paper.selectItem(at: 3)
        if let w = Double(width.stringValue), let h = Double(height.stringValue) { landscape.state = w > h ? .on : .off }
    }
    func settings() throws -> PageSettings {
        let values = ([width, height] + margins).compactMap { Double($0.stringValue) }
        guard values.count == 6 else { throw DocumentError.invalid("enter numeric dimensions and margins") }
        var result = PageSettings()
        result.width = values[0]; result.height = values[1]; result.top = values[2]; result.bottom = values[3]; result.left = values[4]; result.right = values[5]
        guard result.isValid else { throw DocumentError.invalid("dimensions must be at most 4000 points, with nonnegative margins leaving at least 72 points of writing space") }
        return result
    }
}
#endif
