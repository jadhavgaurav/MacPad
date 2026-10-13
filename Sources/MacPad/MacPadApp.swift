import SwiftUI

@main
struct MacPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("MacPad", id: "main") {
            ContentView(windowID: AppState.mainWindowID)
                .frame(minWidth: 760, minHeight: 440)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 660)
        .commands { MacPadCommands() }

        // A window for each torn-off tab, identified by the ID the tab was moved into.
        WindowGroup("MacPad", for: UUID.self) { window in
            ContentView(windowID: window.wrappedValue ?? AppState.mainWindowID)
                .frame(minWidth: 760, minHeight: 440)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 520)

        Settings { SettingsView() }
    }
}
