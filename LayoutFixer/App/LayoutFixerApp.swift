import SwiftUI

@main
struct LayoutFixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.settings)
        }
        .onChange(of: appDelegate.openSettingsTrigger) { _, _ in
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
    }
}
