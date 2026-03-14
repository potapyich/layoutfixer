# LayoutFixer — POST-MORTEM Implementation Plan (Retrospective)

> Ретроспективный план реализации. Написан постфактум.
> Показывает расхождения между тем, что было спланировано, и тем, что пришлось делать на практике.

---

## Что не совпало с планом

### §9.1 — `@ObservationIgnored` "не нужен на macOS 14+"

**Было написано:**
> На macOS 14+ `@Observable` fully supports `@AppStorage` — no `@ObservationIgnored` workaround needed.

**Что получилось:**
`@ObservationIgnored` **оказался нужен**. Без него `@AppStorage` внутри `@Observable` class вызывает runtime предупреждения и некорректное отслеживание зависимостей. Правильный паттерн:

```swift
@Observable
final class AppSettings {
    @ObservationIgnored
    @AppStorage("clipboardPollTimeoutMs") var clipboardPollTimeoutMs: Int = 100
}
```

**Урок:** Не пиши в плане что что-то "не нужно" без проверки на практике. Лучше написать "предположительно не нужно, проверить при реализации".

---

### §3.2 — Orchestrator: "silent no-op if unreadable"

**Было написано:**
> 2. Read focused AX element → silent no-op if unreadable

**Что получилось:**
Это предположение сломало поддержку Teams и части Electron-приложений. `focusedElement()` возвращает `nil` для Teams — не потому что нет текстового поля, а потому что Teams не реализует AX API для своего фокусированного элемента.

**Исправление:**
```swift
guard let element = axReader.focusedElement() else {
    logger.info("No focused element — trying clipboard fallback anyway")
    await keyboardFallback(pair: pair)
    return
}
```

**Урок:** "nil = ничего нельзя сделать" — неверное предположение для AX. nil element ≠ нет текстового поля.

---

### §6 — Clipboard Fallback: "restore after 150ms fixed delay"

**Было написано:**
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { ... }
```

**Что получилось:**
Fixed delay — ненадёжный механизм. На медленных машинах 150ms недостаточно; на быстрых — ждём лишнее время. Заменено на **polling**:

```swift
// Ждём изменения changeCount каждые 10ms до timeout
private func pollClipboard(ifChangedFrom before: Int) async -> String? {
    let pollNs: UInt64 = 10_000_000  // 10ms
    let maxTicks = max(1, settings.clipboardPollTimeoutMs / 10)
    for _ in 0..<maxTicks {
        if NSPasteboard.general.changeCount != before {
            return NSPasteboard.general.string(forType: .string)
        }
        try? await Task.sleep(nanoseconds: pollNs)
    }
    return nil
}
```

Типичное время отклика: 20–50ms. Polling освобождает поток как только приложение обработало ⌘C.

**Урок:** Fixed sleep для межпроцессного взаимодействия — антипаттерн. Всегда поллируй сигнал готовности.

---

### §6 — Clipboard Fallback: ⌘V vs typeText()

**Было написано:**
```swift
// Simulate Cmd+V
func paste() { ... vDown?.flags = .maskCommand ... }
```

**Что получилось:**
`⌘V` в Electron-приложениях перемещает курсор в начало поля перед вставкой (известный баг в некоторых версиях Electron). Вместо этого используется `typeText()` — прямая отправка Unicode строки как keyboard event:

```swift
private func typeText(_ text: String) {
    var utf16 = Array(text.utf16)
    let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
    down?.flags = []  // Критично: очистить модификаторы (иначе ⌥ из hotkey передаётся)
    down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
    down?.post(tap: .cgAnnotatedSessionEventTap)
}
```

Важная деталь: `down?.flags = []` — обязательно. `CGEventSource(.hidSystemState)` отражает текущее состояние железа, и если hotkey modifier (⌥) ещё зажат, событие унаследует флаг. Результат: `virtualKey=0 + maskAlternate = ⌥A` — наш же tap перехватит и съест символ.

**Урок:** При генерации keyboard events через CGEvent всегда явно устанавливай флаги, не полагайся на defaults.

---

### §13 — Добавленные модули (не были в плане)

Два новых файла, которых не было в оригинальном плане:

**`Logging/LogExporter.swift`**
- `OSLogStore` с `scope: .currentProcessIdentifier`
- `TimeRange` enum: `.minutes(5/15/30)`, `.hours(1/24)`, `.all`
- `promptAndExport(since:)` с `NSSavePanel`
- Причина: диагностика на чужих машинах без доступа к Console.app

**`Accessibility/InputMonitoringPermissionManager.swift`**
- `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()`
- Причина: на некоторых машинах CGEventTap не устанавливался молча, нужен был способ диагностики и onboarding

**Урок:** Logging и diagnostics — это не optional polish. Это core infrastructure для любого background daemon.

---

### §4.2 — "Modifier-only hotkeys не поддерживаются в v1"

Осталось без изменений, всё верно. Но стоит добавить почему это правильное решение:

`flagsChanged` events для modifier-only hotkeys требуют отслеживания state machine (pressed/released + timing). Это добавляет ~50 строк кода и потенциальные false positives. `⌥ Space` как default решает проблему элегантно.

---

## Реальная файловая структура (дополнения к §2)

```
LayoutFixer/
├── App/
│   ├── LayoutFixerApp.swift
│   └── AppDelegate.swift
│
├── Orchestration/
│   └── FixOrchestrator.swift          # Сильно расширен vs план
│
├── Hotkey/
│   ├── HotkeyManager.swift            # + onTapInstallFailed callback
│   ├── HotkeyRecorder.swift
│   └── HotkeyDefinition.swift
│
├── Accessibility/
│   ├── AXPermissionManager.swift
│   ├── AXTextReader.swift
│   ├── AXTextWriter.swift             # + selectResult: Bool parameter
│   └── InputMonitoringPermissionManager.swift  # НОВЫЙ
│
├── Conversion/
│   ├── LayoutMapping.swift            # + ё/Ё mapping
│   ├── DirectionDetector.swift
│   ├── LayoutConverter.swift
│   └── LayoutCycleManager.swift       # НОВЫЙ — language cycle logic
│
├── Clipboard/
│   └── ClipboardManager.swift
│
├── Menubar/
│   ├── MenubarManager.swift           # + Log Export submenu, Input Monitoring item
│   └── StatusIconAnimator.swift
│
├── Settings/
│   ├── AppSettings.swift              # + clipboardPollTimeoutMs
│   ├── SettingsView.swift             # + Permissions section, Advanced section
│   └── LanguageOrderView.swift        # НОВЫЙ — drag-and-drop language ordering
│
├── Audio/
│   └── SoundPlayer.swift
│
├── Login/
│   └── LoginItemManager.swift
│
├── Logging/
│   └── LogExporter.swift              # НОВЫЙ
│
└── Resources/
    ├── Assets.xcassets
    └── Info.plist
