# LayoutFixer_CC — Product Requirements Document

## 1. Overview

LayoutFixer_CC — это macOS utility, позволяющая исправлять текст, набранный в неправильной клавиатурной раскладке.

Исправление происходит по глобальному хоткею и работает:
- для выделенного текста
- для последнего введённого токена (в v1 — последнее слово)

**Примеры:**
```
ghbdtn → привет
руддщ  → hello
```

Приложение должно работать в большинстве текстовых полей macOS приложений:
- VS Code
- Терминалы
- Браузеры
- IDE
- Мессенджеры

---

## 2. Problem Statement

При работе с несколькими языками пользователи регулярно печатают текст в неправильной раскладке.

**Пример:**
```
User types: ghbdtn
Expected:   привет
```

Исправление вручную требует:
1. Удалить текст
2. Переключить раскладку
3. Набрать текст заново

Это прерывает поток работы и снижает скорость ввода.

---

## 3. Product Goals

### 3.1 Быстрое исправление текста

Исправление происходит по одному хоткею.

**Логика выбора режима (один хоткей):**
- Если есть выделение → конвертировать выделенный текст
- Если выделения нет → конвертировать последний введённый токен

### 3.2 Работа в различных приложениях macOS

Приложение работает в большинстве текстовых полей:
- Editors
- Terminals
- Browsers
- Native input fields

### 3.3 Минимально заметная задержка

Операция выполняется достаточно быстро, чтобы пользователь воспринимал её как моментальную.

Точное ограничение на latency не устанавливается.

### 3.4 Ненавязчивый UX

Приложение работает как background utility.

UI включает:
- Menubar icon
- Простой интерфейс конфигурации

---

## 4. Core User Flows

### 4.1 Fix Last Token (no selection)
```
User печатает: ghbdtn
Нажимает хоткей
Результат: привет
```

### 4.2 Fix Selected Text
```
User выделяет: ghbdtn vbh
Нажимает хоткей
Результат: привет мир
```

---

## 5. Last Token — Definition

### v1 (MVP)
Последний токен = последнее слово слева от каретки.

**Word boundary delimiters (v1):** space, tab, newline only.

Пример: каретка после `hello world|` → токен = `world`.

### v2 (Future)
Последний токен = весь последний введённый фрагмент, включая:
- Буквы
- Цифры
- Знаки препинания

Разделитель токена — пробел или явный разрыв ввода.

---

## 6. User Feedback

После выполнения операции — визуальный и аудио фидбек.

### Visual Feedback
Иконка приложения в menubar кратковременно меняется на флаг целевого языка (языка результата конверсии), затем возвращается к стандартной иконке.

Пример: если текст сконвертирован в русский → показывается флаг 🇷🇺, если в английский → 🇬🇧.

### Audio Feedback
Проигрывается настраиваемый звук из встроенного набора.

Пользователь может (в v1):
- Выбрать звук из куратированного списка (3–5 вариантов)
- Настроить уровень громкости
- Отключить звук

---

## 7. Language Handling

### Mode 1 — Explicit Language Pair (v1)
Пользователь задаёт конкретную пару языков:
```
RU ↔ EN
```
Конверсия происходит между этими раскладками.

**Mapping:** стандартные физические позиции клавиш QWERTY (й→q, ц→w, у→e, …).

**Direction:** автоматическое определение направления по символам в тексте (bidirectional auto-detection). Пользователь не выбирает направление вручную.

### Mode 2 — System Input Sources (v2)
Приложение использует языки, добавленные в macOS Input Sources.

В этом режиме приложение:
- Определяет текущий input source
- Выбирает альтернативный язык
- Выполняет конверсию

**Optional behavior:** после конверсии переключить системную раскладку на язык результата.

---

## 8. Interaction With Other Applications

Для получения и изменения текста в других приложениях используются механизмы macOS.

**Text reading:** через AXUIElement Accessibility API — без визуального выделения текста.

**Text writing (priority order):**
1. Установить `AXValue` напрямую через AXUIElement (не затрагивает clipboard)
2. Fallback: поместить текст в clipboard → симулировать `Cmd+V` → восстановить оригинальный clipboard

**Если AXUIElement не может прочитать поле** (например, некоторые Electron-приложения, кастомные рендереры) — операция завершается молча (silent no-op), без звука и визуального фидбека.

