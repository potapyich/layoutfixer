import Carbon
import os

/// Switches the active macOS keyboard input source to match the conversion result.
struct InputSourceSwitcher {
    private let logger = Logger(subsystem: "com.yourname.LayoutSwitcherCC", category: "InputSource")

    func switchTo(_ direction: ConversionDirection) {
        let targetPrefix = direction == .enToRu ? "ru" : "en"

        // Only enumerate enabled, selectable keyboard input sources
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ]

        let list = TISCreateInputSourceList(filter as CFDictionary, false)
            .takeRetainedValue() as! [TISInputSource]

        for source in list {
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { continue }
            let langs = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as! [String]
            if langs.first?.hasPrefix(targetPrefix) == true {
                TISSelectInputSource(source)
                logger.debug("Switched input source to \(targetPrefix)")
                return
            }
        }

        logger.debug("No input source found for language prefix: \(targetPrefix)")
    }
}
