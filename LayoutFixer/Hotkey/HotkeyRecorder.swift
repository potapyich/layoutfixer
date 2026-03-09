import SwiftUI
import AppKit

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: HotkeyDefinition

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.onHotkeyChanged = { newHotkey in
            hotkey = newHotkey
        }
        view.currentHotkey = hotkey
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        nsView.currentHotkey = hotkey
        nsView.onHotkeyChanged = { newHotkey in
            hotkey = newHotkey
        }
    }
}

class HotkeyRecorderView: NSView {
    enum State {
        case idle
        case recording
    }

    var currentHotkey: HotkeyDefinition = .default {
        didSet { updateDisplay() }
    }
    var onHotkeyChanged: ((HotkeyDefinition) -> Void)?

    private var recordingState: State = .idle
    private var conflictWarning = false

    private let label = NSTextField(labelWithString: "")
    private let warningLabel = NSTextField(labelWithString: "")

    private let systemConflicts: Set<String> = ["⌘ Space", "⌃ Space", "⌘ Tab", "⌘ Q", "⌘ W", "⌘ H", "⌘ M"]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        warningLabel.textColor = .systemOrange
        warningLabel.font = .systemFont(ofSize: 11)

        addSubview(label)
        addSubview(warningLabel)

        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            warningLabel.topAnchor.constraint(equalTo: bottomAnchor, constant: 2),
            warningLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
        ])

        updateDisplay()
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startRecording()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { startRecording() }
        return result
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    private func startRecording() {
        recordingState = .recording
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        label.stringValue = "Press shortcut…"
    }

    private func stopRecording() {
        recordingState = .idle
        layer?.borderColor = NSColor.separatorColor.cgColor
        updateDisplay()
    }

    private func updateDisplay() {
        guard recordingState == .idle else { return }
        label.stringValue = currentHotkey.displayString
    }

    override func keyDown(with event: NSEvent) {
        guard recordingState == .recording else {
            super.keyDown(with: event)
            return
        }

        let keyCode = UInt16(event.keyCode)

        if keyCode == 53 { // Escape
            stopRecording()
            return
        }

        if keyCode == 51 || keyCode == 117 { // Delete/Backspace
            let defaultHotkey = HotkeyDefinition.default
            currentHotkey = defaultHotkey
            onHotkeyChanged?(defaultHotkey)
            stopRecording()
            return
        }

        let modifiers = event.modifierFlags
        let relevantMods = modifiers.intersection([.control, .option, .command, .shift])
        guard !relevantMods.isEmpty else { return }

        var cgFlags: UInt64 = 0
        if modifiers.contains(.control) { cgFlags |= CGEventFlags.maskControl.rawValue }
        if modifiers.contains(.option)  { cgFlags |= CGEventFlags.maskAlternate.rawValue }
        if modifiers.contains(.command) { cgFlags |= CGEventFlags.maskCommand.rawValue }
        if modifiers.contains(.shift)   { cgFlags |= CGEventFlags.maskShift.rawValue }

        let newHotkey = HotkeyDefinition(keyCode: keyCode, modifierFlags: cgFlags)
        checkConflict(newHotkey)
        currentHotkey = newHotkey
        onHotkeyChanged?(newHotkey)
        stopRecording()
    }

    private func checkConflict(_ hotkey: HotkeyDefinition) {
        let display = hotkey.displayString
        if systemConflicts.contains(display) {
            warningLabel.stringValue = "⚠️ Conflicts with a system shortcut"
        } else {
            warningLabel.stringValue = ""
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 200, height: 28)
    }
}