**Важно:** приложение не использует keyboard sniffing (постоянный мониторинг нажатий клавиш). Это принципиально для возможности распространения через Mac App Store.

---

## 9. Text Processing Pipeline
```
Hotkey pressed
↓
Check accessibility permission
  → if not granted: silent no-op (user prompted only on first trigger)
↓
Read focused element via AXUIElement
  → if element unreadable: silent no-op
↓
Detect explicit selection
↓
IF selection exists
    read selected text via AXUIElement
ELSE
    locate previous word left of caret (delimiter: space / tab / newline)
    → if nothing found: silent no-op
↓
Auto-detect direction (RU→EN or EN→RU) from characters
↓
Convert layout (QWERTY physical key mapping)
↓
Write converted text back:
    try AXValue set directly
    fallback: clipboard → Cmd+V → restore clipboard
↓
UI feedback (sound + language flag icon swap)
```

---

## 10. Permissions

**Accessibility Access** — разрешение позволяет приложению:
- Получать информацию о выделении текста
- Управлять курсором
- Вставлять текст

Настраивается пользователем в:
```
System Settings → Privacy & Security → Accessibility
```

**Onboarding strategy:**
- Приложение запускается молча в menubar без запроса разрешений
- При первом нажатии хоткея без разрешения — показывается prompt с объяснением и кнопкой открытия System Settings
- В menubar меню есть пункт "Accessibility Permissions" для повторного открытия System Settings в любой момент

---

## 11. Tech Stack

| Component       | Choice                          |
|----------------|---------------------------------|
| Language       | Swift                           |
| UI Framework   | SwiftUI + @Observable           |
| Min macOS      | 14.0 Sonoma                     |
| Text Access    | Accessibility API (AXUIElement) |
| Hotkey         | CGEventTap / Carbon HotKeys     |
| Input method   | No keyboard sniffing            |
| Settings store | UserDefaults                    |

---

## 12. Hotkey

Один глобальный хоткей, настраивается пользователем в настройках приложения (**v1**).

### Поддерживаемые форматы:
- **Одна клавиша-модификатор** — например, `⌥` (Option)
- **Комбинация** — модификатор + клавиша, например `⌥Q`, `⌃⌥Space`

### Default:
`⌥ Space` — не конфликтует с системными shortcuts macOS по умолчанию.

### Требования к UI настройки хоткея:
- Пользователь нажимает желаемую комбинацию прямо в поле настройки (key recorder)
- Приложение отображает записанную комбинацию в human-readable виде (`⌥Q`, `⌥`)
- Валидация: предупреждение если комбинация конфликтует с известными системными shortcuts

---

## 13. Menubar Menu

Меню при клике на иконку в menubar:

- **Enable / Disable** — toggle (приостановить работу хоткея без выхода из приложения)
- **Settings…** — открывает окно настроек
- **Accessibility Permissions** — открывает System Settings → Privacy & Security → Accessibility
- **About**
- **Quit**

---

## 14. Settings

Окно настроек содержит:

- **Hotkey** — key recorder для записи комбинации
- **Sound** — выбор звука из куратированного списка + слайдер громкости + toggle отключения
- **Launch at Login** — toggle (включён по умолчанию при первой установке)
- **Language Pair** — отображение текущей пары (RU ↔ EN в v1)

---

## 15. Non-Goals

Приложение **не** предназначено для:
- Постоянного мониторинга всех нажатий клавиш (keyboard sniffing)
- Замены стандартного переключения раскладок
- Выполнения сложного редактирования текста
- Автоматического определения языка без участия пользователя

---

## 16. Distribution

| Channel        | Status    | Notes                                              |
|---------------|-----------|----------------------------------------------------|
| GitHub        | v1        | Open source release                                |
| Homebrew      | v2        | After stable release                               |
| Mac App Store | Potential | Требует отсутствия keyboard sniffing — уже учтено  |

---

## 17. Version Roadmap

### v1 (MVP)
- [ ] Fix last word (no selection)
- [ ] Fix selected text
- [ ] RU ↔ EN explicit pair with bidirectional auto-detection
- [ ] QWERTY physical key position mapping
- [ ] Configurable hotkey (single modifier or modifier+key)
- [ ] Menubar icon with language flag feedback
- [ ] Audio feedback: curated sound list + volume control
- [ ] Launch at login (enabled by default)
- [ ] Accessibility permission onboarding (lazy — on first hotkey use)
- [ ] Settings window (hotkey, sound, launch at login)
- [ ] Menubar menu (enable/disable, settings, permissions, about, quit)

