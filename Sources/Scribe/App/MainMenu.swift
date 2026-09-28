#if canImport(AppKit)
import AppKit

@MainActor enum MainMenu {
    static func install() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title); item.submenu = submenu; main.addItem(item); return submenu
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", shift: Bool = false) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]; menu.addItem(item)
        }
        let app = menu("Scribe")
        item(app, "About Scribe", #selector(AppDelegate.showAbout)); app.addItem(.separator())
        let services = NSMenu(); let serviceItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: ""); serviceItem.submenu = services; app.addItem(serviceItem); NSApp.servicesMenu = services
        item(app, "Hide Scribe", #selector(NSApplication.hide(_:)), "h")
        app.addItem(.separator()); item(app, "Quit Scribe", #selector(NSApplication.terminate(_:)), "q")
        let file = menu("File")
        item(file, "New", #selector(NSDocumentController.newDocument(_:)), "n")
        item(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
        let recent = NSMenu(title: "Open Recent")
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: ""); recentItem.submenu = recent; file.addItem(recentItem)
        item(recent, "Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))
        file.addItem(.separator())
        item(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        item(file, "Save…", #selector(NSDocument.save(_:)), "s")
        item(file, "Save As…", #selector(NSDocument.saveAs(_:)), "s", shift: true)
        let exports = NSMenu(title: "Export Copy")
        let exportItem = NSMenuItem(title: "Export Copy", action: nil, keyEquivalent: ""); exportItem.submenu = exports; file.addItem(exportItem)
        for (title, format) in [("PDF…", "pdf"), ("Word Document (.docx)…", "docx"), ("Rich Text (.rtf)…", "rtf"), ("Markdown…", "md"), ("Plain Text…", "txt")] {
            let i = NSMenuItem(title: title, action: #selector(ScribeFileDocument.exportDocument(_:)), keyEquivalent: ""); i.representedObject = format; exports.addItem(i)
        }
        file.addItem(.separator()); item(file, "Page Layout…", #selector(EditorWindowController.pageSettings))
        item(file, "Print…", #selector(NSDocument.printDocument(_:)), "p")
        let edit = menu("Edit")
        item(edit, "Undo", Selector(("undo:")), "z"); item(edit, "Redo", Selector(("redo:")), "z", shift: true)
        edit.addItem(.separator()); item(edit, "Cut", #selector(NSText.cut(_:)), "x"); item(edit, "Copy", #selector(NSText.copy(_:)), "c"); item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", shift: true)
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator()); item(edit, "Find and Replace…", #selector(EditorWindowController.showFind), "f")
        item(edit, "Check Spelling", #selector(NSTextView.checkSpelling(_:)), ";")
        let view = menu("View")
        item(view, "Toggle Outline", #selector(EditorWindowController.toggleSidebar), "1", shift: true)
        item(view, "Focus Mode", #selector(EditorWindowController.toggleFocus), "f", shift: true)
        item(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)))
        let insert = menu("Insert")
        item(insert, "Page Break", #selector(ScribeTextView.insertPageBreak(_:)), "\r")
        item(insert, "Headers and Footers…", #selector(EditorWindowController.editHeaderFooter))
        item(insert, "Symbols and Characters…", #selector(ScribeTextView.insertSpecialCharacter(_:)))
        let format = menu("Format")
        item(format, "Bold", #selector(ScribeTextView.toggleBold(_:)), "b"); item(format, "Italic", #selector(ScribeTextView.toggleItalic(_:)), "i"); item(format, "Underline", #selector(NSTextView.underline(_:)), "u")
        item(format, "Strikethrough", #selector(ScribeTextView.toggleStrike(_:)))
        item(format, "Show Fonts", #selector(EditorWindowController.showFonts), "t")
        item(format, "Show Colours", #selector(NSApplication.orderFrontColorPanel(_:)))
        format.addItem(.separator())
        item(format, "Align Left", #selector(NSTextView.alignLeft(_:))); item(format, "Centre", #selector(NSTextView.alignCenter(_:))); item(format, "Align Right", #selector(NSTextView.alignRight(_:))); item(format, "Justify", #selector(NSTextView.alignJustified(_:)))
        format.addItem(.separator())
        item(format, "Bullet List", #selector(EditorWindowController.bulletList)); item(format, "Numbered List", #selector(EditorWindowController.numberedList))
        format.addItem(.separator()); item(format, "Modify Style…", #selector(EditorWindowController.editStyle)); item(format, "Create Style…", #selector(EditorWindowController.createStyle)); item(format, "Delete Custom Style", #selector(EditorWindowController.deleteStyle))
        let tools = menu("Tools"); item(tools, "Document Statistics…", #selector(EditorWindowController.documentStatistics))
        let window = menu("Window"); NSApp.windowsMenu = window
        item(window, "Minimise", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        item(window, "Show Next Tab", #selector(NSWindow.selectNextTab(_:)))
        item(window, "Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)))
        item(window, "Merge All Windows", #selector(NSWindow.mergeAllWindows(_:)))
        NSApp.mainMenu = main
    }
}
#endif
