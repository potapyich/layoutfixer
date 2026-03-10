import SwiftUI
import AppKit

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: HotkeyDefinition

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.currentHotkey = hotkey
        view.onHotkeyChanged = { newHotkey in hotkey = newHotkey }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        if nsView.currentHotkey != hotkey {
            nsView.currentHotkey = hotkey
        }
        nsView.onHotkeyChanged = { newHotkey in hotkey = newHotkey }
    }
}

class HotkeyRecorderView: NSView {
    enum RecordingState { case idle, recording }

    var currentHotkey: HotkeyDefinition = .default {
        didSet { refreshDisplay() }
    }
    var onHotkeyChanged: ((HotkeyDefinition) -> Void)?

    private var state: RecordingState = .idle

    // Always shows the current hotkey (large, prominent)
    private let hotkeyLabel: NSTextField = {
        let f = NSTextField(labelWithString: "")
        f.translatesAutoresizingMaskIntoConstraints = false
        f.alignment = .center
        f.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        return f
    }()

    // Secondary hint below the hotkey
    private let hintLabel: NSTextField = {
        let f = NSTextField(labelWithString: "")
        f.translatesAutoresizingMaskIntoConstraints = false
        f.alignment = .center
        f.font = .systemFont(ofSize: 10)
        f.textColor = .secondaryLabelColor
        return f
    }()

    private let warningLabel: NSTextField = {
        let f = NSTextField(labelWithString: "")
        f.translatesAutoresizingMaskIntoConstraints = false
        f.font = .systemFont(ofSize: 11)
        f.textColor = .systemOrange
        return f
    }()

    private let systemConflicts: Set<String> = [
        "⌘ Space", "⌃ Space", "⌘ Tab", "⌘ Q", "⌘ W", "⌘ H", "⌘ M"
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1.5

        addSubview(hotkeyLabel)
        addSubview(hintLabel)
        addSubview(warningLabel)

        NSLayoutConstraint.activate([
            hotkeyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hotkeyLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -7),

            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: hotkeyLabel.bottomAnchor, constant: 3),

            warningLabel.topAnchor.constraint(equalTo: bottomAnchor, constant: 3),
            warningLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
        ])

        refreshDisplay()
        applyAppearance()
    }

    private func refreshDisplay() {
        switch state {
        case .idle:
            hotkeyLabel.stringValue = currentHotkey.displayString
            hotkeyLabel.textColor = .labelColor
            hintLabel.stringValue = "Click to record"
        case .recording:
            // Keep showing the current hotkey so user knows what they're replacing
            hotkeyLabel.stringValue = currentHotkey.displayString
            hotkeyLabel.textColor = .secondaryLabelColor
            hintLabel.stringValue = "Press new shortcut… (Esc to cancel, ⌫ to reset)"
        }
    }

    private func applyAppearance() {
        switch state {
        case .idle:
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        case .recording:
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
    }

    // MARK: - First responder & input

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Only start recording on an explicit click, never on tab-focus alone
        if state == .idle {
            window?.makeFirstResponder(self)
            startRecording()
        }
    }

    // Do NOT start recording in becomeFirstResponder — that fires on tab/window activation
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { applyAppearance() }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    private func startRecording() {
        state = .recording
        applyAppearance()
        refreshDisplay()
    }

    private func stopRecording() {
        state = .idle
        applyAppearance()
        refreshDisplay()
    }

    override func keyDown(with event: NSEvent) {
        guard state == .recording else {
            super.keyDown(with: event)
            return
        }

        let keyCode = UInt16(event.keyCode)

        if keyCode == 53 { // Escape — cancel, keep existing hotkey
            window?.makeFirstResponder(nil)
            return
        }

        if keyCode == 51 || keyCode == 117 { // Delete/Backspace — reset to default
            currentHotkey = .default
            onHotkeyChanged?(.default)
            warningLabel.stringValue = ""
            window?.makeFirstResponder(nil)
            return
        }

        let mods = event.modifierFlags.intersection([.control, .option, .command, .shift])
        guard !mods.isEmpty else { return } // Require at least one modifier

        var cgFlags: UInt64 = 0
        if mods.contains(.control) { cgFlags |= CGEventFlags.maskControl.rawValue }
        if mods.contains(.option)  { cgFlags |= CGEventFlags.maskAlternate.rawValue }
        if mods.contains(.command) { cgFlags |= CGEventFlags.maskCommand.rawValue }
        if mods.contains(.shift)   { cgFlags |= CGEventFlags.maskShift.rawValue }

        let newHotkey = HotkeyDefinition(keyCode: keyCode, modifierFlags: cgFlags)
        warningLabel.stringValue = systemConflicts.contains(newHotkey.displayString)
            ? "⚠️ Conflicts with a system shortcut"
            : ""

        currentHotkey = newHotkey
        onHotkeyChanged?(newHotkey)
        window?.makeFirstResponder(nil)
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 240, height: 52) }

    override func updateLayer() { applyAppearance() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyAppearance() }
}
