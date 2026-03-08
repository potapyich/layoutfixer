# LayoutFixer_CC — Implementation Plan

> **Target:** macOS 14.0 Sonoma+
> **Stack:** Swift 5.10, SwiftUI, `@Observable`, CGEventTap, AXUIElement
> **Scope:** v1 MVP as specified in `docs/PRD.md`

---

## 1. Project Setup

### Xcode Project Configuration

| Setting | Value |
|---|---|
| Product Name | LayoutFixer |
| Bundle ID | com.yourname.LayoutFixer |
| Deployment Target | macOS 14.0 |
| Application Category | Utilities |
| Code Signing | Development (GitHub release) |
| App Sandbox | **Disabled** (v1) |

### Info.plist Keys

```xml
<!-- Hide Dock icon — menubar-only app -->
<key>LSUIElement</key>
<true/>

<!-- Accessibility usage description (shown in System Settings) -->
<key>NSAccessibilityUsageDescription</key>
<string>LayoutFixer needs Accessibility access to read and replace text in other applications.</string>
```

### Entitlements (LayoutFixer.entitlements)

```xml
<!-- No sandbox for v1 — required for CGEventTap + unrestricted AX access -->
<key>com.apple.security.app-sandbox</key>
<false/>

<!-- Hardened Runtime: required for notarization -->
<key>com.apple.security.cs.allow-jit</key>
<false/>
```

> **Note on Sandbox:** CGEventTap with `kCGEventTapOptionDefault` (active tap) requires disabling the sandbox. Ship v1 outside App Store. For a future MAS release, switch to a passive tap (observation only) and rely solely on a Shortcut/Service approach, or use a privileged helper.

---

## 2. Folder & File Structure

```
LayoutFixer/
├── App/
│   ├── LayoutFixerApp.swift          # @main, NSApplicationDelegate, AppModel init
│   └── AppDelegate.swift             # NSApplicationDelegate if needed for lifecycle
│
├── Orchestration/
│   └── FixOrchestrator.swift         # Coordinates all modules on hotkey trigger
│
├── Hotkey/
│   ├── HotkeyManager.swift           # CGEventTap setup, callback, enable/disable
│   ├── HotkeyRecorder.swift          # SwiftUI view: key recorder field
│   └── HotkeyDefinition.swift        # Value type: modifiers + optional keyCode
│
├── Accessibility/
│   ├── AXPermissionManager.swift     # Check + prompt for AX permission
│   ├── AXTextReader.swift            # Read focused element, value, selection range
│   └── AXTextWriter.swift            # Write via AXValue; fallback clipboard paste
│
├── Conversion/
│   ├── LayoutMapping.swift           # QWERTY↔RU static mapping table
│   ├── DirectionDetector.swift       # Detect RU→EN or EN→RU from input string
│   └── LayoutConverter.swift         # Convert string using mapping + direction
│
├── Clipboard/
│   └── ClipboardManager.swift        # Save, set, paste (Cmd+V), restore clipboard
│
├── Menubar/
│   ├── MenubarManager.swift          # NSStatusItem, NSMenu construction
│   └── StatusIconAnimator.swift      # Swap icon → flag → icon after conversion
│
├── Settings/
│   ├── AppSettings.swift             # @Observable settings model + @AppStorage
│   └── SettingsView.swift            # SwiftUI settings window
│
├── Audio/
│   └── SoundPlayer.swift             # NSSound playback, volume, mute
│
├── Login/
│   └── LoginItemManager.swift        # SMAppService.mainApp register/unregister
│
└── Resources/
    ├── Assets.xcassets               # App icon, flag images
    └── LayoutFixer.entitlements
```

---

## 3. Module / Layer Breakdown

### 3.1 App Entry (`App/`)

`LayoutFixerApp.swift` is the `@main` entry point. It:
- Creates a single `AppModel` / `AppSettings` observable object
- Instantiates `MenubarManager`, `HotkeyManager`, `FixOrchestrator`
- Wires them together via dependency injection (pass references, not singletons where possible)
- Does **not** create a default `WindowGroup` — menubar apps suppress windows at startup

```swift
@main
struct LayoutFixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
```

### 3.2 Orchestration (`FixOrchestrator`)

Called by `HotkeyManager` on every hotkey trigger. Sequence:

