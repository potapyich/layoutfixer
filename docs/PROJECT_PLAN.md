# Project: LayoutFixer_CC

## Overview
LayoutFixer_CC — это macOS menubar utility, которая исправляет текст, набранный в неправильной клавиатурной раскладке, по глобальному хоткею. Приложение работает как background process (без иконки в Dock), поддерживает исправление последнего слова и выделенного текста через AXUIElement Accessibility API. Стек: Swift 5.10, SwiftUI, `@Observable`, CGEventTap, AXUIElement. Минимальная версия macOS: 14.0 Sonoma.

## Success Criteria
- [ ] All tasks complete
- [ ] All unit tests pass (LayoutMapping, DirectionDetector, LayoutConverter, WordExtractor, HotkeyDefinition)
- [ ] Build succeeds on macOS 14.0+ without sandbox
- [ ] No linting errors
- [ ] Manual test checklist from `docs/PRD.md §18` полностью пройден
- [ ] EXIT_SIGNAL: true

---

## Tasks

### Task 1: Project Skeleton
**Priority:** 1
**Description:**
Создать Xcode-проект с нуля и настроить всю инфраструктуру перед написанием бизнес-логики.

Конкретные шаги:
- Создать macOS App project: Product Name `LayoutFixer`, Bundle ID `com.yourname.LayoutFixer`, Deployment Target `14.0`, без SwiftData, без CoreData
- Отключить App Sandbox в `.entitlements` (`com.apple.security.app-sandbox = false`)
- Добавить `LSUIElement = true` в `Info.plist` (скрыть иконку из Dock)
- Добавить `NSAccessibilityUsageDescription` в `Info.plist`
- Создать структуру папок согласно `IMPLEMENTATION_PLAN.md §2`: `App/`, `Orchestration/`, `Hotkey/`, `Accessibility/`, `Conversion/`, `Clipboard/`, `Menubar/`, `Settings/`, `Audio/`, `Login/`, `Resources/`
- Создать пустые Swift-файлы с именами из плана (stub с `// TODO`)
- Настроить `@main` в `LayoutFixerApp.swift`: только `Settings { SettingsView() }` scene, без `WindowGroup`
- Подключить `NSApplicationDelegateAdaptor` к `AppDelegate`
- Добавить `LayoutFixerTests` target для unit-тестов

**Acceptance Criteria:**
- Проект собирается без ошибок и предупреждений
- Приложение запускается: иконки в Dock нет, иконки в menubar нет (пока не реализован `MenubarManager`)
- `LSUIElement` и entitlements проверяются в Xcode → Target → Info / Signing & Capabilities
- Все папки и пустые файлы присутствуют в navigator

**Test:**
1. `Cmd+B` — сборка без ошибок
2. `Cmd+R` — запуск; открыть Dock — иконки приложения нет
3. Проверить `Info.plist`: ключ `LSUIElement` = YES
4. Проверить `.entitlements`: `com.apple.security.app-sandbox` = NO

---

### Task 2: Settings Model
**Priority:** 2
**Description:**
Реализовать модель настроек `AppSettings` и тип `HotkeyDefinition` — они используются во всех остальных модулях, поэтому должны быть готовы вторыми.

`AppSettings` (`Settings/AppSettings.swift`):
- Аннотация `@Observable`
- Свойства с `@AppStorage`:
  - `hotkeyData: Data` — сериализованный `HotkeyDefinition`, default = `HotkeyDefinition.default.encoded()`
  - `soundName: String` — default `"Tink"`
  - `soundVolume: Double` — default `0.7`
  - `soundEnabled: Bool` — default `true`
  - `launchAtLogin: Bool` — default `true`
  - `isEnabled: Bool` — default `true`
- Вычисляемое свойство `hotkey: HotkeyDefinition` с get/set через `hotkeyData`