```

---

## Обновлённые Known Pitfalls (дополнение к §14)

| # | Pitfall | Что произошло | Mitigation |
|---|---|---|---|
| 13 | **Electron apps return nil focusedElement** | Teams не работал | Всегда пробовать clipboard fallback, даже при nil element |
| 14 | **VS Code ⌘C copies whole line with \n** | Phase 1 давал неверный результат | Проверять trailing newline, пропускать в Phase 2 |
| 15 | **⌥⇧← останавливается на пунктуации** | `cj,frf` → только `frf` | Принято как known limitation v1 |
| 16 | **CGEvent наследует modifier flags от hotkey** | typeText() отправлял ⌥+char | Всегда явно `down?.flags = []` |
| 17 | **@AppStorage + @Observable без @ObservationIgnored** | Runtime warnings, некорректный binding | Добавлять `@ObservationIgnored` к каждому `@AppStorage` свойству |
| 18 | **Новые Swift файлы в Xcode не попадают в target автоматически** | "Cannot find type in scope" после создания файла | При добавлении файлов вне Xcode — вручную редактировать pbxproj |
| 19 | **OSLogStore.getEntries privacy masking** | Bundle IDs третьих сторон отображались как `<private>` | Использовать `privacy: .public` для third-party app identifiers |
| 20 | **Teams игнорирует ⌘C без выделения** | Phase 1 всегда таймаутился в Teams | Configurable timeout (100ms) + Phase 2 всегда выполняется |

---

## Реальный порядок реализации (vs план)

Плановый порядок фаз 1–10 в целом соблюдался, но несколько итераций добавились постфактум:

**Итерация 11 — Diagnostics & Cross-machine debugging**
- LogExporter, Input Monitoring detection
- Причина: приложение не работало на рабочем ноутбуке, нужна была телеметрия

**Итерация 12 — Teams/Electron fix**
- nil focusedElement → fallback вместо no-op
- Добавлены подробные логи для каждой фазы

**Итерация 13 — UX polish**
- selectResult: Bool для сохранения ожидаемого положения курсора
- Configurable clipboard timeout

**Итерация 14 — Charset completeness**
- ё/Ё mapping

**Урок:** Закладывай ~30% времени на "итерации после первого рабочего прототипа". Первый рабочий прототип на TextEdit — это не "done". Done = работает на всех целевых приложениях на всех целевых машинах.

---

## Что стоило бы сделать по-другому

1. **Logging с первого дня.** `os.Logger` был там с начала, но без export механизма. Когда понадобилась диагностика на чужой машине, пришлось срочно писать LogExporter. Это должно было быть в Phase 1.

2. **Тестировать на Electron в первую очередь, а не в последнюю.** Electron — самый сложный кейс и наиболее частый. В плане он был в конце чеклиста.

3. **Документировать word-boundary behavior явно.** ⌥⇧← как механизм word selection имеет конкретные правила (стоп на пунктуации). Это не баг — это OS behavior. PRD должен был это явно специфицировать.

4. **Clipboard polling вместо fixed sleep сразу.** Fixed sleep проще написать, но polling лучше во всех отношениях. Это была известная проблема (§14 #4 в оригинальном плане), но решение отложили.