```
1. Check AX permission → silent no-op if missing (prompt on first miss)
2. Read focused AX element → silent no-op if unreadable
3. Read selection range
4. IF selection non-empty  → read selected text
   ELSE                   → extract last word left of caret
5. silent no-op if nothing to convert
6. Detect direction (EN→RU or RU→EN)
7. Convert text
8. Write converted text back (AX direct → clipboard fallback)
9. Trigger audio feedback
10. Trigger icon animation
```

---

## 4. Hotkey System

### 4.1 CGEventTap

Use a **key-down event tap** at `kCGSessionEventTap` / `kCGHeadInsertEventTap` level so the hotkey fires before the target app receives the key.

```swift
// Tap key-down events
let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,          // active tap — consumes matched events
    eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
    callback: eventTapCallback,
    userInfo: Unmanaged.passRetained(self).toOpaque()
)
```

The callback inspects `CGEvent` flags and `keyCode`. If it matches the configured hotkey:
- Return `nil` to consume the event (prevent it from reaching the frontmost app)
- Schedule `FixOrchestrator.trigger()` on the main actor

### 4.2 Modifier-Only Hotkeys

A single modifier press (e.g., double-`⌥`) is **not** handled by key-down taps. For v1, **require at least one non-modifier key**. The default `⌥ Space` satisfies this.

If a modifier-only shortcut is needed in v2, use `flagsChanged` events and track consecutive presses with a timestamp.

### 4.3 `HotkeyDefinition`

```swift
struct HotkeyDefinition: Codable, Equatable {
    var keyCode: UInt16          // CGKeyCode
    var modifierFlags: UInt64    // CGEventFlags raw value (mask)

    // Human-readable string, e.g. "⌥ Space"
    var displayString: String { ... }

    // Serialise to/from UserDefaults via Codable
}
```

### 4.4 Key Recorder UI (`HotkeyRecorder`)

A `NSViewRepresentable` wrapping an `NSView` that:
1. On focus: starts capturing key events (suppress normal SwiftUI handling)
2. On any key-down: records `keyCode` + `modifierFlags`, updates display
3. On Escape: cancels recording
4. On blur / Enter: confirms and saves to `AppSettings`

Display conflict warning if the combination is in a known list of system shortcuts (e.g., `⌘ Space`, `⌃ Space`, `⌘ Tab`, `⌘ Q`).

---

## 5. AXUIElement Text Access

### 5.1 Permission Check

```swift
func isAccessibilityGranted() -> Bool {
    AXIsProcessTrustedWithOptions(
        [kAXTrustedCheckOptionPrompt: false] as CFDictionary
    )
}
```

To prompt with system dialog:
```swift
AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)
```

### 5.2 Read Focused Element

```swift
let systemWide = AXUIElementCreateSystemWide()
var focusedApp: CFTypeRef?
AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)

var focusedElement: CFTypeRef?
AXUIElementCopyAttributeValue(focusedApp as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
```

### 5.3 Read Value and Selection

```swift
// Full text value
var value: CFTypeRef?
AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
let text = value as? String

// Selected range (AXTextRange)
var selectedRange: CFTypeRef?
AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange)
// Unpack via AXValueGetValue with kAXValueCFRangeType → CFRange
```

### 5.4 Write Strategies

**Strategy A — Set AXValue directly (preferred):**
```swift
AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newFullText as CFTypeRef)
// Then restore caret position via kAXSelectedTextRangeAttribute
```

**Strategy B — Clipboard fallback:**
1. Save current clipboard contents (all UTTypes on the pasteboard)
2. Write converted text to `NSPasteboard.general`
3. Simulate `⌘V` via `CGEvent`
4. After a short delay (~100 ms), restore original clipboard contents

> **Important:** Strategy A modifies the entire field value and moves the caret. After writing, restore caret position by setting `kAXSelectedTextRangeAttribute` to the new range covering the replaced text.

### 5.5 Word Extraction (no selection)

1. Read full `kAXValueAttribute` string
2. Read caret position from `kAXSelectedTextRangeAttribute` (when selection length == 0, location = caret)
3. Scan leftward from caret for first space/tab/newline delimiter
4. Extract substring → this is the last word
5. After conversion: replace that substring in the full text, write back, set caret to end of replacement

---

## 6. Layout Conversion Engine