`HotkeyDefinition` (`Hotkey/HotkeyDefinition.swift`):
- `struct HotkeyDefinition: Codable, Equatable`
- Поля: `keyCode: UInt16`, `modifierFlags: UInt64`
- `static let default` = `⌥ Space` (keyCode 49, modifierFlags `.maskAlternate`)
- `var displayString: String` — форматирует в human-readable (`⌥`, `⌃`, `⌘`, `⇧` + название клавиши)
- `func encoded() -> Data` и `static func decode(from:) -> HotkeyDefinition?`

**Acceptance Criteria:**
- `AppSettings` инициализируется без ошибок и доступна как `@Environment` в SwiftUI
- Значения сохраняются в `UserDefaults` и переживают перезапуск приложения
- `HotkeyDefinition` корректно кодируется и декодируется через `JSONEncoder/JSONDecoder`
- `displayString` для default hotkey возвращает `"⌥ Space"`

**Test:**
1. Unit test: `HotkeyDefinition.default.encoded()` → `HotkeyDefinition.decode(from:)` возвращает исходный объект
2. Unit test: `displayString` для нескольких комбинаций возвращает ожидаемые строки
3. Запустить приложение, изменить `soundVolume` программно → перезапустить → значение сохранилось
4. Убедиться, что нет `@ObservationIgnored` (не нужен на macOS 14+)

---

### Task 3: Layout Conversion Engine
**Priority:** 3
**Description:**
Реализовать три файла конверсии — самая тестируемая часть приложения. Никаких зависимостей от системных API, только чистая логика.

`LayoutMapping` (`Conversion/LayoutMapping.swift`):
- `enum LayoutMapping` (namespace)
- `static let qwertyToRu: [Character: Character]` — полная таблица из `IMPLEMENTATION_PLAN.md §6.1` (строчные + прописные, 66+ пар)
- `static let ruToQwerty: [Character: Character]` — автоматически инвертированная через `Dictionary(uniqueKeysWithValues:)`

`DirectionDetector` (`Conversion/DirectionDetector.swift`):
- `enum ConversionDirection { case enToRu, case ruToEn }`
- `func detectDirection(_ text: String) -> ConversionDirection?`
- Логика: считать Latin (U+0041–U+007A) и Cyrillic (U+0400–U+04FF) символы; вернуть `nil` если оба 0; direction по большинству; при равенстве — `.enToRu`

`LayoutConverter` (`Conversion/LayoutConverter.swift`):
- `func convert(_ text: String, direction: ConversionDirection) -> String`
- Маппинг через словарь, немаппированные символы — passthrough (`map[$0] ?? $0`)

**Acceptance Criteria:**
- `convert("ghbdtn", direction: .enToRu)` == `"привет"`
- `convert("руддщ", direction: .ruToEn)` == `"hello"`
- `convert("hello тест", direction: .enToRu)` — кириллица passthrough, латиница конвертируется
- `detectDirection("ghbdtn")` == `.enToRu`
- `detectDirection("привет")` == `.ruToEn`
- `detectDirection("")` == `nil`
- `detectDirection("123 !@#")` == `nil`
- Все unit-тесты проходят

**Test:**
1. Unit test: все 66+ пар из `qwertyToRu` — прямое и обратное направление
2. Unit test: round-trip — `convert(convert(word, .enToRu), .ruToEn)` == исходное слово (для всех маппированных символов)
3. Unit test: `convert("тест,", .ruToEn)` == `"ntcn,"` — запятая pass-through
4. Unit test: смешанный текст, пустая строка, строка только из пробелов
5. Unit test: Cases из PRD §18.1 — `"тест"` → `"ntcn"` (RU→EN)

---

### Task 4: Hotkey System
**Priority:** 4
**Description:**
Реализовать глобальный перехват хоткея через `CGEventTap`.

