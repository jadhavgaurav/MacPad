import SwiftUI

@main
struct NotePadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("NotePad", id: "main") {
            ContentView()
                .frame(minWidth: 760, minHeight: 440)
                .task { await AppState.shared.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 660)
        .commands { NotePadCommands() }

        Settings { SettingsView() }
    }
}
