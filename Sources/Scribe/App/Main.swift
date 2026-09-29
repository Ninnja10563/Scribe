#if canImport(AppKit)
import AppKit
import DocumentCore

@main struct ScribeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
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
            if documents.documents.isEmpty { _ = try? documents.openUntitledDocumentAndDisplay(true) }
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
