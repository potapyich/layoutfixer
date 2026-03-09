import AppKit
import SwiftUI

class MenubarManager: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings: AppSettings
    private weak var orchestrator: FixOrchestrator?
    let statusIconAnimator: StatusIconAnimator

    private var enableMenuItem: NSMenuItem?

    init(settings: AppSettings, orchestrator: FixOrchestrator) {
        self.settings = settings
        self.orchestrator = orchestrator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusIconAnimator = StatusIconAnimator(statusItem: statusItem)

        super.init()

        statusItem.button?.image = NSImage(named: "MenubarIcon") ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        statusItem.button?.image?.isTemplate = true
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let enableItem = NSMenuItem(
            title: "Enable LayoutFixer",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enableItem.target = self
        enableItem.state = settings.isEnabled ? .on : .off
        self.enableMenuItem = enableItem
        menu.addItem(enableItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let accessibilityItem = NSMenuItem(
            title: "Accessibility Permissions",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "About LayoutFixer",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: "Quit LayoutFixer",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        enableMenuItem?.state = settings.isEnabled ? .on : .off
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        enableMenuItem?.state = settings.isEnabled ? .on : .off
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
