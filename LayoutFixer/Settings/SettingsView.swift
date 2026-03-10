import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Hotkey") {
                HotkeyRecorder(hotkey: $settings.hotkey)
            }
            Section("Sound") {
                Picker("Sound", selection: $settings.soundName) {
                    ForEach(SoundPlayer.availableSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Slider(value: $settings.soundVolume, in: 0...1) {
                    Text("Volume")
                }
                Toggle("Enable sound", isOn: $settings.soundEnabled)
                Button("Preview") {
                    SoundPlayer().play(name: settings.soundName, volume: settings.soundVolume)
                }
            }
            Section("General") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        LoginItemManager.shared.setEnabled(newValue)
                    }
            }
            Section("Language Cycle") {
                LanguageOrderView()
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }
}