### 6.1 QWERTY ↔ RU Mapping Table

Physical key position mapping (standard QWERTY keyboard):

```swift
// LayoutMapping.swift
enum LayoutMapping {
    static let qwertyToRu: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е",
        "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ъ",
        "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п",
        "h": "р", "j": "о", "k": "л", "l": "д", ";": "ж",
        "'": "э",
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и",
        "n": "т", "m": "ь", ",": "б", ".": "ю", "/": ".",
        // Uppercase
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е",
        "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ъ",
        "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П",
        "H": "Р", "J": "О", "K": "Л", "L": "Д", ":": "Ж",
        "\"": "Э",
        "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И",
        "N": "Т", "M": "Ь", "<": "Б", ">": "Ю", "?": ",",
    ]

    static let ruToQwerty: [Character: Character] = {
        Dictionary(uniqueKeysWithValues: qwertyToRu.map { ($0.value, $0.key) })
    }()
}
```

### 6.2 Direction Detection

```swift
// DirectionDetector.swift
enum ConversionDirection {
    case enToRu  // Latin → Cyrillic
    case ruToEn  // Cyrillic → Latin
}

func detectDirection(_ text: String) -> ConversionDirection? {
    var latinCount = 0
    var cyrillicCount = 0
    for scalar in text.unicodeScalars {
        if scalar.value >= 0x0041 && scalar.value <= 0x007A { latinCount += 1 }
        if scalar.value >= 0x0400 && scalar.value <= 0x04FF { cyrillicCount += 1 }
    }
    if latinCount == 0 && cyrillicCount == 0 { return nil }
    return latinCount >= cyrillicCount ? .enToRu : .ruToEn
}
```

> Mixed-script input: direction follows the dominant script. Unmapped characters pass through unchanged.

### 6.3 Converter

```swift
// LayoutConverter.swift
func convert(_ text: String, direction: ConversionDirection) -> String {
    let map = direction == .enToRu ? LayoutMapping.qwertyToRu : LayoutMapping.ruToQwerty
    return String(text.map { map[$0] ?? $0 })
}
```

---

## 7. Clipboard Fallback

Used when AXValue write fails (Strategy B).

```swift
// ClipboardManager.swift
class ClipboardManager {
    // Save all items+types from NSPasteboard.general
    func saveClipboard() -> [[NSPasteboard.PasteboardType: Data]] { ... }

    // Set plain string
    func setString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    // Simulate Cmd+V
    func paste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    // Restore saved clipboard after delay
    func restoreClipboard(_ saved: [[NSPasteboard.PasteboardType: Data]]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            NSPasteboard.general.clearContents()
            // re-write each item/type pair
        }
    }
}
```

**Timing:** wait ~80–100 ms after posting `Cmd+V` before restoring clipboard to ensure the target app has processed the paste event.

**Rich clipboard:** save all UTTypes (RTF, HTML, plain, etc.) and restore them all to avoid clobbering the user's clipboard.

---

## 8. Menubar App Architecture

### 8.1 NSStatusItem

```swift
// MenubarManager.swift
class MenubarManager {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(settings: AppSettings, orchestrator: FixOrchestrator) {
        statusItem.button?.image = NSImage(named: "MenubarIcon")
        statusItem.menu = buildMenu(settings: settings, orchestrator: orchestrator)
    }
}
```

### 8.2 NSMenu Structure

```
✓ Enable LayoutFixer         (checkmark toggle, action: toggleEnabled)
─────────────────────────────
  Settings…                  (action: openSettings)
  Accessibility Permissions  (action: openAccessibilitySettings)
─────────────────────────────
  About LayoutFixer
  Quit LayoutFixer
```

### 8.3 Settings Window

Opened via `NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)` or via SwiftUI `openWindow` environment action targeting the `Settings` scene.

```swift
// SettingsView.swift
struct SettingsView: View {
    @Environment(AppSettings.self) var settings

    var body: some View {
        Form {
            Section("Hotkey") {
                HotkeyRecorder(hotkey: $settings.hotkey)
            }
            Section("Sound") {
                Picker("Sound", selection: $settings.soundName) { ... }
                Slider(value: $settings.soundVolume, in: 0...1)
                Toggle("Enable sound", isOn: $settings.soundEnabled)
            }
            Section("General") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, new in
                        LoginItemManager.shared.setEnabled(new)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }
}
```