`HotkeyManager` (`Hotkey/HotkeyManager.swift`):
- Класс, создаёт `CGEventTap` при инициализации
- Tap: `cgSessionEventTap`, `headInsertEventTap`, `.defaultTap` (active — поглощает событие)
- `eventsOfInterest`: только `keyDown`
- В callback: сравнить `keyCode` и `flags` события с `AppSettings.hotkey`; если совпадение — вернуть `nil` (потребить событие) и вызвать `onTrigger` closure на main actor
- Методы `enable()` и `disable()` — добавить/удалить tap из `RunLoop`
- Watchdog: переиспользовать `RunLoop` source, проверять `CGEvent.tapIsEnabled` — при инвалидации пересоздавать tap
- Реагировать на изменение `AppSettings.isEnabled` — включать/отключать tap
- Реагировать на изменение `AppSettings.hotkey` — пересоздавать tap с новым фильтром

Требования v1:
- Поддерживаются только комбинации `modifier + key` (не одиночный модификатор)
- Default hotkey: `⌥ Space`

**Acceptance Criteria:**
- При нажатии `⌥ Space` вызывается `onTrigger`; событие не доходит до frontmost app
- При нажатии других клавиш — приложения получают их без изменений
- `disable()` — хоткей перестаёт работать; `enable()` — возобновляется
- Если `AXIsProcessTrustedWithOptions` возвращает `false` — tap не создаётся (CGEventTap требует AX)

**Test:**
1. Запустить приложение → нажать `⌥ Space` в TextEdit → убедиться, что пробел не вставился (событие поглощено)
2. Нажать `⌥ A` — символ вставился нормально (не совпадает с hotkey)
3. Через меню "Disable" → нажать `⌥ Space` → пробел вставился нормально
4. Снова "Enable" → `⌥ Space` снова перехватывается
5. Сменить hotkey на `⌃ Q` → убедиться, что `⌥ Space` больше не перехватывается, а `⌃ Q` — перехватывается

---

### Task 5: Accessibility — Read
**Priority:** 5
**Description:**
Реализовать чтение текста из сфокусированного элемента через AXUIElement.

`AXPermissionManager` (`Accessibility/AXPermissionManager.swift`):
- `func isGranted() -> Bool` — `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: false])`
- `func promptIfNeeded()` — `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`; вызывать только на первом нажатии хоткея без разрешения

`AXTextReader` (`Accessibility/AXTextReader.swift`):
- `func focusedElement() -> AXUIElement?` — через `kAXFocusedApplicationAttribute` → `kAXFocusedUIElementAttribute`
- `func fullText(of element: AXUIElement) -> String?` — `kAXValueAttribute`
- `func selectionRange(of element: AXUIElement) -> CFRange?` — `kAXSelectedTextRangeAttribute`, unpack через `AXValueGetValue` с `kAXValueCFRangeType`
- `func selectedText(of element: AXUIElement) -> String?` — `kAXSelectedTextAttribute`
- `func lastWord(of element: AXUIElement) -> (text: String, range: CFRange)?`:
  1. Получить `fullText`
  2. Получить `selectionRange` (caret = location когда length == 0)
  3. Сканировать влево от caret до первого пробела/таба/newline
  4. Вернуть подстроку и её range в исходном тексте
  5. Если caret в начале строки или текст пуст — вернуть `nil`

Edge cases в `lastWord`:
- Текст `"hello world|"` → `("world", range)`
- Текст `"тест\nтест|"` → `("тест", range)` — newline является разделителем
- Текст `"тест,|"` → `("тест,", range)` — запятая входит в слово (v1: только space/tab/newline разделители)
- Текст `"|"` (caret в начале) → `nil`

**Acceptance Criteria:**
- В TextEdit: `focusedElement()` возвращает non-nil при сфокусированном поле
- `fullText` возвращает полный текст поля
- `selectionRange` корректно указывает позицию каретки
- `lastWord` корректно извлекает последнее слово по всем edge cases из PRD §18
- Если элемент не поддерживает AX-атрибуты — возвращается `nil` (не crash)

