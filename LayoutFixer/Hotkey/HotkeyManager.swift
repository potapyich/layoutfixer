import CoreGraphics
import AppKit

class HotkeyManager {
    private let settings: AppSettings
    private let onTrigger: @MainActor () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(settings: AppSettings, onTrigger: @escaping @MainActor () -> Void) {
        self.settings = settings
        self.onTrigger = onTrigger
    }

    func enable() {
        guard AXIsProcessTrustedWithOptions(nil) else { return }
        installTap()
    }

    func disable() {
        removeTap()
    }

    private func installTap() {
        removeTap()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let ptr = userInfo else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
                return manager.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else { return }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard settings.isEnabled else { return Unmanaged.passRetained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue & CGEventFlags.maskNonCoalesced.rawValue.advanced(by: -1)
        let hotkey = settings.hotkey

        let relevantFlags = event.flags.rawValue & (
            CGEventFlags.maskAlternate.rawValue |
            CGEventFlags.maskCommand.rawValue |
            CGEventFlags.maskControl.rawValue |
            CGEventFlags.maskShift.rawValue
        )

        if keyCode == hotkey.keyCode && relevantFlags == hotkey.modifierFlags {
            let trigger = onTrigger
            DispatchQueue.main.async {
                trigger()
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}
