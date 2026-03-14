# LayoutFixer — POST-MORTEM PRD (Retrospective)

> Это ретроспективная версия PRD, написанная постфактум после завершения v1.
> Отражает то, что реально было реализовано, и фиксирует расхождения с оригинальным планом.

---

## Что изменилось относительно оригинального PRD

### §8 — Interaction With Other Applications

**Было написано:**
> Если AXUIElement не может прочитать поле — операция завершается молча (silent no-op)

**Что получилось на практике:**
Silent no-op оказался неприемлемым. Electron-приложения (VS Code, Teams, Slack) либо не предоставляют `focusedElement()`, либо предоставляют элемент без читаемого `kAXValueAttribute`. Это значит, что для ~30–40% реального usage-а хоткей бы молча не работал.

**Что было сделано:**
Добавлен полноценный keyboard+clipboard fallback:
1. ⌘C — копировать выделенное
2. ⌥⇧← + ⌘C — если не было выделения, выделить последнее слово и скопировать

Teams был особым случаем: `focusedElement()` возвращал `nil`, но ⌘C/⌥⇧← работали. Пришлось отказаться от early return при `nil` элементе и всегда пробовать clipboard fallback.

**Урок:** Для macOS утилиты, которая должна работать "везде", AX API — это оптимистичный путь, а не единственный. Fallback-стратегия должна быть в PRD с первого дня.

---

### §9 — Text Processing Pipeline (реальная версия)

```
Hotkey pressed
↓
Check AX permission
  → if not granted: prompt (only first time), silent no-op
↓
Try to read focused element via AXUIElement
  → if element found: AX path (see below)
  → if element nil OR AX read fails: keyboard+clipboard fallback
↓
── AX PATH ──────────────────────────────────────────────
  Read selectionRange
  IF selection non-empty:
      read selectedText
      convert
      write via AXValue (selectResult: true — keep selection)
      if AXValue write fails: clipboard writeAndPaste
  ELSE:
      find lastWord left of caret
      convert
      write via AXValue (selectResult: false — cursor at end)
      if AXValue write fails: clipboard writeAndPaste

── KEYBOARD+CLIPBOARD FALLBACK ──────────────────────────
  Phase 1: ⌘C
    poll clipboard for change (configurable timeout, default 100ms)
    if changed AND no trailing newline → paste converted text
    if changed but trailing newline → skip to Phase 2 (VS Code line-copy)
    if unchanged → skip to Phase 2
  Phase 2: ⌥⇧← + ⌘C (select last word)
    poll clipboard for change
    if changed → paste converted text via typeText()
    if unchanged → collapse selection (→), restore clipboard, no-op
↓
UI feedback (sound + flag icon swap)
↓
Switch system input source to target layout
```

---

### §10 — Permissions

**Было написано:** только Accessibility permission.

**Что получилось:** CGEventTap требует Input Monitoring permission (для passive/listen-only taps), или активный tap (default) — только Accessibility. Однако на некоторых машинах с ограничительными политиками безопасности tap не устанавливался молча. Пришлось добавить:
- `onTapInstallFailed` callback в `HotkeyManager`
- NSAlert с объяснением и кнопкой "Open Settings → Input Monitoring"
- Строку Input Monitoring в SettingsView с индикатором статуса

**Урок:** Пиши все требования к разрешениям в PRD, даже если думаешь что они не нужны.

---

### §5 — Last Token Definition

**Было:**
> Word boundary delimiters (v1): space, tab, newline only.

**Реальное поведение:**
⌥⇧← (Option+Shift+Left) — стандартная macOS клавиша "выделить предыдущее слово" — останавливается на пунктуации (запятая, точка, скобки). Значит при тексте `cj,frf` (собака) выделяется только `frf`.

Это **известное ограничение** v1. Была попытка исправить через ⌘⇧← (выделить до начала строки), но это было хуже — конвертация всей строки более дезориентирует, чем конвертация фрагмента до запятой.

