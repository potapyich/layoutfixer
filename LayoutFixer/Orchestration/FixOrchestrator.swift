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
    /// Timestamp of the last completed conversion, used to debounce rapid repeats.
    private var lastTriggerTime: Date = .distantPast

    private let logger = Logger(subsystem: "com.potapyich.LayoutFixer", category: "Orchestration")

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
        let now = Date()
        guard now.timeIntervalSince(lastTriggerTime) > 0.5 else {
            logger.debug("Debounce — ignoring hotkey within 500 ms of last trigger")
            return
        }
        isConverting = true
        defer { isConverting = false }

        let appName   = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        let appBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        logger.info("Hotkey triggered — app: \(appName, privacy: .public) (\(appBundle, privacy: .public))")

        guard axPermission.isGranted() else {
            logger.info("AX permission not granted — skipping")
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

        logger.info("Converting: \(pair.sourceID) → \(pair.targetID)")

        guard let element = axReader.focusedElement() else {
            logger.info("No focused element — trying clipboard fallback anyway")
            await keyboardFallback(pair: pair)
            return
        }

        // ── AX path (native apps: TextEdit, Safari, …) ──────────────────────────
        let selRange = axReader.selectionRange(of: element)
        logger.info("AX selectionRange: \(selRange.map { "loc=\($0.location) len=\($0.length)" } ?? "nil")")

        if let selRange, selRange.length > 0 {
            guard let selectedText = axReader.selectedText(of: element),
                  !selectedText.isEmpty else {
                logger.info("AX selectedText empty despite non-zero range — using fallback")
                await keyboardFallback(pair: pair)
                return
            }
            logger.info("AX path: selection (\(selectedText.count) chars)")
            await finishAX(text: selectedText, range: selRange, element: element, pair: pair, selectResult: true)

        } else if let (word, range) = axReader.lastWord(of: element) {
            logger.info("AX path: lastWord (\(word.count) chars)")
            await finishAX(text: word, range: range, element: element, pair: pair, selectResult: false)

        } else {
            // ── Keyboard+clipboard fallback (Electron/CEF) ─────────────────────
            logger.info("AX read failed — using keyboard+clipboard fallback")
            await keyboardFallback(pair: pair)
        }
    }

    // MARK: - AX write path

    private func finishAX(text: String, range: CFRange,
                          element: AXUIElement, pair: LayoutCycleManager.Pair,
                          selectResult: Bool) async {
        let converted = normalize(converter.convert(text, from: pair.sourceID, to: pair.targetID))
        guard converted != text else {
            logger.info("Conversion produced no change — text may already be in target layout")
            return
        }

        // Prefer AX-select + typeText over kAXValueAttribute write.
        // kAXValueAttribute updates the accessibility tree but NOT the visible DOM in
        // Chromium/Electron webview panels (e.g. VS Code extension inputs). typeText()
        // sends real keyboard events that modify the DOM regardless of the environment.
        if axWriter.selectRange(range, in: element) {
            typeText(converted)
            // For user-selection path, re-select the result after a tick.
            if selectResult {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10 ms
                axWriter.positionCursor(after: converted, replacing: range, in: element, selectResult: true)
            }
            logger.info("AX write (typeText): \(text) → \(converted)")
        } else {
            // AX selection set failed — fall back to full kAXValueAttribute write + cursor set.
            let ok = axWriter.write(convertedText: converted, replacing: range, in: element)
            if !ok { clipboard.writeAndPaste(text: converted) }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20 ms
            axWriter.positionCursor(after: converted, replacing: range, in: element, selectResult: selectResult)
            logger.info("AX write (kAXValue fallback ok=\(ok)): \(text) → \(converted)")
        }

        feedback(pair: pair)
    }

    // MARK: - Keyboard + clipboard fallback

    /// Phase 1: ⌘C — captures an existing user selection.
    ///   VS Code/Electron line-copy always ends with \n, so we reject those.
    /// Phase 2: ⌥⇧← + ⌘C — selects the previous word (last-word mode).
    ///
    /// Both phases use clipboard-change polling (configurable timeout, default 100 ms)
    /// instead of a fixed sleep — so the lock is released as soon as the target app
    /// actually processes ⌘C, typically in 20–50 ms.
    private func keyboardFallback(pair: LayoutCycleManager.Pair) async {
        let savedClipboard = clipboard.saveClipboard()

        // ── Phase 1: ⌘C — try to copy existing selection ──────────────────────
        let pre1 = NSPasteboard.general.changeCount
        logger.info("Fallback Phase 1: posting ⌘C (changeCount=\(pre1))")
        postKey(keyCode: 8, flags: .maskCommand) // ⌘C
        let t1 = Date()

        if let word = await pollClipboard(ifChangedFrom: pre1) {
            let ms = Int(Date().timeIntervalSince(t1) * 1000)
            if !word.hasSuffix("\n"), !word.hasSuffix("\r") {
                logger.info("Fallback Phase 1: clipboard changed in \(ms)ms — selection \(word.count) chars")
                await pasteConverted(word: word, pair: pair, savedClipboard: savedClipboard)
                return
            }
            logger.info("Fallback Phase 1: clipboard changed in \(ms)ms but content ends with newline — skipping to Phase 2")
        } else {
            let ms = Int(Date().timeIntervalSince(t1) * 1000)
            let post1 = NSPasteboard.general.changeCount
            logger.info("Fallback Phase 1: clipboard unchanged after \(ms)ms (changeCount still=\(post1)) — ⌘C may be blocked")
        }

        // ── Phase 2: ⌥⇧← + ⌘C — select and copy the previous word ───────────
        postKey(keyCode: 123, flags: [.maskAlternate, .maskShift]) // ⌥⇧←
        try? await Task.sleep(nanoseconds: 60_000_000) // 60 ms

        let pre2 = NSPasteboard.general.changeCount
        logger.info("Fallback Phase 2: posting ⌘C (changeCount=\(pre2))")
        postKey(keyCode: 8, flags: .maskCommand) // ⌘C
        let t2 = Date()

        guard let word = await pollClipboard(ifChangedFrom: pre2), !word.isEmpty else {
            let ms = Int(Date().timeIntervalSince(t2) * 1000)
            let post2 = NSPasteboard.general.changeCount
            logger.info("Fallback Phase 2: clipboard empty/unchanged after \(ms)ms (changeCount=\(pre2)→\(post2)) — nothing to convert")
            postKey(keyCode: 124, flags: []) // ⇒ collapse ⌥⇧← selection
            clipboard.restoreClipboard(savedClipboard)
            return
        }

        let ms = Int(Date().timeIntervalSince(t2) * 1000)
        logger.info("Fallback Phase 2: clipboard changed in \(ms)ms — last word \(word.count) chars")
        await pasteConverted(word: word, pair: pair, savedClipboard: savedClipboard, collapseSelectionOnNoChange: true)
    }

    /// Polls NSPasteboard.changeCount every 10 ms until it changes or the configured timeout elapses.
    private func pollClipboard(ifChangedFrom before: Int) async -> String? {
        let pollNs: UInt64 = 10_000_000
        let maxTicks = max(1, settings.clipboardPollTimeoutMs / 10)
        for _ in 0..<maxTicks {
            if NSPasteboard.general.changeCount != before {
                return NSPasteboard.general.string(forType: .string)
            }
            try? await Task.sleep(nanoseconds: pollNs)
        }
        return nil
    }

    private func pasteConverted(word: String, pair: LayoutCycleManager.Pair,
                                savedClipboard: [[NSPasteboard.PasteboardType: Data]],
                                collapseSelectionOnNoChange: Bool = false) async {
        let converted = normalize(converter.convert(word, from: pair.sourceID, to: pair.targetID))
        guard converted != word else {
            logger.debug("Conversion produced no change for '\(word)' (\(pair.sourceID)→\(pair.targetID))")
            if collapseSelectionOnNoChange {
                // Phase 2 used ⌥⇧← to create a selection but nothing was typed to replace it.
                // Collapse the selection so subsequent hotkey presses don't see a stale
                // "selection (N chars)" of already-converted text → endless "no change" loop.
                postKey(keyCode: 124, flags: []) // →
            }
            clipboard.restoreClipboard(savedClipboard)
            return
        }

        // Type directly — avoids ⌘V cursor-to-beginning issues in Electron apps.
        typeText(converted)
        clipboard.restoreClipboard(savedClipboard)

        feedback(pair: pair)
        logger.info("Keyboard fallback: \(word) → \(converted)")
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
        // Explicitly clear all modifier flags.
        // CGEventSource(.hidSystemState) reflects the current hardware state, so if
        // the user's hotkey modifier (e.g. ⌥) is still physically held, the event
        // would inherit that flag. Without this clear, the event could be: virtualKey=0
        // + maskAlternate = ⌥A, which our own tap would intercept and consume, silently
        // eating the typed text instead of delivering it to the app.
        down?.flags = []
        up?.flags   = []
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func feedback(pair: LayoutCycleManager.Pair) {
        lastTriggerTime = Date()
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
