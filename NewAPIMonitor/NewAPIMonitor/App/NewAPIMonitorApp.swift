import SwiftUI

@main
struct NewAPIMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appClient = NewAPIClient.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appClient)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
                .environment(appClient)
        }
    }
}