**Test:**
1. TextEdit: напечатать `"hello world"` → вызвать `lastWord` программно → результат `"world"`
2. TextEdit: выделить `"world"` → вызвать `selectionRange` → length > 0
3. TextEdit: поставить каретку в начало → `lastWord` → `nil`
4. TextEdit: `"тест\nтест"` с кареткой после второго `"тест"` → `lastWord` → `"тест"` (второе)
5. VS Code (Electron): `focusedElement()` может вернуть `nil` — проверить, что нет crash

---

### Task 6: Accessibility — Write + Clipboard Fallback
**Priority:** 6
**Description:**
Реализовать запись сконвертированного текста обратно в поле — два метода: прямой через AX и fallback через clipboard.

`AXTextWriter` (`Accessibility/AXTextWriter.swift`):
- `func write(convertedText: String, replacing range: CFRange, in element: AXUIElement) -> Bool`:
  1. Сформировать новую полную строку: заменить `range` в `fullText` на `convertedText`
  2. `AXUIElementSetAttributeValue(element, kAXValueAttribute, newFullText)`
  3. Если вернул ошибку `kAXErrorCannotComplete` или `kAXErrorNotImplemented` — вернуть `false`
  4. Если успех — восстановить позицию каретки: установить `kAXSelectedTextRangeAttribute` в `CFRange(location: range.location + convertedText.utf16.count, length: 0)`
  5. Вернуть `true`

`ClipboardManager` (`Clipboard/ClipboardManager.swift`):
- `func saveClipboard() -> [[NSPasteboard.PasteboardType: Data]]` — сохранить все items и все UTTypes
- `func setString(_ string: String)` — `clearContents()` + `setString(_:forType:.string)`
- `func paste()` — симулировать `Cmd+V` через `CGEvent` (keyCode 0x09, flags `.maskCommand`), posted to `.cgAnnotatedSessionEventTap`
- `func restoreClipboard(_ saved:)` — через `asyncAfter(deadline: .now() + 0.15)` восстановить все сохранённые items
- `func writeAndPaste(text: String)` — saveClipboard → setString → paste → asyncAfter restoreClipboard

Важно: не удалять trailing newlines при сохранении clipboard; удалять trailing newlines только из конвертируемого текста (PRD §18.4).

**Acceptance Criteria:**
- TextEdit: `AXTextWriter.write` успешно заменяет слово без изменения clipboard
- VS Code: `AXTextWriter.write` возвращает `false` → `ClipboardManager.writeAndPaste` выполняется
- После clipboard fallback в обоих случаях clipboard восстанавливается до исходного значения (PRD §18.3)
- Каретка после замены находится сразу после вставленного текста (PRD §18.7)
- Дублирования текста нет (PRD §18.8)

**Test:**
1. TextEdit: `"тест|"` → конвертировать → результат `"ntcn|"`, clipboard не изменён
2. TextEdit: скопировать `"ABC"` → конвертировать слово → clipboard после = `"ABC"`
3. VS Code: `"ghbdtn|"` → конвертировать → результат `"привет|"` (clipboard fallback)
4. VS Code: clipboard `"ABC"` → конвертировать → clipboard после = `"ABC"`
5. Проверить PRD §18.8: после конвертации нет дублирования `"ntcnтест"`
6. Проверить PRD §18.4: trailing newline в скопированном тексте удаляется перед конвертацией

---

### Task 7: Fix Orchestrator
**Priority:** 7
**Description:**
Собрать все модули в единый pipeline, который вызывается при нажатии хоткея.

