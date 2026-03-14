# LayoutFixer — POST-MORTEM Project Plan (Retrospective)

> Ретроспективный проектный план. Написан постфактум.
> Описывает реальный ход проекта, отклонения от плана, и что стоит учесть в следующий раз.

---

## Реальное состояние на момент завершения

| Критерий | Статус |
|---|---|
| Все 10 задач выполнены | ✅ |
| Конвертация работает в TextEdit, Safari, Telegram | ✅ |
| Конвертация работает в VS Code (Electron) | ✅ |
| Конвертация работает в Teams (Electron, no AX) | ✅ |
| Поддержка нескольких языков (cycle) | ✅ реализовано в v1, было в плане v2 |
| ё/Ё mapping | ✅ добавлено по ходу |
| Configurable clipboard timeout | ✅ добавлено по ходу |
| Log export | ✅ добавлено по ходу |
| Input Monitoring permission UI | ✅ добавлено по ходу |
| Unit tests | ❌ написаны не были (не хватило приоритета) |
| Notarization через GitHub Actions | ❌ не реализовано |
| Build version | 1.1.1 (build 111) |

---

## Overview

**Что реализовалось:** macOS menubar utility для исправления текста в неправильной раскладке. Работает через глобальный хоткей, поддерживает AX API для нативных приложений и keyboard+clipboard fallback для Electron/CEF.

**Стек:** Swift 5.10, SwiftUI, `@Observable`, CGEventTap, AXUIElement, OSLogStore.

---

## Задачи — Реальный статус

### Task 1–10: Оригинальные задачи

Все 10 оригинальных задач были выполнены примерно в том же порядке, что и планировалось. Существенных отклонений в процессе реализации основного пайплайна не было — архитектурные решения (DI через init, @MainActor, @Observable) оказались правильными.

### Task 11: Diagnostics & Cross-machine debugging (не был в плане)

**Причина:** Приложение работало на личном ноутбуке, но не работало на рабочем. Без логов — невозможно понять почему. Оказалось: Teams возвращает nil focusedElement, VS Code копировал строку с \n в Phase 1.

**Что было сделано:**
- `os.Logger` с `privacy: .public` для app bundle IDs
- `LogExporter` с `OSLogStore` + NSSavePanel
- Export Logs submenu в menubar
- Детальные логи каждой фазы (Phase 1/Phase 2 timing, AX path selection)

**Время:** ~2 итерации (добавить логи → получить логи с другой машины → исправить)

### Task 12: Electron/Teams Fix (не был в плане)

**Причина:** Обнаружено по логам с рабочего ноутбука.

**Root cause:** Teams не реализует AX API → `focusedElement()` = nil → оригинальный код: early return (silent no-op) → хоткей ничего не делал.

**Fix:** одна строка в FixOrchestrator — вместо `return` при nil element: `await keyboardFallback(pair: pair)`.

**Урок:** Самые критичные баги находятся при тестировании на реальных машинах пользователя, не в dev среде.

### Task 13: UX Polish (частично в плане, частично нет)

- **selectResult: Bool** — не был предусмотрен. Пользователь заметил что после конвертации lastWord слово оказывается выделено. Ожидание: курсор стоит после слова.
- **Configurable clipboard timeout** — был запрошен явно. Пользователь хотел уменьшить задержку (100ms vs 300ms).
- **ё/Ё mapping** — упущение в mapping table, обнаружено при реальном использовании.

---

## Success Criteria — Реальный результат

| Критерий из оригинального плана | Результат |
|---|---|
| All tasks complete | ✅ |
| All unit tests pass | ❌ unit tests не написаны |
| Build succeeds on macOS 14.0+ | ✅ |
| No linting errors | ✅ |
| Manual test checklist §18 пройден | ✅ (частично — не все пункты проверялись формально) |

---

## Technical Constraints — Уточнения

| Constraint | Планировалось | Реально |
|---|---|---|
| `@ObservationIgnored` | Не нужен на macOS 14+ | **Нужен** для `@AppStorage` внутри `@Observable` |
| Clipboard restore | Fixed 150ms delay | **Polling** 10ms ticks до changeCount изменится |
| Clipboard write | ⌘V via CGEvent | **typeText()** via Unicode CGEvent (⌘V двигал курсор в Electron) |
| Electron support | Silent no-op | **Full keyboard+clipboard fallback** |
| Permissions | Accessibility only | **+ Input Monitoring** (для диагностики) |

