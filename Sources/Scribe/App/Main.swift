#if canImport(AppKit)
import AppKit
import DocumentCore

@main struct ScribeMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--startup-smoke-test") {
            print("Startup arguments: \(CommandLine.arguments)"); fflush(stdout)
            var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            arguments["SUEnableAutomaticChecks"] = false
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        // Initialize the custom controller before AppKit finishes launching.
        _ = NSDocumentController.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let documents = ScribeDocumentController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        MainMenu.install()
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--smoke-test") { Task { await smokeTest() }; return }
        ensureDocumentWindow()
        SoftwareUpdates.shared.start()
        if CommandLine.arguments.contains("--startup-smoke-test") { verifyStartup(); return }
        Task {
            let snapshots = (try? await ScribeFileDocument.recovery.snapshots()) ?? []
            for snapshot in snapshots {
                let alert = NSAlert(); alert.messageText = "Recover \(snapshot.document.title)?"
                alert.informativeText = "Scribe found a recovery copy from \(snapshot.savedAt.formatted()). It opens as an unsaved document; the original is kept intact."
                alert.addButton(withTitle: "Recover Copy"); alert.addButton(withTitle: "Keep for Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    do {
                        let document = try ScribeFileDocument.recovering(snapshot)
                        let replacement = RecoverySnapshot(document: document.model, originalURL: snapshot.originalURL)
                        try await ScribeFileDocument.recovery.replaceSnapshot(id: snapshot.document.id, with: replacement)
                        documents.addDocument(document); document.makeWindowControllers(); document.showWindows()
                    } catch { NSApp.presentError(error) }
                }
            }
            ensureDocumentWindow()
        }
    }
    func ensureDocumentWindow() {
        if let document = documents.documents.first {
            if document.windowControllers.isEmpty { document.makeWindowControllers() }
            document.showWindows()
            document.windowControllers.first?.window?.deminiaturize(nil)
            document.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
        } else {
            let document = ScribeFileDocument()
            document.fileType = ScribeFileDocument.typeName
            documents.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
            document.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { ensureDocumentWindow() }
        return true
    }
    private func verifyStartup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            print("Startup documents=\(documents.documents.count), shared=\(documents === NSDocumentController.shared), appWindows=\(NSApp.windows.count)")
            for document in documents.documents {
                print("Document \(type(of: document)), controllers=\(document.windowControllers.count), editor=\((document as? ScribeFileDocument)?.editorController != nil)")
                for controller in document.windowControllers { print("Window visible=\(controller.window?.isVisible == true), loaded=\(controller.isWindowLoaded)") }
            }
            let visible = documents.documents.flatMap(\.windowControllers).contains { $0.window?.isVisible == true }
            guard visible, let document = documents.documents.first as? ScribeFileDocument,
                  let editor = document.editorController?.editor else { exit(1) }
            editor.activeTextView.insertText("Startup typing works", replacementRange: NSRange(location: 0, length: 0))
            guard document.snapshot().paragraphs.contains(where: { $0.text.contains("Startup typing works") }) else { exit(2) }
            document.windowControllers.first?.window?.orderOut(nil)
            _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            guard document.windowControllers.first?.window?.isVisible == true else { exit(3) }
            guard SoftwareUpdates.shared.controller.updater.canCheckForUpdates else { exit(7) }
            documents.newDocument(nil)
            guard documents.documents.count == 2,
                  documents.documents.allSatisfy({ $0.windowControllers.count == 1 }),
                  documents.documents.contains(where: { $0.windowControllers.first?.window?.isVisible == true }) else { exit(5) }
            for openDocument in documents.documents { openDocument.updateChangeCount(.changeCleared); openDocument.close() }
            ensureDocumentWindow()
            guard documents.documents.count == 1, documents.documents.first?.windowControllers.first?.window?.isVisible == true else { exit(6) }
            if let report = CommandLine.arguments.first(where: { $0.hasPrefix("--startup-report=") }) {
                let path = String(report.dropFirst("--startup-report=".count))
                do { try Data("Normal startup, typing and Dock reopen passed".utf8).write(to: URL(fileURLWithPath: path), options: .atomic) }
                catch { exit(4) }
            }
            print("Normal startup, typing and Dock reopen passed")
            exit(0)
        }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for file in filenames {
            let url = URL(fileURLWithPath: file)
            if url.pathExtension == "scribe" {
                documents.openDocument(withContentsOf: url, display: true) { _, _, error in if let error { NSApp.presentError(error) } }
            } else { documents.importDocument(url) }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    @objc func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Scribe", .applicationVersion: version, .credits: NSAttributedString(string: "A native document workspace for macOS.\nEarly development release.")])
    }

}
#else
import Foundation
@main struct ScribeMain {
    static func main() {
        print("Scribe is a native macOS application. Build on macOS 14 or later. The document core and import/export tests run on Linux with swift test.")
    }
}
#endif
