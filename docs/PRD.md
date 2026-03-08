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
Последний токен = последнее слово слева от каретки (до первого пробела или начала строки).

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
Иконка приложения в menubar кратковременно мигает.

### Audio Feedback
Проигрывается настраиваемый звук.

Пользователь может:
- Выбрать звук
- Отключить звук

---

## 7. Language Handling

### Mode 1 — Explicit Language Pair (v1)
Пользователь задаёт конкретную пару языков:
```
RU ↔ EN
```
Конверсия происходит между этими раскладками.

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

**Assumption:** Accessibility APIs — наиболее практичный способ взаимодействия с текстовыми полями других приложений. Эта часть архитектуры может измениться если будут найдены более надёжные механизмы.

**Важно:** приложение не использует keyboard sniffing (постоянный мониторинг нажатий клавиш). Это принципиально для возможности распространения через Mac App Store.

---

## 9. Text Processing Pipeline
```
Hotkey pressed
↓
Check accessibility permission
↓
Detect explicit selection
↓
IF selection exists
    copy selection
ELSE
    select previous word (v1) / last token (v2)
↓
Convert layout
↓
Replace text
↓
Restore clipboard
↓
UI feedback (sound + icon blink)
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

---

## 11. Tech Stack

| Component    | Choice                          |
|-------------|----------------------------------|
| Language    | Swift                            |
| UI Framework | SwiftUI                         |
| Min macOS   | 13.0 Ventura                     |
| Text Access | Accessibility API (AXUIElement)  |
| Hotkey      | CGEventTap / Carbon HotKeys      |
| Input method | No keyboard sniffing            |

---

## 12. Hotkey

Один глобальный хоткей, настраивается пользователем в настройках приложения.

### Поддерживаемые форматы:
- **Одна клавиша-модификатор** — например, `⌥` (Option) нажатая дважды или отдельно
- **Комбинация** — модификатор + клавиша, например `⌥Q`, `⌃⌥Space`

### Default:
`⌥ Space` — не конфликтует с системными shortcuts macOS по умолчанию.

### Требования к UI настройки хоткея:
- Пользователь нажимает желаемую комбинацию прямо в поле настройки (key recorder)
- Приложение отображает записанную комбинацию в human-readable виде (`⌥Q`, `⌥`)
- Валидация: предупреждение если комбинация конфликтует с известными системными shortcuts

---

## 13. Non-Goals

Приложение **не** предназначено для:
- Постоянного мониторинга всех нажатий клавиш (keyboard sniffing)
- Замены стандартного переключения раскладок
- Выполнения сложного редактирования текста
- Автоматического определения языка без участия пользователя

---

## 14. Distribution

| Channel       | Status    | Notes                                             |
|--------------|-----------|---------------------------------------------------|
| GitHub       | v1        | Open source release                               |
| Homebrew     | v2        | After stable release                              |
| Mac App Store | Potential | Требует отсутствия keyboard sniffing — уже учтено |

---

## 15. Version Roadmap

### v1 (MVP)
- [ ] Fix last word (no selection)
- [ ] Fix selected text
- [ ] RU ↔ EN explicit pair
- [ ] Menubar icon
- [ ] Audio + visual feedback
- [ ] Accessibility permission onboarding

### v2
- [ ] Fix last token (full fragment, not just word)
- [ ] System Input Sources mode
- [ ] Auto switch layout after conversion
- [ ] Configurable hotkey
- [ ] Custom sound selection