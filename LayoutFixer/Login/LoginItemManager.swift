import ServiceManagement
import os

class LoginItemManager {
    static let shared = LoginItemManager()

    private let logger = Logger(subsystem: "com.yourname.LayoutSwitcherCC", category: "LoginItem")

    private init() {}

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("Registered login item")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Unregistered login item")
            }
        } catch {
            logger.error("Login item error: \(error.localizedDescription)")
        }
    }

    var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func registerIfNeeded(settings: AppSettings) {
        if settings.launchAtLogin && !isRegistered {
            setEnabled(true)
        }
    }
}