**Статус:** Принято как known limitation v1. В v2 — рассмотреть собственную реализацию word-selection логики.

---

### §6 — User Feedback (Post-conversion Selection)

**Было:** не специфицировано явно.

**Что обнаружилось:** После конвертации последнего слова (без предварительного выделения) текст оказывался выделен. Пользователь ожидает, что курсор встанет после слова, а не выделит его.

**Решение:** параметр `selectResult: Bool` в `AXTextWriter.write()`:
- `true` — при конвертации выделенного текста (пользователь видит результат выделенным)
- `false` — при конвертации lastWord (курсор ставится после слова)

**Урок:** UX после конвертации — это отдельный требования, его нужно специфицировать явно.

---

### §7 — Language Handling (Многоязычный цикл)

**Было в PRD §19:** Спроектировано как "v2 feature".

**Что получилось:** Реализовано в v1 — `LayoutCycleManager` с ordered list из Input Sources. Пользователи сразу хотели поддержку более 2 языков.

**Урок:** Features, которые пользователь попросит в первый день, не нужно откладывать в v2.

---

### §11 — Char Mapping (ё/Ё)

**Не было в PRD вообще.**

**Что оказалось:** Клавиша `` ` ``/`~` на QWERTY производит ё/Ё в русской раскладке, но маппинга не было. Пользователь заметил сразу на первой реальной раскладке.

**Урок:** Тестируй mapping таблицу на реальном тексте с нестандартными символами перед релизом.

---

### §13 — Menubar Menu (расширения)

**Было в PRD:** 5 пунктов — Enable/Disable, Settings, Accessibility Permissions, About, Quit.

**Что добавилось:**
- Input Monitoring Permissions
- Export Logs ▶ (с подменю: Last 5 min, Last 15 min, Last 30 min, Last hour, Last 24 hours, All logs)

**Причина:** Диагностика на удалённых машинах без Terminal доступа. OSLogStore позволяет экспортировать логи в текстовый файл из самого приложения.

**Урок:** Инструменты диагностики — это не v2 фича, это необходимость для любой background utility. Включи в PRD изначально.

---

### §14 — Settings (расширения)

**Добавлено:**
- Permissions section (Accessibility + Input Monitoring status с кнопками "Open Settings")
- Language Cycle — полноценный UI для управления ordered list раскладок (добавить/удалить/переупорядочить)
- Advanced section — Clipboard timeout (TextField, ms, default 100)

---

## Behavioral Test Cases — Обновлённые

### Добавить к §18.9 (Silent Failure → Fallback)

**Case: No focused AX element (Teams, some Electron apps)**

```
No focused element returned by AXUIElement
↓
App tries clipboard fallback anyway
↓
Phase 1: ⌘C — if text was selected, converts it
Phase 2: ⌥⇧← + ⌘C — selects last word, converts it
```

Это НЕ silent no-op. Fallback предпринимается всегда.

### Case: Trailing newline from VS Code line-copy (Phase 1)

```
Phase 1 clipboard change detected
Content: "тест\n"
↓
Skip to Phase 2 (don't convert line-copied content)
```

---

## Non-Goals — Уточнения

**Добавить:**
- Конвертация на уровне символов с учётом пунктуации как части токена — v2 (требует собственной word-selection логики вместо ⌥⇧←)
- Автоматическая конвертация без хоткея (на основе детекции раскладки в реальном времени)

---

## Version Reality

**Планировалось:** v1 → v2 roadmap.

**Что получилось:** Версионирование 1.0 → 1.0.9 → 1.1.0 → 1.1.1, инкрементальные релизы по feature-запросам. v2 как отдельный milestone не наступил — фичи из "v2" реализовывались по мере необходимости.

**Урок:** Для небольших утилит roadmap v1/v2 — это фикция. Лучше вести backlog фич с приоритетами без жёсткой версионной привязки.
