import AppKit
import CoreGraphics

/// Manages clipboard save/restore around conversion paste operations.
///
/// Rapid consecutive hotkey presses create a race: press N schedules
/// restoreClipboard(asyncAfter 0.15 s), then press N+1 starts before that
/// fires.  To avoid the restore from a previous call polluting the next
/// operation's clipboard reads, we track the pending restore with a
/// cancellable DispatchWorkItem.
///
/// When saveClipboard() is called while a restore is still pending:
///   • The pending restore is cancelled (won't fire later).
///   • The "true original" content (what the previous restore would have
///     written) is returned as the new save — so the original user clipboard
///     is correctly threaded through any number of rapid presses.
class ClipboardManager {

    private var pendingRestore: DispatchWorkItem?
    private var pendingOriginal: [[NSPasteboard.PasteboardType: Data]]?

    // MARK: - Public API

    /// Returns the current clipboard contents to be restored later.
    /// If a prior restore is still pending, cancels it and returns its
    /// target content instead (preserving the user's true original clipboard).
    func saveClipboard() -> [[NSPasteboard.PasteboardType: Data]] {
        if let item = pendingRestore, !item.isCancelled, let original = pendingOriginal {
            item.cancel()
            pendingRestore = nil
            pendingOriginal = nil
            return original   // hand back the real original, not the converted clipboard
        }
        return snapshot()
    }

    func setString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func paste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    func restoreClipboard(_ saved: [[NSPasteboard.PasteboardType: Data]]) {
        pendingRestore?.cancel()
        pendingOriginal = saved

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.write(saved)
            self.pendingRestore = nil
            self.pendingOriginal = nil
        }
        pendingRestore = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    func writeAndPaste(text: String) {
        let saved = saveClipboard()
        setString(text)
        paste()
        restoreClipboard(saved)
    }

    // MARK: - Private

    private func snapshot() -> [[NSPasteboard.PasteboardType: Data]] {
        var result: [[NSPasteboard.PasteboardType: Data]] = []
        for item in NSPasteboard.general.pasteboardItems ?? [] {
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            if !entry.isEmpty { result.append(entry) }
        }
        return result
    }

    private func write(_ saved: [[NSPasteboard.PasteboardType: Data]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        for entry in saved {
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            pb.writeObjects([item])
        }
    }
}