### v2
- [ ] Fix last token (full fragment, not just word)
- [ ] System Input Sources mode
- [ ] Auto switch layout after conversion
- [ ] Custom sound selection (user-provided files)
- [ ] Dedicated onboarding window (welcome → permission → done)

## 18. Behavioral Test Cases

Этот раздел описывает набор ручных тестов (edge cases), которые должны
всегда корректно работать. Они используются как основной regression
набор при разработке.

Если изменение ломает один из этих сценариев — это считается багом.

---

### 18.1 Last Word Conversion

**Case 1 — Single word**

```
Input:
тест|

Hotkey →

Expected:
ntcn|
```

---

**Case 2 — Two words**

```
Input:
тест тест|

Hotkey →

Expected:
тест ntcn|
```

Конвертируется **только последнее слово**.

---

**Case 3 — Newline boundary**

```
Input:
тест
тест|

Hotkey →

Expected:
тест
ntcn|
```

Последний токен определяется **относительно каретки**, а не строки.

---

### 18.2 Explicit Selection

Если пользователь выделил текст — конвертируется именно выделение.

---

**Case 4 — Single word selection**

```
Input:
<тест>

Hotkey →

Expected:
ntcn
```

---

**Case 5 — Multi-word selection**

```
Input:
<тест тест>

Hotkey →

Expected:
ntcn ntcn
```

---

**Case 6 — Selection inside sentence**

```
Input:
hello <тест> world

Hotkey →

Expected:
hello ntcn world
```

Остальной текст не должен изменяться.

---

### 18.3 Clipboard Safety

Clipboard пользователя не должен изменяться.

```
Clipboard before:
ABC

User converts text

Clipboard after:
ABC
```

---

### 18.4 Trailing Newline Artifact

Некоторые приложения (например VS Code) добавляют newline при копировании.

```
Copied text:
"тест\n"
```

Ожидаемое поведение:

```
Normalized:
"тест"
```

Удаляются **только хвостовые newline**, но не newline внутри текста.

---

### 18.5 Multiline Selection

```
Input:
<тест
тест>

Hotkey →

Expected:
ntcn
ntcn
```

---

### 18.6 Punctuation Safety

В v1 знаки препинания не входят в токен.

```
Input:
тест,|

Hotkey →

Expected:
ntcn,|
```

Delimiter для v1:

```
space
tab
newline
```

---

### 18.7 Cursor Position Guarantee

Курсор должен оставаться в логически ожидаемой позиции.

```
Input:
hello тест|

Hotkey →

Expected:
hello ntcn|
```

---

### 18.8 No Duplication Guarantee

Неверное поведение:

```
тест|
Hotkey →

ntcnтест
```

Правильное поведение:

```
тест|
Hotkey →

ntcn|
```

---

### 18.9 Silent Failure Behavior

Если приложение не может получить текст из поля через Accessibility API:

```
Result → silent no-op
```

Без:

- звука
- изменения иконки
- изменения clipboard

---

## 19. Language Management — Updated Design (v2)

### Concept

Instead of a hardcoded RU ↔ EN pair, the app reads all keyboard layouts available in macOS Input Sources and lets the user build an **ordered list** of layouts to cycle through.

### Setup (Settings UI)

1. App reads all layouts from macOS Input Sources
2. User selects a subset and defines their order, e.g.: `[EN, RU, DE]`
3. This ordered list is persisted in AppSettings

### Conversion Logic

On hotkey press:
1. Read the **current active macOS input source**
2. Find it in the user's ordered list
3. Take the **next layout** in the list (wraps around cyclically)
4. Convert the token from current layout → next layout
5. (Optional) Switch the system input source to the target layout

**Edge case:** if current system layout is not in the user's list → use the first layout in the list as source.

### Example
```
User list:     [EN → RU → DE → EN → ...]
System layout: RU

Hotkey pressed → convert token RU→DE
Next press     → convert token DE→EN
Next press     → convert token EN→RU
```

### UI Requirements

- Settings screen shows all available macOS Input Sources
- User can add/remove layouts to their active list
- User can reorder the list (drag & drop or up/down arrows)
- Current active list is clearly visible in menubar menu