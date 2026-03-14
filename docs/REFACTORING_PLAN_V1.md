# LayoutFixer — Refactoring Plan v1

## Цель

Повысить тестируемость, явность контрактов и расширяемость кода без изменения поведения.
Каждый этап — самостоятельный, завершённый шаг. После каждого приложение собирается и работает.

---

## Этап 1 — Устранение force cast в AXTextReader

**Файл:** `Accessibility/AXTextReader.swift`

**Проблема:**
```swift
return (focusedElement as! AXUIElement)   // crash если AX вернёт неожиданный тип
app as! AXUIElement                        // то же
axValue as! AXValue                        // то же
```

**Что делаем:**
Заменить все `as!` на `guard let ... as?` с возвратом `nil`.

**Результат:** defensive code, нет потенциальных crash-ов.

**Сложность:** низкая. Чисто механическая замена.

---

## Этап 2 — Явная actor-изоляция ClipboardManager

**Файл:** `Clipboard/ClipboardManager.swift`

**Проблема:**
`ClipboardManager` владеет изменяемым состоянием (`pendingRestore`, `pendingOriginal`).
Потокобезопасность сейчас держится неявно — только потому что FixOrchestrator помечен `@MainActor`.
Если кто-то вызовет ClipboardManager из другого контекста, компилятор не предупредит.

**Что делаем:**
```swift
// было
class ClipboardManager { ... }

// стало
@MainActor
final class ClipboardManager { ... }
```

Компилятор начнёт явно гарантировать что всё происходит на main actor.
Возможно потребуется добавить `await` в паре мест в FixOrchestrator.

**Результат:** явная гарантия потокобезопасности на уровне типа.

**Сложность:** низкая.

---

## Этап 3 — Result type вместо Bool в AXTextWriter

**Файл:** `Accessibility/AXTextWriter.swift`

**Проблема:**
```swift
let ok = axWriter.write(...)
if !ok { clipboard.writeAndPaste(text: converted) }
// непонятно почему упало: range out of bounds? AX error? fullText == nil?
```

**Что делаем:**

Добавить enum в `AXTextWriter.swift`:
```swift
enum AXWriteFailure {
    case fullTextUnreadable
    case rangeOutOfBounds
    case axError(AXError)
}
```

Изменить сигнатуру:
```swift
// было
func write(...) -> Bool

// стало
func write(...) -> Result<Void, AXWriteFailure>
```

В `FixOrchestrator.finishAX`:
```swift
switch axWriter.write(...) {
case .success:
    break
case .failure(let reason):
    logger.info("AX write failed: \(reason) — using clipboard fallback")
    clipboard.writeAndPaste(text: converted)
}
```

**Результат:** логи теперь показывают конкретную причину fallback.

**Сложность:** низкая.

---

## Этап 4 — Протоколы для AXTextReader и AXTextWriter

**Файлы:** `Accessibility/AXTextReader.swift`, `Accessibility/AXTextWriter.swift`

**Проблема:**
FixOrchestrator зависит от конкретных типов → unit-тесты невозможны.

**Что делаем:**

Добавить протоколы (можно в те же файлы или в отдельные `Protocols/`):

```swift
protocol TextReading {
    func focusedElement() -> AXUIElement?
    func fullText(of element: AXUIElement) -> String?
    func selectionRange(of element: AXUIElement) -> CFRange?
    func selectedText(of element: AXUIElement) -> String?
    func lastWord(of element: AXUIElement) -> (text: String, range: CFRange)?
}

protocol TextWriting {
    func write(
        convertedText: String,
        replacing range: CFRange,
        in element: AXUIElement,
        selectResult: Bool
    ) -> Result<Void, AXWriteFailure>
}
```

Добавить `extension AXTextReader: TextReading {}` и `extension AXTextWriter: TextWriting {}`.

Изменить FixOrchestrator:
```swift
// было
private let axReader: AXTextReader
private let axWriter: AXTextWriter

// стало
private let axReader: any TextReading
private let axWriter: any TextWriting
```

AppDelegate передаёт конкретные типы как раньше — ничего не меняется снаружи.

**Результат:** разблокированы unit-тесты для FixOrchestrator.

**Сложность:** средняя. Нужно аккуратно согласовать сигнатуры после этапа 3.

---

