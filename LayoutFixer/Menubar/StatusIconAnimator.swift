import AppKit

class StatusIconAnimator {
    private weak var statusItem: NSStatusItem?
    private var pendingTask: DispatchWorkItem?

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
    }

    func animateSuccess(resultLanguage: ConversionDirection) {
        pendingTask?.cancel()

        let flagImage = Self.flagImage(for: resultLanguage)
        let defaultImage = Self.defaultIcon()

        // Blink: flag → default → flag → default (2 cycles, 400 ms each)
        statusItem?.button?.image = flagImage

        schedule(after: 0.4) { [weak self] in self?.statusItem?.button?.image = defaultImage }
        schedule(after: 0.7) { [weak self] in self?.statusItem?.button?.image = flagImage }

        let final = DispatchWorkItem { [weak self] in
            self?.statusItem?.button?.image = defaultImage
            self?.pendingTask = nil
        }
        pendingTask = final
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: final)
    }

    // MARK: - Icon helpers

    static func defaultIcon() -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let img = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "LayoutSwitcher_CC")?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = true
        return img ?? NSImage()
    }

    private static func flagImage(for direction: ConversionDirection) -> NSImage {
        // Render the country flag emoji as a small bitmap — works in any macOS theme.
        let emoji = direction == .enToRu ? "🇷🇺" : "🇺🇸"
        let size: CGFloat = 18
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size * 0.85)]
        let textSize = (emoji as NSString).size(withAttributes: attrs)

        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            (emoji as NSString).draw(
                at: NSPoint(x: (rect.width - textSize.width) / 2,
                            y: (rect.height - textSize.height) / 2),
                withAttributes: attrs
            )
            return true
        }
    }

    private func schedule(after delay: TimeInterval, block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
}
