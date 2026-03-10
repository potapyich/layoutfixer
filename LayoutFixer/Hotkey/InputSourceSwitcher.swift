import Carbon
import os

/// Reads and switches macOS keyboard input sources via the TIS API.
///
/// # Layout classification
///
/// `support(for:)` returns one of three tiers:
///
/// - `.full`   — Explicit character mapping in `LayoutMapping` (RU, DE, FR, …).
///               Letters AND punctuation convert accurately.
///
/// - `.qwerty` — No explicit mapping, but `UCKeyTranslate` confirmed the layout
///               uses QWERTY physical key positions (Dutch, Spanish, Italian, …).
///               Letters convert accurately; punctuation keys may be imprecise.
///
/// - `.none`   — Non-QWERTY layout with no mapping (Greek, Arabic, CJK, …).
///               Cannot convert; shown with ✗ in Settings.
///
/// Detection is performed once per layout ID and cached for the process lifetime.
class InputSourceManager {
    static let shared = InputSourceManager()
    private let logger = Logger(subsystem: "com.yourname.LayoutSwitcherCC", category: "InputSource")

    /// Cache: TIS source ID → true if QWERTY-based (determined by UCKeyTranslate).
    private var qwertyCache: [String: Bool] = [:]

    private init() {}

    // MARK: - Layout support tier

    /// Returns the conversion support level for a TIS source ID.
    /// Call this everywhere you previously called `LayoutMapping.hasMapping(for:)`.
    func support(for layoutID: String) -> LayoutSupport {
        if LayoutMapping.isQwertyBase(layoutID) || LayoutMapping.hasExplicitMapping(for: layoutID) {
            return .full
        }
        // Check runtime cache first, then probe TIS if needed.
        if let cached = qwertyCache[layoutID] {
            return cached ? .qwerty : .none
        }
        return probeAndCache(layoutID)
    }

    // MARK: - Available layouts

    /// Keyboard input sources the user has added in System Settings → Keyboard → Input Sources.
    /// Uses `kTISPropertyInputSourceIsSelected` (user's active list) instead of
    /// `kTISPropertyInputSourceIsEnabled` (every layout macOS ships, 20+ US variants).
    /// Also populates the QWERTY cache for all returned sources.
    func availableLayouts() -> [LayoutInfo] {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelected as String: true,
        ]
        let sources = TISCreateInputSourceList(filter as CFDictionary, false)
            .takeRetainedValue() as! [TISInputSource]

        return sources.compactMap { source in
            guard
                let idPtr   = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
            else { return nil }

            let id   = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue()   as String
            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String

            var langs: [String] = []
            if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
                langs = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as! [String]
            }

            // Populate QWERTY cache while we already have the TISInputSource reference.
            if qwertyCache[id] == nil, !LayoutMapping.isQwertyBase(id), !LayoutMapping.hasExplicitMapping(for: id) {
                qwertyCache[id] = isQwertyBased(source)
            }

            return LayoutInfo(id: id, name: name, flag: LayoutInfo.flag(for: langs, sourceID: id))
        }
    }

    // MARK: - Current layout

    /// TIS source ID of the currently active keyboard layout.
    func currentLayoutID() -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    // MARK: - Switch

    func switchTo(layoutID: String) {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceID as String: layoutID,
        ]
        let sources = TISCreateInputSourceList(filter as CFDictionary, false)
            .takeRetainedValue() as! [TISInputSource]
        guard let source = sources.first else {
            logger.debug("No source found for ID: \(layoutID)")
            return
        }
        TISSelectInputSource(source)
        logger.debug("Switched to: \(layoutID)")
    }

    // MARK: - Defaults

    /// Suggested starter list: English base + first non-English installed layout.
    func suggestedDefaults() -> [LayoutInfo] {
        let all = availableLayouts()
        var result: [LayoutInfo] = []
        if let en = all.first(where: { LayoutMapping.isQwertyBase($0.id) }) { result.append(en) }
        if let other = all.first(where: { !result.contains($0) })           { result.append(other) }
        return result.isEmpty ? Array(all.prefix(2)) : result
    }

    // MARK: - UCKeyTranslate-based QWERTY detection

    /// Uses `UCKeyTranslate` to check whether physical key 12 (the Q key on all
    /// Apple keyboards) produces the character `'q'` in the given layout.
    /// If it does, the layout uses QWERTY letter positions.
    ///
    /// This covers every QWERTY-based layout Apple ships — Dutch, Spanish, Italian,
    /// Portuguese, all Nordic variants, Polish, Czech, Hungarian, Turkish-Q, etc. —
    /// without needing a hardcoded list.
    private func isQwertyBased(_ source: TISInputSource) -> Bool {
        guard let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return false
        }
        let cfData = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue() as Data
        return cfData.withUnsafeBytes { rawPtr -> Bool in
            guard let layoutPtr = rawPtr.baseAddress?
                .assumingMemoryBound(to: UCKeyboardLayout.self) else { return false }
            var char       = UniChar(0)
            var deadState  = UInt32(0)
            var actualLen  = 0
            let status = UCKeyTranslate(
                layoutPtr,
                12,                                        // virtual key code: Q key
                UInt16(kUCKeyActionDown),
                0,                                         // no modifier keys
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadState, 1, &actualLen, &char
            )
            return status == noErr && actualLen == 1 && char == 0x71 // 'q'
        }
    }

    /// Probe TIS for a specific layout ID (cache-miss path for IDs loaded from
    /// persisted AppSettings that weren't in the last `availableLayouts()` call).
    private func probeAndCache(_ layoutID: String) -> LayoutSupport {
        let filter: [String: Any] = [
            kTISPropertyInputSourceID as String: layoutID
        ]
        let sources = TISCreateInputSourceList(filter as CFDictionary, false)
            .takeRetainedValue() as! [TISInputSource]
        guard let source = sources.first else {
            qwertyCache[layoutID] = false
            return .none
        }
        let result = isQwertyBased(source)
        qwertyCache[layoutID] = result
        return result ? .qwerty : .none
    }
}
