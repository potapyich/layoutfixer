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
    private let detector: DirectionDetector
    private let soundPlayer: SoundPlayer
    var statusIconAnimator: StatusIconAnimator?

    private var isFirstPermissionDenial = true

    private let logger = Logger(subsystem: "com.yourname.LayoutSwitcherCC", category: "Orchestration")

    init(
        settings: AppSettings,
        axPermission: AXPermissionManager,
        axReader: AXTextReader,
        axWriter: AXTextWriter,
        clipboard: ClipboardManager,
        converter: LayoutConverter,
        detector: DirectionDetector,
        soundPlayer: SoundPlayer
    ) {
        self.settings = settings
        self.axPermission = axPermission
        self.axReader = axReader
        self.axWriter = axWriter
        self.clipboard = clipboard
        self.converter = converter
        self.detector = detector
        self.soundPlayer = soundPlayer
    }

    func trigger() async {
        logger.debug("Hotkey triggered")

        guard axPermission.isGranted() else {
            logger.debug("AX permission not granted")
            if isFirstPermissionDenial {
                isFirstPermissionDenial = false
                axPermission.promptIfNeeded()
            }
            return
        }

        guard let element = axReader.focusedElement() else {
            logger.debug("No focused element")
            return
        }

        // Try direct AX read path first (native apps: TextEdit, Safari, etc.)
        if let selRange = axReader.selectionRange(of: element), selRange.length > 0 {
            guard let selectedText = axReader.selectedText(of: element),
                  !selectedText.isEmpty else {
                await keyboardFallback()
                return
            }
            await finishConversion(text: selectedText, range: selRange, element: element)

        } else if let (word, range) = axReader.lastWord(of: element) {
            await finishConversion(text: word, range: range, element: element)

        } else {
            // AX read failed (Electron/CEF apps like VS Code)
            logger.debug("AX read failed, using keyboard+clipboard fallback")
            await keyboardFallback()
        }
    }

    // MARK: - AX write path (native apps)

    private func finishConversion(text: String, range: CFRange, element: AXUIElement) async {
        guard let direction = detector.detectDirection(text) else {
            logger.debug("Could not detect direction for: \(text)")
            return
        }

        var converted = converter.convert(text, direction: direction)
        while converted.hasSuffix("\n") || converted.hasSuffix("\r") {
            converted = String(converted.dropLast())
        }

        let writeSuccess = axWriter.write(convertedText: converted, replacing: range, in: element)
        if !writeSuccess {
            clipboard.writeAndPaste(text: converted)
        }

        feedback(direction: direction)
        logger.debug("AX conversion: \(text) → \(converted)")
    }

    // MARK: - Keyboard + clipboard fallback (Electron/CEF apps)

    /// Two-phase strategy that avoids relying on unreliable AX selectedText attribute:
    ///
    /// Phase 1 — try ⌘C immediately.
    ///   VS Code copies current selection to clipboard without modifying the selection.
    ///   If the clipboard changed and the result looks like a real selection (non-empty,
    ///   no trailing newline — VS Code's "copy whole line" always appends \n), use it.
    ///
    /// Phase 2 — if Phase 1 gave nothing useful, select the previous word with ⌥⇧←
    ///   then ⌘C again (last-word mode).
    private func keyboardFallback() async {
        let savedClipboard = clipboard.saveClipboard()

        // ── Phase 1: copy whatever is currently selected ──────────────────────────
        let preCount1 = NSPasteboard.general.changeCount
        postKey(keyCode: 8, flags: .maskCommand) // ⌘C
        try? await Task.sleep(nanoseconds: 150_000_000)

        if let word = clipboardString(ifChangedFrom: preCount1),
           !word.hasSuffix("\n"), !word.hasSuffix("\r"),  // VS Code "copy line" always ends with \n
           let direction = detector.detectDirection(word) {

            logger.debug("Keyboard fallback (selection): \(word)")
            await pasteConverted(word: word, direction: direction, savedClipboard: savedClipboard)
            return
        }

        // ── Phase 2: no usable selection — select previous word ───────────────────
        let preCount2 = NSPasteboard.general.changeCount
        postKey(keyCode: 123, flags: [.maskAlternate, .maskShift]) // ⌥⇧←
        try? await Task.sleep(nanoseconds: 80_000_000)
        postKey(keyCode: 8, flags: .maskCommand) // ⌘C
        try? await Task.sleep(nanoseconds: 150_000_000)

        guard let word = clipboardString(ifChangedFrom: preCount2),
              !word.isEmpty,
              let direction = detector.detectDirection(word) else {
            logger.debug("Keyboard fallback: nothing to convert")
            postKey(keyCode: 124, flags: []) // ⇒ collapse the ⌥⇧← selection
            clipboard.restoreClipboard(savedClipboard)
            return
        }

        logger.debug("Keyboard fallback (last word): \(word)")
        await pasteConverted(word: word, direction: direction, savedClipboard: savedClipboard)
    }

    private func pasteConverted(word: String, direction: ConversionDirection,
                                savedClipboard: [[NSPasteboard.PasteboardType: Data]]) async {
        var converted = converter.convert(word, direction: direction)
        while converted.hasSuffix("\n") || converted.hasSuffix("\r") {
            converted = String(converted.dropLast())
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(converted, forType: .string)
        postKey(keyCode: 9, flags: .maskCommand) // ⌘V

        clipboard.restoreClipboard(savedClipboard)

        feedback(direction: direction)
        logger.debug("Keyboard fallback: \(word) → \(converted)")
    }

    // MARK: - Helpers

    /// Returns the clipboard string only if the changeCount increased (i.e. ⌘C actually wrote something).
    private func clipboardString(ifChangedFrom preCount: Int) -> String? {
        guard NSPasteboard.general.changeCount != preCount else { return nil }
        return NSPasteboard.general.string(forType: .string)
    }

    private let inputSwitcher = InputSourceSwitcher()

    private func feedback(direction: ConversionDirection) {
        inputSwitcher.switchTo(direction)
        if settings.soundEnabled {
            soundPlayer.play(name: settings.soundName, volume: settings.soundVolume)
        }
        statusIconAnimator?.animateSuccess(resultLanguage: direction)
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags   = flags
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
