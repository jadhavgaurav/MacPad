import SwiftUI

@main
struct NotePadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("NotePad", id: "main") {
            ContentView(windowID: AppState.mainWindowID)
                .frame(minWidth: 760, minHeight: 440)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 660)
        .commands { NotePadCommands() }

        // A window for each torn-off tab, identified by the ID the tab was moved into.
        WindowGroup("NotePad", for: UUID.self) { window in
            ContentView(windowID: window.wrappedValue ?? AppState.mainWindowID)
                .frame(minWidth: 760, minHeight: 440)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 520)

        Settings { SettingsView() }
    }
}
