import AppKit
import SwiftUI

@Observable
class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    var menubarManager: MenubarManager?
    var hotkeyManager: HotkeyManager?
    var orchestrator: FixOrchestrator?
    var openSettingsTrigger: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let axPermission = AXPermissionManager()
        let axReader = AXTextReader()
        let axWriter = AXTextWriter()
        let clipboard = ClipboardManager()
        let converter = LayoutConverter()
        let soundPlayer = SoundPlayer()

        let orchestrator = FixOrchestrator(
            settings: settings,
            axPermission: axPermission,
            axReader: axReader,
            axWriter: axWriter,
            clipboard: clipboard,
            converter: converter,
            soundPlayer: soundPlayer
        )
        self.orchestrator = orchestrator

        let menubarManager = MenubarManager(settings: settings, orchestrator: orchestrator, openSettings: { [weak self] in
            self?.openSettingsTrigger += 1
        })
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

        // Prompt for AX permission on first launch so the event tap can be installed
        let noPromptOptions = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as NSDictionary
        if !AXIsProcessTrustedWithOptions(noPromptOptions) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let promptOptions = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as NSDictionary
                AXIsProcessTrustedWithOptions(promptOptions)
            }
        }
    }
}