## Этап 5 — Протокол для ClipboardManager

**Файл:** `Clipboard/ClipboardManager.swift`

Аналогично этапу 4:

```swift
protocol ClipboardManaging {
    func saveClipboard() -> [[NSPasteboard.PasteboardType: Data]]
    func setString(_ string: String)
    func paste()
    func restoreClipboard(_ saved: [[NSPasteboard.PasteboardType: Data]])
    func writeAndPaste(text: String)
}

extension ClipboardManager: ClipboardManaging {}
```

Изменить FixOrchestrator:
```swift
private let clipboard: any ClipboardManaging
```

**Сложность:** низкая.

---

## Этап 6 — Strategy Pattern для извлечения текста

**Файл:** `Orchestration/FixOrchestrator.swift` + новые файлы в `Orchestration/`

**Проблема:**
`trigger()` — один большой метод с вложенным if/else для трёх путей (AX selection, AX lastWord, keyboard fallback).
Добавление нового пути требует редактирования ядра оркестратора.

**Что делаем:**

Новый файл `Orchestration/TextExtractionStrategy.swift`:
```swift
struct ExtractionResult {
    let text: String
    let writeBack: WriteBack

    enum WriteBack {
        case ax(range: CFRange, element: AXUIElement, selectResult: Bool)
        case keyboard   // результат пишется через typeText в самой стратегии
    }
}

protocol TextExtractionStrategy {
    func extract() async -> ExtractionResult?
}
```

Три файла стратегий:

`Orchestration/Strategies/AXSelectionStrategy.swift`:
```swift
struct AXSelectionStrategy: TextExtractionStrategy {
    let reader: any TextReading
    let element: AXUIElement

    func extract() async -> ExtractionResult? {
        guard let range = reader.selectionRange(of: element), range.length > 0,
              let text = reader.selectedText(of: element), !text.isEmpty
        else { return nil }
        return ExtractionResult(text: text, writeBack: .ax(range: range, element: element, selectResult: true))
    }
}
```

`Orchestration/Strategies/AXLastWordStrategy.swift`:
```swift
struct AXLastWordStrategy: TextExtractionStrategy {
    let reader: any TextReading
    let element: AXUIElement

    func extract() async -> ExtractionResult? {
        guard let (word, range) = reader.lastWord(of: element) else { return nil }
        return ExtractionResult(text: word, writeBack: .ax(range: range, element: element, selectResult: false))
    }
}
```

`Orchestration/Strategies/KeyboardFallbackStrategy.swift`:
```swift
struct KeyboardFallbackStrategy: TextExtractionStrategy {
    // содержит логику Phase 1 + Phase 2 (вынесена из FixOrchestrator)
    ...
}
```

`trigger()` становится:
```swift
func trigger() async {
    // ... guards (isConverting, debounce, permission, pair) ...

    let element = axReader.focusedElement()

    let strategies: [any TextExtractionStrategy] = element.map {
        [AXSelectionStrategy(reader: axReader, element: $0),
         AXLastWordStrategy(reader: axReader, element: $0),
         KeyboardFallbackStrategy(...)]
    } ?? [KeyboardFallbackStrategy(...)]

    for strategy in strategies {
        if let result = await strategy.extract() {
            await finish(result, pair: pair)
            return
        }
    }
}
```

**Результат:**
- `trigger()` — ~30 строк вместо 110
- Каждая стратегия тестируется изолированно
- Новый путь = новый файл, не правка оркестратора

**Сложность:** высокая. Самый большой шаг рефакторинга.

---

## Этап 7 — Фикс двойного чтения fullText

**Файлы:** `Accessibility/AXTextWriter.swift`, `Orchestration/FixOrchestrator.swift`

**Проблема:**
`AXTextWriter.write()` содержит `private let reader = AXTextReader()` и читает `fullText` повторно.
FixOrchestrator уже прочитал его в `axReader.lastWord()`.

**Что делаем:**
Убрать `private let reader` из AXTextWriter. Принимать `fullText` как параметр:

```swift
// было
func write(convertedText: String, replacing range: CFRange, in element: AXUIElement, ...) -> Result<...>
// внутри: guard let fullText = reader.fullText(of: element)

// стало
func write(convertedText: String, replacing range: CFRange, fullText: String, in element: AXUIElement, ...) -> Result<...>
// fullText приходит снаружи — уже прочитан в стратегии
```