---

## Что стоит учесть в следующем проекте

### 1. Logging — это infrastructure, не feature

Logging должен быть в Task 1, не в Task 11. Для любого background macOS daemon без UI логи — единственный способ понять что происходит на другой машине. `os.Logger` прост в настройке, экспорт через `OSLogStore` — ~50 строк.

**Rule:** создавай LogExporter в тот же день, что создаёшь первый `Logger`.

---

### 2. Тестируй на самом сложном таргете первым

Порядок тестирования в оригинальном плане: TextEdit → Safari → VS Code → Telegram. Это "от простого к сложному". В реальности: баги в Electron обнаружены последними, когда вся архитектура уже устоялась.

**Rule:** тестируй на Electron-приложении (самый сложный кейс) сразу после Task 7 (Orchestrator). Не откладывай на "финальный checklist".

---

### 3. Fixed sleep → polling

Везде, где нужно дождаться реакции другого процесса (clipboard change, window appear, process launch) — используй polling с reasonable timeout, не fixed sleep. Fixed sleep — это либо слишком долго, либо недостаточно долго.

```swift
// Вместо:
try? await Task.sleep(nanoseconds: 150_000_000)

// Делай:
for _ in 0..<maxTicks {
    if conditionMet { break }
    try? await Task.sleep(nanoseconds: pollInterval)
}
```

---

### 4. Явно устанавливай CGEvent flags

При создании CGEvent через `CGEventSource(.hidSystemState)` source отражает текущее состояние железа. Если hotkey modifier (⌥) ещё зажат — все созданные события унаследуют этот флаг. Всегда:

```swift
event?.flags = []  // или нужный набор флагов
```

---

### 5. nil AX element ≠ нет текстового поля

Electron, CEF, и некоторые другие фреймворки не реализуют AX API, но имеют работающие текстовые поля. nil от `focusedElement()` означает "AX не поддерживается", не "нет поля". Всегда пробуй fallback.

---

### 6. @AppStorage + @Observable требует @ObservationIgnored

Это underdocumented behavior. Без `@ObservationIgnored` `@AppStorage` внутри `@Observable` работает некорректно. Добавляй к каждому `@AppStorage` свойству.

---

### 7. Xcode не добавляет файлы в target автоматически при создании вне IDE

При создании Swift файлов через CLI/редактор файл не попадает в compile sources target. Нужно либо создавать файлы через Xcode (drag&drop в navigator), либо вручную редактировать pbxproj:
- Добавить в `PBXBuildFile` section
- Добавить в `PBXFileReference` section
- Добавить в `PBXSourcesBuildPhase` → files list
- Добавить в нужную `PBXGroup`

Симптом: "Cannot find type 'Foo' in scope" несмотря на то что файл существует.

---

### 8. Word boundary в ⌥⇧← — это OS behavior

⌥⇧← (Option+Shift+Left) — стандартное macOS действие "выделить предыдущее слово". Оно останавливается на пунктуации. Это не баг приложения, это поведение OS. При проектировании "last word" функциональности нужно либо:
- Принять это ограничение и задокументировать (v1)
- Реализовать собственную word-selection логику без ⌥⇧← (v2)

---

### 9. v1/v2 roadmap для небольших утилит — избыточно

"v2 features" обычно реализуются по мере реальных запросов, не по roadmap. Language cycle (планировался v2) реализовался в v1 потому что без него утилита не была полезной для пользователя с 3+ языками.

**Rule:** для утилит с одним пользователем/small team — веди backlog с приоритетами вместо жёстких версионных milestone.

---

## Финальный вывод

Ключевое расхождение между планом и реальностью — это **предположение что AX API покрывает все кейсы**. Оригинальный PRD и план были написаны в парадигме "AX work → great, AX fail → silent no-op". Реальность: для ~40% usage (Electron apps) нужен полноценный keyboard+clipboard fallback, и это не fallback — это primary path для этих приложений.

Второе ключевое расхождение — **отсутствие logging infrastructure** на старте. Без логов диагностика на удалённых машинах невозможна, и проблема с Teams была бы неразрешимой без добавления LogExporter.

Всё остальное — архитектурные решения, порядок задач, выбор API — оказалось правильным.
