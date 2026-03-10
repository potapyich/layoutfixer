import Foundation
import AppKit
import CoreGraphics
import os

@MainActor
class FixOrchestrator {
    private let settings: AppSettings
    private let axPermission: AXPermissionManager
    private let axReader: AXTextReader
    private let axWriter: AXTextWriter
    private let clipboard: ClipboardManager
    private let converter: LayoutConverter
    private let soundPlayer: SoundPlayer
    var statusIconAnimator: StatusIconAnimator?

    private let cycleManager = LayoutCycleManager()
    private var isFirstPermissionDenial = true
    /// Prevents concurrent trigger() executions.
    /// Safe without a lock because the whole class is @MainActor:
    /// the flag is read/written on the main actor, and each `await` suspension
    /// returns to the main actor before any other code can run here.
    private var isConverting = false

    private let logger = Logger(subsystem: "com.yourname.LayoutSwitcherCC", category: "Orchestration")

    init(
        settings: AppSettings,
        axPermission: AXPermissionManager,
        axReader: AXTextReader,
        axWriter: AXTextWriter,
        clipboard: ClipboardManager,
        converter: LayoutConverter,
        soundPlayer: SoundPlayer
    ) {
        self.settings = settings
        self.axPermission = axPermission
        self.axReader = axReader
        self.axWriter = axWriter
        self.clipboard = clipboard
        self.converter = converter
        self.soundPlayer = soundPlayer
    }

    // MARK: - Entry point

    func trigger() async {
        guard !isConverting else {
            logger.debug("Conversion in progress — ignoring rapid hotkey press")
            return
        }
        isConverting = true
        defer { isConverting = false }

        logger.debug("Hotkey triggered")

        guard axPermission.isGranted() else {
            logger.debug("AX permission not granted")
            if isFirstPermissionDenial {
                isFirstPermissionDenial = false
                axPermission.promptIfNeeded()
            }
            return
        }

        guard let pair = cycleManager.currentPair(settings: settings) else {
            logger.debug("No layout pair — add at least 2 layouts in Settings")
            return
        }

        logger.debug("Converting: \(pair.sourceID) → \(pair.targetID)")

        guard let element = axReader.focusedElement() else {
            logger.debug("No focused element")
            return
        }

        // ── AX path (native apps: TextEdit, Safari, …) ──────────────────────────
        if let selRange = axReader.selectionRange(of: element), selRange.length > 0 {
            guard let selectedText = axReader.selectedText(of: element),
                  !selectedText.isEmpty else {
                await keyboardFallback(pair: pair)
                return
            }
            await finishAX(text: selectedText, range: selRange, element: element, pair: pair)

        } else if let (word, range) = axReader.lastWord(of: element) {
            await finishAX(text: word, range: range, element: element, pair: pair)

        } else {
            // ── Keyboard+clipboard fallback (Electron/CEF) ─────────────────────
            logger.debug("AX read failed, using keyboard+clipboard fallback")
            await keyboardFallback(pair: pair)
        }
    }

    // MARK: - AX write path

    private func finishAX(text: String, range: CFRange,
                          element: AXUIElement, pair: LayoutCycleManager.Pair) async {
        let converted = normalize(converter.convert(text, from: pair.sourceID, to: pair.targetID))
        guard converted != text else {
            logger.debug("Conversion produced no change — no mapping for this pair?")
            return
        }

        let ok = axWriter.write(convertedText: converted, replacing: range, in: element)
        if !ok { clipboard.writeAndPaste(text: converted) }

        feedback(pair: pair)
        logger.debug("AX conversion: \(text) → \(converted)")
    }

    // MARK: - Keyboard + clipboard fallback