Передавать fullText из `AXLastWordStrategy` (он уже его имеет после `lastWord()`).
Для `AXSelectionStrategy` fullText не нужен вообще — используется `kAXSelectedTextAttribute`.

**Результат:** один AX-запрос вместо двух при lastWord пути.

**Сложность:** средняя (зависит от результата этапа 6).

---

## Этап 8 — Устранение activeLayoutsVersion hack

**Файл:** `Settings/AppSettings.swift`

**Проблема:**
```swift
private var activeLayoutsVersion = 0
// ...
_ = activeLayoutsVersion  // костыль для регистрации наблюдателя
activeLayoutsVersion &+= 1  // костыль для уведомления
```

**Что делаем:**
Варианты (выбрать один):

**Вариант A — ObservableObject вместо @Observable для AppSettings:**
```swift
// @Observable + @AppStorage — плохая комбинация
// ObservableObject + @AppStorage — работает нативно

final class AppSettings: ObservableObject {
    @AppStorage("activeLayouts") var activeLayoutsData: Data = Data()
    // @Published не нужен — @AppStorage сам триггерит objectWillChange
}
```
Трейдоф: нужно поменять `@Environment(AppSettings.self)` на `@EnvironmentObject`.

**Вариант B — хранить activeLayouts как отдельный @Observable массив:**
```swift
@Observable
final class AppSettings {
    var activeLayouts: [LayoutInfo] = []  // напрямую @Observable, без AppStorage

    func saveActiveLayouts() {
        UserDefaults.standard.set(try? JSONEncoder().encode(activeLayouts), forKey: "activeLayouts")
    }

    func loadActiveLayouts() {
        // в init
    }
}
```
Чище, но нужно явно вызывать save/load.

**Рекомендуемый вариант:** B, хранение напрямую в массиве с явным persist().

**Сложность:** средняя.

---

## Этап 9 — Unit Tests

**Новый target:** `LayoutFixerTests`

После этапов 4–5 зависимости тестируемы через протоколы. Пишем:

| Тест | Mock |
|---|---|
| `FixOrchestratorTests` — полный pipeline | `MockTextReader`, `MockTextWriter`, `MockClipboard` |
| `AXSelectionStrategyTests` | `MockTextReader` |
| `AXLastWordStrategyTests` | `MockTextReader` |
| `LayoutMappingTests` | нет (pure functions) |
| `LayoutConverterTests` | нет |
| `DirectionDetectorTests` | нет |
| `ClipboardManagerTests` | реальный NSPasteboard (или mock) |

Минимальный набор для начала — тесты pure functions (этапы 1–3 не нужны для этого):
```
LayoutMappingTests     — все 66 пар EN→RU и обратно
LayoutConverterTests   — "ghbdtn" → "привет", round-trip
DirectionDetectorTests — edge cases (пустая строка, цифры, смешанный)
```

**Сложность:** низкая для pure functions, средняя для orchestrator с mock-ами.

---

## Порядок выполнения

```
Этап 1  Force cast fix              — 30 мин   — нет зависимостей
Этап 2  ClipboardManager @MainActor — 20 мин   — нет зависимостей
Этап 3  Result type в AXTextWriter  — 30 мин   — нет зависимостей
Этап 4  Протоколы TextReading/Writing — 1 ч   — нужен этап 3
Этап 5  Протокол ClipboardManaging  — 20 мин   — нужен этап 2
Этап 9  Unit tests (pure functions) — 1 ч      — нет зависимостей, можно параллельно
Этап 6  Strategy Pattern            — 3–4 ч    — нужны этапы 4, 5
Этап 7  Double-read fix             — 30 мин   — нужен этап 6
Этап 8  activeLayoutsVersion fix    — 1 ч      — нет зависимостей
```

Этапы 1–3 + 9 (pure functions) можно брать в любом порядке независимо.
Этапы 4–7 — последовательно.
Этап 8 — независим, но затрагивает много UI кода, лучше делать отдельным PR.

---

## Что НЕ входит в этот план

- Изменение логики конверсии
- Новые функции (auto-detection, etc.)
- Изменение UI
- Логика word-boundary (отдельная задача, требует own word-selection вместо ⌥⇧←)
- Notarization / CI pipeline
