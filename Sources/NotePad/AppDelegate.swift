import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Visual QA can force light or dark mode without changing the system setting.
        switch ProcessInfo.processInfo.environment["NOTEPAD_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppState.shared.isFullScreen = true }
        }
        center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppState.shared.isFullScreen = false }
        }
        NSApp.servicesProvider = self
    }

    /// Services menu entry: receives the selected text from another app and opens it in a new tab.
    @objc func openSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string) else {
            error.pointee = "The selection has no plain text." as NSString
            return
        }
        Task { @MainActor in AppState.shared.openServiceText(text) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in AppState.shared.open(urls) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in AppState.shared.checkDisk() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Everything is saved to the session store first, so quitting never asks about unsaved text.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await AppState.shared.flushSession()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
