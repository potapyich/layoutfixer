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

    @ObservationIgnored
    @AppStorage("activeLayouts") private var activeLayoutsData: Data = Data()

    /// Tracked by @Observable so views re-render when activeLayouts changes.
    /// Incrementing this in the setter is the signal that triggers observation.
    /// (activeLayoutsData itself is @ObservationIgnored, so without this counter
    /// SwiftUI never knows the computed activeLayouts property changed.)
    private var activeLayoutsVersion = 0

    // MARK: - Computed

    var hotkey: HotkeyDefinition {
        get { HotkeyDefinition.decode(from: hotkeyData) ?? .default }
        set { hotkeyData = newValue.encoded() }
    }

    /// Ordered list of layouts the user wants to cycle through.
    /// Defaults to whatever macOS has installed (EN + first other language).
    var activeLayouts: [LayoutInfo] {
        get {
            _ = activeLayoutsVersion   // register view as observer of this property
            if !activeLayoutsData.isEmpty,
               let decoded = try? JSONDecoder().decode([LayoutInfo].self, from: activeLayoutsData),
               !decoded.isEmpty {
                return decoded
            }
            return InputSourceManager.shared.suggestedDefaults()
        }
        set {
            activeLayoutsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            activeLayoutsVersion &+= 1  // notify observers
        }
    }
}
