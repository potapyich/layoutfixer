import AppKit
import CoreGraphics

class ClipboardManager {
    func saveClipboard() -> [[NSPasteboard.PasteboardType: Data]] {
        var saved: [[NSPasteboard.PasteboardType: Data]] = []
        let pasteboard = NSPasteboard.general
        for item in pasteboard.pasteboardItems ?? [] {
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            if !entry.isEmpty {
                saved.append(entry)
            }
        }
        return saved
    }

    func setString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func paste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    func restoreClipboard(_ saved: [[NSPasteboard.PasteboardType: Data]]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            for entry in saved {
                let item = NSPasteboardItem()
                for (type, data) in entry {
                    item.setData(data, forType: type)
                }
                pasteboard.writeObjects([item])
            }
        }
    }

    func writeAndPaste(text: String) {
        let saved = saveClipboard()
        setString(text)
        paste()
        restoreClipboard(saved)
    }
}
