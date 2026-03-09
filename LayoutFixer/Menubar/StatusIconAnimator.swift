import AppKit

class StatusIconAnimator {
    private weak var statusItem: NSStatusItem?
    private var pendingTask: DispatchWorkItem?

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
    }

    func animateSuccess(resultLanguage: ConversionDirection) {
        pendingTask?.cancel()

        let flagImageName = resultLanguage == .enToRu ? "flag_ru" : "flag_en"
        let flagImage = NSImage(named: flagImageName)
        statusItem?.button?.image = flagImage

        let task = DispatchWorkItem { [weak self] in
            self?.statusItem?.button?.image = NSImage(named: "MenubarIcon")
        }
        pendingTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }
}
