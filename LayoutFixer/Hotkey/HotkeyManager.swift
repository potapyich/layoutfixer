import CoreGraphics
import AppKit
import os

class HotkeyManager {
    private let settings: AppSettings
    private let onTrigger: @MainActor () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdogTimer: Timer?
    private var selfPtr: UnsafeMutableRawPointer?

    private let logger = Logger(subsystem: "com.yourname.LayoutSwitcherCC", category: "HotkeyManager")

    init(settings: AppSettings, onTrigger: @escaping @MainActor () -> Void) {
        self.settings = settings
        self.onTrigger = onTrigger
    }

    func enable() {
        installTap()
        startWatchdog()
    }

    func disable() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        removeTap()
    }

    private func installTap() {
        removeTap()

        guard AXIsProcessTrustedWithOptions(([kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as NSDictionary)) else {
            logger.debug("AX not trusted, skipping tap install")
            return
        }

        let retained = Unmanaged.passRetained(self)
        let ptr = retained.toOpaque()
        selfPtr = ptr

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, userInfo -> Unmanaged<CGEvent>? in
                guard let ptr = userInfo else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
                return manager.handle(event: event)
            },
            userInfo: ptr
        ) else {
            retained.release()
            selfPtr = nil
            logger.error("CGEvent.tapCreate returned nil")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Event tap installed")
    }

    private func removeTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let ptr = selfPtr {
            Unmanaged<HotkeyManager>.fromOpaque(ptr).release()
            selfPtr = nil
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func startWatchdog() {
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkTapHealth()
        }
    }

    private func checkTapHealth() {
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                logger.warning("Tap was disabled, reinstalling")
                installTap()
            }
        } else {
            // Try to install if AX was granted since last attempt
            if AXIsProcessTrustedWithOptions(([kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as NSDictionary)) {
                logger.info("AX now granted, installing tap")
                installTap()
            }
        }
    }

    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard settings.isEnabled else { return Unmanaged.passRetained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let hotkey = settings.hotkey

        let relevantFlags = event.flags.rawValue & (
            CGEventFlags.maskAlternate.rawValue |
            CGEventFlags.maskCommand.rawValue |
            CGEventFlags.maskControl.rawValue |
            CGEventFlags.maskShift.rawValue
        )

        if keyCode == hotkey.keyCode && relevantFlags == hotkey.modifierFlags {
            logger.debug("Hotkey matched, consuming event")
            let trigger = onTrigger
            DispatchQueue.main.async {
                trigger()
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    deinit {
        disable()
    }
}