### 8.4 Icon Animation (`StatusIconAnimator`)

On successful conversion:
1. Determine result language (RU or EN)
2. Swap `statusItem.button?.image` to the corresponding flag image
3. After 1.5 s, restore original icon

```swift
func animateSuccess(resultLanguage: ConversionDirection) {
    let flagImage = resultLanguage == .enToRu ? NSImage(named: "flag_ru") : NSImage(named: "flag_en")
    statusItem.button?.image = flagImage
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        self?.statusItem.button?.image = NSImage(named: "MenubarIcon")
    }
}
```

---

## 9. Settings Persistence

### 9.1 `AppSettings` — `@Observable` + `@AppStorage`

On macOS 14+ `@Observable` fully supports `@AppStorage` — no `@ObservationIgnored` workaround needed.

```swift
// AppSettings.swift
@Observable
final class AppSettings {
    @AppStorage("hotkey")         var hotkeyData: Data = HotkeyDefinition.default.encoded()
    @AppStorage("soundName")      var soundName: String = "Tink"
    @AppStorage("soundVolume")    var soundVolume: Double = 0.7
    @AppStorage("soundEnabled")   var soundEnabled: Bool = true
    @AppStorage("launchAtLogin")  var launchAtLogin: Bool = true
    @AppStorage("isEnabled")      var isEnabled: Bool = true

    var hotkey: HotkeyDefinition {
        get { HotkeyDefinition.decode(from: hotkeyData) ?? .default }
        set { hotkeyData = newValue.encoded() }
    }
}
```

### 9.2 First-Launch Defaults

`@AppStorage` uses the `defaultValue` parameter as the initial value — no explicit "first launch" check needed. `launchAtLogin: Bool = true` means the SMAppService registration fires on first `didSet`.

---

## 10. Audio Feedback

```swift
// SoundPlayer.swift
class SoundPlayer {
    // Curated list of NSSound names available on macOS 14
    static let availableSounds = ["Tink", "Pop", "Morse", "Funk", "Bottle"]

    func play(name: String, volume: Double) {
        guard let sound = NSSound(named: name) else { return }
        sound.volume = Float(volume)
        sound.play()
    }
}
```

**Volume:** `NSSound.volume` is `Float` in `0.0...1.0`. Map from settings slider directly.

**Mute:** check `AppSettings.soundEnabled` before calling `play()`.

---

## 11. Launch at Login

`SMAppService` (available since macOS 13.0) manages login items without a separate helper app.

```swift
// LoginItemManager.swift
import ServiceManagement

class LoginItemManager {
    static let shared = LoginItemManager()

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Log error; UI shows current status via SMAppService.mainApp.status
        }
    }

    var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
```

---

## 12. Testing Strategy

### 12.1 Unit Tests

| Module | What to test |
|---|---|
| `LayoutMapping` | All 66 EN→RU character mappings; inverse RU→EN; round-trip |
| `DirectionDetector` | Pure Latin → `.enToRu`; pure Cyrillic → `.ruToEn`; mixed (dominant wins); empty → `nil` |
| `LayoutConverter` | Known conversions: `"ghbdtn"` → `"привет"`, `"руддщ"` → `"hello"`; passthrough for unmapped chars |
| `WordExtractor` | Word left of caret at various positions; no word → empty; delimiter variants |
| `HotkeyDefinition` | Codable round-trip; `displayString` formatting |

### 12.2 Manual Test Checklist

- [ ] Fix last word in **TextEdit** (native NSTextView)
- [ ] Fix last word in **Safari** address bar
- [ ] Fix last word in **VS Code** (Electron — clipboard fallback path)
- [ ] Fix selected text in **Telegram**
- [ ] Fix selected text spanning multiple words
- [ ] No-op when caret at start of line
- [ ] No-op when field is unreadable (verify silence: no sound, no icon change)
- [ ] Accessibility prompt appears on first hotkey press without permission
- [ ] Clipboard is preserved after clipboard-fallback path
- [ ] Icon swaps to flag and restores after 1.5 s
- [ ] Sound plays at configured volume; muted when disabled
- [ ] Launch at Login toggle registers / unregisters correctly
- [ ] Settings persist across app restart
- [ ] Hotkey recorder captures and displays combinations correctly
- [ ] Enable/Disable toggle suspends hotkey interception

