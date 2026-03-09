import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    var menubarManager: MenubarManager?
    var hotkeyManager: HotkeyManager?
    var orchestrator: FixOrchestrator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let axPermission = AXPermissionManager()
        let axReader = AXTextReader()
        let axWriter = AXTextWriter()
        let clipboard = ClipboardManager()
        let converter = LayoutConverter()
        let detector = DirectionDetector()
        let soundPlayer = SoundPlayer()

        let orchestrator = FixOrchestrator(
            settings: settings,
            axPermission: axPermission,
            axReader: axReader,
            axWriter: axWriter,
            clipboard: clipboard,
            converter: converter,
            detector: detector,
            soundPlayer: soundPlayer
        )
        self.orchestrator = orchestrator

        let menubarManager = MenubarManager(settings: settings, orchestrator: orchestrator)
        self.menubarManager = menubarManager

        orchestrator.statusIconAnimator = menubarManager.statusIconAnimator

        let hotkeyManager = HotkeyManager(settings: settings) { [weak orchestrator] in
            Task { @MainActor in
                await orchestrator?.trigger()
            }
        }
        self.hotkeyManager = hotkeyManager
        hotkeyManager.enable()

        LoginItemManager.shared.registerIfNeeded(settings: settings)
    }
}
