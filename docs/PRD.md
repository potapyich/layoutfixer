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