`FixOrchestrator` (`Orchestration/FixOrchestrator.swift`):
- `@MainActor class FixOrchestrator`
- Зависимости через init: `AXPermissionManager`, `AXTextReader`, `AXTextWriter`, `ClipboardManager`, `LayoutConverter`, `DirectionDetector`, `SoundPlayer`, `StatusIconAnimator`
- Метод `trigger()` — полный pipeline:
  1. Проверить `AXPermissionManager.isGranted()` → если нет: `promptIfNeeded()` (только первый раз), silent no-op (без звука и анимации)
  2. `AXTextReader.focusedElement()` → если nil: silent no-op
  3. `AXTextReader.selectionRange(of:)` → если length > 0: `selectedText(of:)` + сохранить range
  4. Если length == 0: `lastWord(of:)` → если nil: silent no-op
  5. `DirectionDetector.detectDirection(text)` → если nil: silent no-op
  6. `LayoutConverter.convert(text, direction:)` → получить `convertedText`
  7. Нормализация: удалить trailing newlines из `convertedText` (PRD §18.4)
  8. `AXTextWriter.write(convertedText, replacing: range, in: element)` → если false: `ClipboardManager.writeAndPaste(text: convertedText)`
  9. `SoundPlayer.play(...)` если `AppSettings.soundEnabled`
  10. `StatusIconAnimator.animateSuccess(resultLanguage: direction)`

- `var isFirstPermissionDenial = true` — флаг для prompt только при первом отказе

**Acceptance Criteria:**
- Полный end-to-end: нажать `⌥ Space` в TextEdit с текстом `"ghbdtn"` → результат `"привет"`, звук играет, иконка меняется
- Полный end-to-end: нажать `⌥ Space` в VS Code → конвертация через clipboard, всё работает
- Silent no-op: без AX permission — ни звука, ни анимации, ни изменения clipboard
- Silent no-op: в несовместимом поле (unreadable element) — ни звука, ни анимации
- PRD §18 — все 9 behavioral test cases проходят

**Test:**
1. Все тест-кейсы из PRD §18.1–§18.9 вручную
2. TextEdit — все 4 сценария: single word, two words, newline boundary, punctuation safety
3. VS Code — selected text, last word
4. Telegram — selected text
5. Safari address bar — last word
6. Без AX permission: нажать хоткей → ничего не происходит, появляется системный диалог (только первый раз)

---

### Task 8: Menubar & Settings UI
**Priority:** 8
**Description:**
Реализовать весь UI приложения: иконку в menubar, выпадающее меню и окно настроек.

`MenubarManager` (`Menubar/MenubarManager.swift`):
- Создать `NSStatusItem` с `squareLength`
- Установить иконку `MenubarIcon` из `Assets.xcassets`
- Построить `NSMenu` со структурой:
  ```
  ✓ Enable LayoutFixer   (toggle isEnabled, checkmark отражает состояние)
  ─────────────────────
    Settings…            (открыть окно настроек)
    Accessibility Permissions  (открыть System Settings → Accessibility)
  ─────────────────────
    About LayoutFixer
    Quit LayoutFixer
  ```
- `NSMenuDelegate` — обновлять checkmark перед показом меню по текущему `AppSettings.isEnabled`
- "Settings…" — `NSApp.activate(ignoringOtherApps: true)` + открыть SwiftUI Settings window
- "Accessibility Permissions" — `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`

`StatusIconAnimator` (`Menubar/StatusIconAnimator.swift`):
- `func animateSuccess(resultLanguage: ConversionDirection)` — заменить иконку на `flag_ru` или `flag_en`, через 1.5 с вернуть `MenubarIcon`
- Если анимация уже идёт — отменить предыдущую задачу и начать новую

`SettingsView` (`Settings/SettingsView.swift`):
- SwiftUI Form с `.formStyle(.grouped)`, ширина 400 pt
- **Section "Hotkey"**: `HotkeyRecorder` (stub на этом этапе, реализуется в Task 9)
- **Section "Sound"**: `Picker` с 5 звуками `["Tink", "Pop", "Morse", "Funk", "Bottle"]`, `Slider` громкости 0–1, `Toggle` включения звука; кнопка Preview для прослушивания
- **Section "General"**: `Toggle` Launch at Login (с `onChange` → `LoginItemManager`)
- **Section "Language"**: text label `"RU ↔ EN"` (read-only в v1)

