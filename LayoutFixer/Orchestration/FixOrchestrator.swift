import Foundation
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

    private let logger = Logger(subsystem: "com.yourname.LayoutFixer", category: "Orchestration")

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

        let textToConvert: String
        let rangeToReplace: CFRange

        if let selRange = axReader.selectionRange(of: element), selRange.length > 0 {
            guard let selectedText = axReader.selectedText(of: element),
                  !selectedText.isEmpty else { return }
            textToConvert = selectedText
            rangeToReplace = selRange
        } else {
            guard let (word, range) = axReader.lastWord(of: element) else {
                logger.debug("No last word found")
                return
            }
            textToConvert = word
            rangeToReplace = range
        }

        guard let direction = detector.detectDirection(textToConvert) else {
            logger.debug("Could not detect direction for: \(textToConvert)")
            return
        }

        var convertedText = converter.convert(textToConvert, direction: direction)

        // Normalize: remove trailing newlines
        while convertedText.hasSuffix("\n") || convertedText.hasSuffix("\r") {
            convertedText = String(convertedText.dropLast())
        }

        let writeSuccess = axWriter.write(convertedText: convertedText, replacing: rangeToReplace, in: element)
        if !writeSuccess {
            clipboard.writeAndPaste(text: convertedText)
        }

        if settings.soundEnabled {
            soundPlayer.play(name: settings.soundName, volume: settings.soundVolume)
        }

        statusIconAnimator?.animateSuccess(resultLanguage: direction)
        logger.debug("Conversion complete: \(textToConvert) -> \(convertedText)")
    }
}