    /// Phase 1: ⌘C — captures an existing user selection.
    ///   VS Code/Electron line-copy always ends with \n, so we reject those.
    /// Phase 2: ⌥⇧← + ⌘C — selects the previous word (last-word mode).
    ///
    /// Both phases use clipboard-change polling (10 ms intervals, 300 ms max)
    /// instead of a fixed 150 ms sleep — so the lock is released as soon as
    /// the target app actually processes ⌘C, typically in 20–50 ms.
    private func keyboardFallback(pair: LayoutCycleManager.Pair) async {
        let savedClipboard = clipboard.saveClipboard()

        // ── Phase 1 ────────────────────────────────────────────────────────────
        let pre1 = NSPasteboard.general.changeCount
        postKey(keyCode: 8, flags: .maskCommand) // ⌘C

        if let word = await pollClipboard(ifChangedFrom: pre1),
           !word.hasSuffix("\n"), !word.hasSuffix("\r") {
            logger.debug("Keyboard fallback (selection): \(word)")
            await pasteConverted(word: word, pair: pair, savedClipboard: savedClipboard)
            return
        }

        // ── Phase 2 ────────────────────────────────────────────────────────────
        postKey(keyCode: 123, flags: [.maskAlternate, .maskShift]) // ⌥⇧←
        // Short fixed wait for the selection to take effect (no observable signal).
        try? await Task.sleep(nanoseconds: 60_000_000) // 60 ms

        let pre2 = NSPasteboard.general.changeCount
        postKey(keyCode: 8, flags: .maskCommand) // ⌘C

        guard let word = await pollClipboard(ifChangedFrom: pre2), !word.isEmpty else {
            logger.debug("Keyboard fallback: nothing to convert")
            postKey(keyCode: 124, flags: []) // ⇒ collapse ⌥⇧← selection
            clipboard.restoreClipboard(savedClipboard)
            return
        }

        logger.debug("Keyboard fallback (last word): \(word)")
        await pasteConverted(word: word, pair: pair, savedClipboard: savedClipboard)
    }

    /// Polls NSPasteboard.changeCount every 10 ms until it changes or 300 ms elapses.
    /// Returns the new clipboard string immediately when the change is detected.
    private func pollClipboard(ifChangedFrom before: Int) async -> String? {
        let pollNs: UInt64 = 10_000_000   // 10 ms per tick
        let maxTicks = 30                  // 30 × 10 ms = 300 ms max wait
        for _ in 0..<maxTicks {
            if NSPasteboard.general.changeCount != before {
                return NSPasteboard.general.string(forType: .string)
            }
            try? await Task.sleep(nanoseconds: pollNs)
        }
        return nil
    }

    private func pasteConverted(word: String, pair: LayoutCycleManager.Pair,
                                savedClipboard: [[NSPasteboard.PasteboardType: Data]]) async {
        let converted = normalize(converter.convert(word, from: pair.sourceID, to: pair.targetID))
        guard converted != word else {
            logger.debug("Conversion produced no change for '\(word)' (\(pair.sourceID)→\(pair.targetID))")
            clipboard.restoreClipboard(savedClipboard)
            return
        }

        // Type directly — avoids ⌘V cursor-to-beginning issues in Electron apps.
        typeText(converted)
        clipboard.restoreClipboard(savedClipboard)

        feedback(pair: pair)
        logger.debug("Keyboard fallback: \(word) → \(converted)")
    }

    // MARK: - Helpers

    private func normalize(_ text: String) -> String {
        var s = text
        while s.hasSuffix("\n") || s.hasSuffix("\r") { s = String(s.dropLast()) }
        return s
    }

    private func typeText(_ text: String) {
        var utf16 = Array(text.utf16)
        let src  = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func feedback(pair: LayoutCycleManager.Pair) {
        InputSourceManager.shared.switchTo(layoutID: pair.targetID)
        if settings.soundEnabled {
            soundPlayer.play(name: settings.soundName, volume: settings.soundVolume)
        }
        statusIconAnimator?.animateSuccess(targetLayout: pair.target)
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src  = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags   = flags
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