Assets (`Resources/Assets.xcassets`):
- `MenubarIcon` — монохромный шаблонный символ (template image) для адаптации к dark/light menubar
- `flag_ru` — флаг России (16×16 или SF Symbol `flag` с цветом)
- `flag_en` — флаг UK или US (16×16)
- App icon — все необходимые размеры (16, 32, 64, 128, 256, 512, 1024)

**Acceptance Criteria:**
- Иконка видна в menubar
- Меню открывается при клике, все пункты работают
- Checkmark у "Enable LayoutFixer" отражает реальное состояние
- Settings открываются поверх других окон (`NSApp.activate`)
- Sound preview играет выбранный звук
- Иконка меняется на флаг после конвертации и возвращается через 1.5 с
- В тёмной и светлой темах menubar иконка отображается корректно (template image)

**Test:**
1. Кликнуть иконку → меню открылось с правильными пунктами
2. Toggle "Enable" → checkmark меняется; хоткей перестаёт/начинает работать
3. "Settings…" → окно открывается поверх других окон
4. "Accessibility Permissions" → открывается нужный раздел System Settings
5. В Settings: выбрать звук "Funk" → нажать Preview → "Funk" играет
6. Конвертировать слово → иконка сменилась на флаг → через 1.5 с вернулась
7. System Preferences → Appearance: тёмная тема → иконка menubar выглядит корректно

---

### Task 9: Hotkey Recorder
**Priority:** 9
**Description:**
Реализовать UI-компонент для записи пользовательского хоткея прямо в поле настроек.

`HotkeyRecorder` (`Hotkey/HotkeyRecorder.swift`):
- `NSViewRepresentable`, оборачивает кастомный `NSView`
- Состояния: `.idle` (отображает текущий hotkey), `.recording` (мигающий курсор, "Press shortcut…")
- Переход в `.recording` по клику или фокусу
- В `.recording`: перехватывать `keyDown` events до того как они попадут в SwiftUI
  - `Escape` → отмена, вернуться в `.idle` без изменений
  - `Delete/Backspace` → сбросить hotkey к default
  - Любая комбинация с modifier → записать как новый `HotkeyDefinition`, подтвердить
  - Одиночный modifier без key → игнорировать (требуем modifier+key)
- Отображение: использовать SF Symbols или Unicode symbols `⌥ ⌃ ⌘ ⇧` + название key
- Подтверждение (blur / Enter) → вызвать `AppSettings.hotkey = newDefinition`

Conflict detection:
- Список системных shortcuts: `⌘ Space`, `⌃ Space`, `⌘ Tab`, `⌘ Q`, `⌘ W`, `⌘ H`, `⌘ M`
- При совпадении → показать `Text("⚠️ Conflicts with a system shortcut")` рядом с recorder

**Acceptance Criteria:**
- Кликнуть на поле → переходит в режим записи
- Нажать `⌥ Q` → поле показывает `"⌥ Q"`, hotkey обновляется в `AppSettings`
- Нажать `Escape` → отмена, старый hotkey сохранён
- Нажать `⌘ Space` → появляется предупреждение о конфликте
- После смены hotkey: новый хоткей начинает работать немедленно (HotkeyManager наблюдает за `AppSettings.hotkey`)
- Перезапустить приложение → записанный hotkey сохранился

**Test:**
1. Settings → Hotkey → кликнуть → поле в режиме записи (другой вид)
2. Нажать `⌥ Q` → отображается `"⌥ Q"`, нажать `⌥ Q` в TextEdit → конвертация работает
3. Нажать `⌘ Space` → видно предупреждение о конфликте
4. Нажать `Escape` → hotkey не изменился
5. Перезапустить → hotkey `"⌥ Q"` сохранился
6. Нажать `Delete` в recorder → hotkey сброшен к `"⌥ Space"`

---