---

## 13. Implementation Order

### Phase 1 — Project Skeleton
- Create Xcode project (macOS 14, no sandbox, `LSUIElement`)
- Add folder structure and empty Swift files
- Wire `@main` → `AppDelegate` / `MenubarManager`
- Verify: app launches as menubar icon, no Dock icon

### Phase 2 — Settings Model
- Implement `AppSettings` with `@Observable` + `@AppStorage`
- Implement `HotkeyDefinition` (Codable, displayString)
- Verify: defaults persist across launches

### Phase 3 — Layout Conversion Engine
- Implement `LayoutMapping`, `DirectionDetector`, `LayoutConverter`
- Write unit tests (all pass before moving on)

### Phase 4 — Hotkey System
- Implement `HotkeyManager` with CGEventTap
- Hardcode default hotkey (`⌥ Space`) for now
- Verify: hotkey fires callback; other apps still receive non-matching keys

### Phase 5 — AXUIElement Read
- Implement `AXPermissionManager` (check + prompt)
- Implement `AXTextReader` (focused element, value, selection, word extraction)
- Test in TextEdit and Safari

### Phase 6 — AXUIElement Write + Clipboard Fallback
- Implement `AXTextWriter` (Strategy A)
- Implement `ClipboardManager` (Strategy B)
- Test in TextEdit (Strategy A) and VS Code (Strategy B)

### Phase 7 — Orchestrator
- Wire all modules in `FixOrchestrator`
- Implement full pipeline end-to-end
- Manual test on all target apps

### Phase 8 — UI & Feedback
- Build `SettingsView` with all controls
- Implement `SoundPlayer` with curated sound list
- Implement `StatusIconAnimator`
- Implement `MenubarManager` with full menu

### Phase 9 — Hotkey Recorder + Conflict Detection
- Implement `HotkeyRecorder` SwiftUI view
- Wire to `AppSettings.hotkey`
- Add conflict warning logic

### Phase 10 — Launch at Login + Polish
- Implement `LoginItemManager`
- First-launch defaults (auto-register)
- Icon assets (app icon + flag images)
- Code review, fix TODOs
- Test entire manual checklist

---

## 14. Known Pitfalls & Mitigations

| # | Pitfall | Mitigation |
|---|---|---|
| 1 | **CGEventTap requires Accessibility permission** — tap silently fails if not granted | Always check `AXIsProcessTrustedWithOptions` before installing tap; re-install tap after permission granted |
| 2 | **CGEventTap can be disabled by the system** on hang | Install a `RunLoop`-based watchdog that checks `CGEvent.tapIsEnabled` and re-enables if needed |
| 3 | **AXValue write fails on Electron/CEF apps** | Detect `kAXErrorCannotComplete` / `kAXErrorNotImplemented`; fall through to clipboard strategy |
| 4 | **Clipboard restore race condition** — target app hasn't finished pasting when we restore | Wait ≥ 100 ms before restoring; use `DispatchQueue.main.asyncAfter` |
| 5 | **Rich clipboard destruction** — user had formatted text, we overwrite with plain string | Save all UTType entries from `NSPasteboard.general` and restore all of them |
| 6 | **Word extraction wrong in right-to-left or emoji text** | v1 scope is EN↔RU only; add a guard that aborts if text contains non-Latin/non-Cyrillic dominant scripts |
| 7 | **Settings window appears behind other windows** | Call `NSApp.activate(ignoringOtherApps: true)` before showing settings |
| 8 | **Hotkey conflicts with in-app shortcuts** of the frontmost app | Active CGEventTap at `headInsertEventTap` consumes the event before the app sees it; document this trade-off |
| 9 | **AX attribute `kAXSelectedTextRangeAttribute` absent in some fields** | Fall back to reading full value and scanning for word using `kAXValueAttribute` only |
| 10 | **Caret position after AXValue write** — writing full value resets caret to end | After writing, set `kAXSelectedTextRangeAttribute` to the new range (start of replaced word + converted length) |
| 11 | **`SMAppService` registration fails silently** | Check `SMAppService.mainApp.status` and surface error in Settings UI |
| 12 | **App not notarized** — Gatekeeper blocks launch on first run | Set up GitHub Actions with `xcrun notarytool` + staple step for releases |
