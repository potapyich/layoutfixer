import SwiftUI

@Observable
final class AppSettings {
    @ObservationIgnored
    @AppStorage("hotkey") private var hotkeyData: Data = HotkeyDefinition.default.encoded()

    @ObservationIgnored
    @AppStorage("soundName") var soundName: String = "Tink"

    @ObservationIgnored
    @AppStorage("soundVolume") var soundVolume: Double = 0.7

    @ObservationIgnored
    @AppStorage("soundEnabled") var soundEnabled: Bool = true

    @ObservationIgnored
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = true

    @ObservationIgnored
    @AppStorage("isEnabled") var isEnabled: Bool = true

    var hotkey: HotkeyDefinition {
        get { HotkeyDefinition.decode(from: hotkeyData) ?? .default }
        set { hotkeyData = newValue.encoded() }
    }
}
