#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class RunningContentOptions {
    let view = NSTabView(frame: NSRect(x: 0, y: 0, width: 420, height: 230))
    private let original: RunningContentVariants
    let header: NSTextField, footer: NSTextField
    let firstHeader: NSTextField, firstFooter: NSTextField
    let evenHeader: NSTextField, evenFooter: NSTextField
    let differentFirst = NSButton(checkboxWithTitle: "Different first page", target: nil, action: nil)
    let differentEven = NSButton(checkboxWithTitle: "Different odd and even pages", target: nil, action: nil)
    init(section: Section) {
        let variants = section.runningContent ?? RunningContentVariants()
        original = variants
        header = NSTextField(string: section.header); footer = NSTextField(string: section.footer)
        firstHeader = NSTextField(string: variants.firstHeader); firstFooter = NSTextField(string: variants.firstFooter)
        evenHeader = NSTextField(string: variants.evenHeader); evenFooter = NSTextField(string: variants.evenFooter)
        differentFirst.state = variants.differentFirstPage ? .on : .off
        differentEven.state = variants.differentOddEvenPages ? .on : .off
        addTab("Default", fields: [header, footer], note: "Used on every page unless a first-page or even-page variant is enabled.")
        addTab("First Page", fields: [firstHeader, firstFooter], toggle: differentFirst, note: "Empty fields leave the first page's running text blank. Page numbering is configured separately.")
        addTab("Even Pages", fields: [evenHeader, evenFooter], toggle: differentEven, note: "Uses numbered-page parity, including a custom starting page number. Default text is used on odd pages.")
    }
    private func addTab(_ title: String, fields: [NSTextField], toggle: NSButton? = nil, note: String) {
        var views: [NSView] = []
        if let toggle { views.append(toggle) }
        for (index, field) in fields.enumerated() {
            let label = index == 0 ? "Header" : "Footer"
            field.setAccessibilityLabel("\(title) \(label.lowercased())")
            field.identifier = NSUserInterfaceItemIdentifier("\(title) \(label)")
            field.widthAnchor.constraint(equalToConstant: 372).isActive = true
            views.append(NSTextField(labelWithString: label)); views.append(field)
        }
        let help = NSTextField(wrappingLabelWithString: note)
        help.font = .systemFont(ofSize: 11); help.textColor = .secondaryLabelColor
        help.widthAnchor.constraint(equalToConstant: 372).isActive = true; views.append(help)
        let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 7
        let container = NSView(); stack.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16), stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12)])
        let tab = NSTabViewItem(identifier: title); tab.label = title; tab.view = container; view.addTabViewItem(tab)
    }
    func apply(to section: inout Section) {
        section.header = header.stringValue; section.footer = footer.stringValue
        var variants = original
        variants.differentFirstPage = differentFirst.state == .on; variants.differentOddEvenPages = differentEven.state == .on
        variants.firstHeader = firstHeader.stringValue; variants.firstFooter = firstFooter.stringValue
        variants.evenHeader = evenHeader.stringValue; variants.evenFooter = evenFooter.stringValue
        section.runningContent = variants == RunningContentVariants() ? nil : variants
    }
}
#endif