### Task 10: Launch at Login + Sound Player + Final Polish
**Priority:** 10
**Description:**
Завершить оставшиеся модули, провести финальный polish и запустить полный manual test checklist.

`LoginItemManager` (`Login/LoginItemManager.swift`):
- `import ServiceManagement`
- `static let shared = LoginItemManager()`
- `func setEnabled(_ enabled: Bool)` — `try SMAppService.mainApp.register()` / `unregister()`
- `var isRegistered: Bool` — `SMAppService.mainApp.status == .enabled`
- При старте приложения: если `AppSettings.launchAtLogin == true` и `!isRegistered` → вызвать `setEnabled(true)` (first-launch auto-register)
- Ошибку регистрации логировать; в SettingsView показывать актуальный статус из `SMAppService.mainApp.status`

`SoundPlayer` (`Audio/SoundPlayer.swift`):
- `static let availableSounds: [String] = ["Tink", "Pop", "Morse", "Funk", "Bottle"]`
- `func play(name: String, volume: Double)` — `NSSound(named:)?.volume = Float(volume)` → `.play()`
- Не играть если `AppSettings.soundEnabled == false`
- При конкурентных вызовах (быстрые повторные нажатия) — остановить предыдущий звук

Final Polish:
- Убедиться что `NSApp.activate(ignoringOtherApps: true)` вызывается перед показом Settings
- Убедиться что при всех silent no-op НЕ играет звук и НЕ анимируется иконка
- Убедиться что `HotkeyManager` переустанавливает tap если он был инвалидирован системой
- Все `TODO` комментарии убраны или задокументированы как known issues
- Проверить поведение при быстрых повторных нажатиях хоткея (очередь/дебаунс)
- Добавить `os_log` или `print` для ключевых событий pipeline (debug только)

**Acceptance Criteria:**
- Toggle "Launch at Login" → приложение появляется/исчезает из Login Items в System Settings
- При установке (первый запуск) Launch at Login включён автоматически
- Sound player играет все 5 звуков на нужной громкости
- Mute toggle работает мгновенно
- Все пункты manual checklist из `IMPLEMENTATION_PLAN.md §12.2` и `PRD.md §18` пройдены
- Нет утечек памяти (`weak self` в closures)

**Test:**
1. Первый запуск → System Settings → General → Login Items → `LayoutFixer` присутствует
2. Settings → Launch at Login OFF → Login Items → `LayoutFixer` исчез
3. Settings → Sound → выбрать каждый из 5 звуков, нажать Preview → каждый играет
4. Sound toggle OFF → конвертировать → звука нет
5. Slider на 0.0 → конвертировать → звука нет (или очень тихо)
6. Быстро нажать хоткей 5 раз подряд → нет дублирования, нет зависания
7. Полный manual checklist из `IMPLEMENTATION_PLAN.md §12.2` — все пункты ✓

---

## Technical Constraints
- Language: Swift 5.10
- UI Framework: SwiftUI + `@Observable` (macOS 14+, без `@ObservationIgnored`)
- Minimum macOS: 14.0 Sonoma
- App Sandbox: **отключён** (v1, не для App Store)
- Hotkey: CGEventTap (`headInsertEventTap`, active tap)
- Text Access: AXUIElement Accessibility API
- Settings: `@AppStorage` + `UserDefaults`
- Launch at Login: `SMAppService` (ServiceManagement framework)
- No keyboard sniffing (важно для возможного App Store в v2)
- Distribution: GitHub open source release (notarization через GitHub Actions)

## Out of Scope
- App Sandbox (добавить в v2 для App Store)
- Modifier-only hotkeys (e.g., double-⌥) — только в v2
- System Input Sources mode (v2)
- Auto-switch keyboard layout after conversion (v2)
- Fix last token (полный фрагмент, не только слово) — v2
- Custom user-provided sound files — v2
- Dedicated onboarding window — v2
- Homebrew formula — v2
- Mac App Store submission — potential v2+
