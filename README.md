<!-- SPDX-FileCopyrightText: 2026 Vitalik Makhnev -->
<!-- SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0 -->

# Language Switcher Plus

Language Switcher Plus lets you switch input languages with a quick Fn/Globe or Command tap and fix text typed in the wrong layout or case with customizable global shortcuts.

Having trouble with selected-text actions in professional code editors such as JetBrains IDEs or Visual Studio Code? [Compare Plus and Dev](#plus-or-dev).

[Download the latest release](https://github.com/makhnevvitalik/LanguageSwitcherPlus/releases/latest)

## Contents

- [English](#english)
  - [Features](#features)
  - [Plus or Dev?](#plus-or-dev)
  - [Install and start](#install-and-start)
  - [Permissions](#permissions)
  - [Text actions](#text-actions)
  - [License](#license)
- [Русский](#русский)
  - [Возможности](#возможности)
  - [Plus или Dev?](#plus-или-dev)
  - [Установка и запуск](#установка-и-запуск)
  - [Разрешения](#разрешения)
  - [Действия с текстом](#действия-с-текстом)
  - [Лицензия](#лицензия)

## English

### Features

- Switch between selected macOS input sources with Fn/Globe, Command, or both.
- Choose which input sources participate in switching and text conversion.
- Convert text typed in the wrong keyboard layout.
- Change text to Uppercase, Lowercase, Capitalize Words, or Invert Case.
- Assign global shortcuts using modifiers, F1–F20, letters, and digits with Once, Twice, and Hold + twice press patterns.
- Apply shortcut actions to recently typed text, the last word, or selected text.

### Plus or Dev?

Plus is recommended for most users: macOS limits the app’s access to the system and personal data. If selected-text actions do not work in professional code editors such as JetBrains IDEs or Visual Studio Code, try [Language Switcher Dev](https://github.com/makhnevvitalik/LanguageSwitcherDev). It has broader access to other apps and therefore runs without App Sandbox. Both editions otherwise offer the same features.

### Install and start

Language Switcher Plus requires macOS 14 or later.

1. Download the `.dmg` file from the [latest release](https://github.com/makhnevvitalik/LanguageSwitcherPlus/releases/latest).
2. Open the downloaded file and drag **Language Switcher Plus.app** to **Applications**.
3. Open the app from **Applications** or Spotlight to show its settings window. The menu bar icon opens the quick panel when visible.
4. Under **Keyboard switching**, choose active inputs and enable Fn/Globe, Command, or both.
5. Grant the permissions requested by the app.

#### First-launch notes

- Use the gear menu to change the interface language, enable **Open at Login**, or toggle **Show in Menu Bar**.
- Closing the settings window leaves the app running. With **Open at Login** enabled, it starts in the background. If the menu bar icon is hidden or there is no room for it, open the app from **Applications** or Spotlight to return to settings.
- Plus checks GitHub in the background at launch and every 24 hours while running. A blue dot on the menu bar icon signals an update. The orange Input Monitoring warning takes priority. The **Update available** link in the panel and settings window opens the release page. To check manually, choose **Settings → About… → Check for Updates**.
- The release also includes a ZIP archive if you prefer to unzip the app manually and move it to **Applications**.
- macOS may block the first launch because the app is distributed independently rather than through the App Store. If this happens, try opening the app once, then go to **System Settings → Privacy & Security**, find the security message for Language Switcher Plus, and select **Open Anyway**.
- When using Fn/Globe, set its macOS action to **Do Nothing** under Keyboard settings so the system action does not conflict with Language Switcher Plus.

### Permissions

| Permission | Used for |
| --- | --- |
| **Input Monitoring** | Language switching and global shortcuts |
| **Accessibility** | Intercepting assigned letter and digit shortcuts, reading and replacing text |

If Input Monitoring is paused, a dot appears on the menu bar icon and a warning appears in the settings. Use **Resume…** to review your next step. If macOS asks, choose **Quit & Reopen**, then start the action again.

### Text actions

Quick example: assign a shortcut to **Convert Layout**, type text using the wrong keyboard layout, and press the shortcut. Language Switcher Plus will correct the text you just typed.

#### Configure shortcuts

Text action shortcuts run **Convert Layout**, **Uppercase**, **Lowercase**, **Capitalize Words**, or **Invert Case** without opening the menu.

Open **Text actions → Shortcuts → Configure…** to assign shortcuts. Use Shift, Control, Option, Command, or F1–F20. Letters and digits require Control, Option, or Command, with optional Shift. Their labels follow the physical positions on a US keyboard. No text-action shortcuts are assigned by default.

With Accessibility enabled, Language Switcher intercepts the letter or digit in an assigned combination from the first press, including for double presses. This keeps the active app from running its own command on the same keys and lets Language Switcher act on recently typed text. The editor blocks shortcuts reported as enabled by macOS. For other standard macOS shortcuts and common app commands, it shows a warning below the recorded keys. To proceed, choose **Assign Anyway**. To use different keys, record another combination. Warnings about app commands use the active keyboard layout.

#### Press patterns

- **Once** — press and release the shortcut once. Example: press and release `⇧⌥`.
- **Twice** — press and release the entire shortcut twice. Example: press `⇧⌥`, release it, then press and release `⇧⌥` again.
- **Hold + twice** — hold one or more modifiers and tap another modifier, a function key, a letter, or a digit twice. For example, hold `⇧` and tap `⌥` twice, or hold `⌃` and tap `K` twice.

Which key you hold matters: holding `⇧` and tapping `⌥` is different from holding `⌥` and tapping `⇧`.

Once and Twice may use the same keys for different actions. In that case, the Once action waits for the configured double-press interval. If no Twice action uses those keys, Once runs immediately after release.

#### Apply to

**Apply to** determines which text a shortcut action targets:

- **Typed text** — all tracked typed text.
- **Last word** — only the most recently typed word.
- **Selection** — selected text.

In **Typed text** and **Last word**, the shortcut uses tracked text when available and falls back to the selection. Selecting with the mouse or standard keyboard shortcuts usually clears the tracked text. Menu actions always target the selection.

### License

Language Switcher Plus is source-available under the [MIT License with the Commons Clause License Condition v1.0](LICENSE). You may use, modify, and redistribute original or modified builds at no charge. Selling the software—including paid distribution through an app store—or a product or service whose value derives substantially from it is prohibited.

Bundled FrequencyWords data is licensed separately under CC BY-SA 4.0. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution and third-party license details.

## Русский

Language Switcher Plus позволяет быстро переключать языки ввода нажатием Fn/Globe или Command и исправлять текст, набранный в неверной раскладке или регистре, с помощью настраиваемых глобальных сочетаний клавиш.

Возникли проблемы с действиями над выделенным текстом в профессиональных редакторах кода, например в IDE от JetBrains или Visual Studio Code? [Сравните Plus и Dev](#plus-или-dev).

[Скачать последнюю версию](https://github.com/makhnevvitalik/LanguageSwitcherPlus/releases/latest)

### Возможности

- Переключение между выбранными источниками ввода macOS с помощью Fn/Globe, Command или обеих клавиш.
- Выбор источников ввода, участвующих в переключении и преобразовании текста.
- Исправление текста, набранного в неверной раскладке.
- Преобразование текста в верхний и нижний регистр, написание слов с прописной буквы или инвертирование регистра.
- Настраиваемые глобальные сочетания из модификаторов, F1–F20, букв и цифр с вариантами «Один раз», «Дважды» и «Удержание + двойное нажатие».
- Применение действий к недавно набранному тексту, последнему слову или выделенному тексту.

### Plus или Dev?

Для большинства пользователей подходит Plus: macOS ограничивает доступ приложения к системе и личным данным. Если действия с выделенным текстом не работают в профессиональных редакторах кода, например в IDE от JetBrains или Visual Studio Code, попробуйте [Language Switcher Dev](https://github.com/makhnevvitalik/LanguageSwitcherDev). Она получает более широкий доступ к другим приложениям и поэтому работает без App Sandbox. В остальном возможности обеих редакций одинаковы.

### Установка и запуск

Language Switcher Plus требует macOS 14 или новее.

1. Скачайте файл `.dmg` из [последнего релиза](https://github.com/makhnevvitalik/LanguageSwitcherPlus/releases/latest).
2. Откройте скачанный файл и перетащите **Language Switcher Plus.app** в папку **Applications**.
3. Откройте приложение из папки **«Программы»** или через Spotlight, чтобы показать окно настроек. Значок в строке меню открывает быструю панель, когда он виден.
4. В разделе **Переключение раскладки** выберите используемые источники и включите Fn/Globe, Command или обе клавиши.
5. Предоставьте запрошенные приложением разрешения.

#### Первый запуск

- В меню шестерёнки можно выбрать **Язык**, включить **Запускать при входе** и управлять настройкой **Показывать в строке меню**.
- После закрытия окна настроек приложение продолжает работать. Если включено открытие при входе, приложение запускается в фоне. Если значок скрыт или для него нет места, откройте приложение из папки **«Программы»** или через Spotlight, чтобы вернуться к настройкам.
- Plus проверяет GitHub в фоне при запуске и каждые 24 часа, пока приложение запущено. Синяя точка на значке в строке меню сообщает о новой версии. Оранжевое предупреждение Input Monitoring имеет приоритет. Ссылка **Доступно обновление** в панели и окне настроек открывает страницу релиза. Для ручной проверки выберите **Настройки → О приложении… → Проверить обновления**.
- В релиз также входит ZIP-архив: его можно распаковать вручную и переместить приложение в **Applications**.
- При первом запуске macOS может заблокировать приложение, поскольку оно распространяется самостоятельно, а не через App Store. В таком случае попробуйте один раз открыть приложение, затем перейдите в **Системные настройки → Конфиденциальность и безопасность**, найдите сообщение о Language Switcher Plus и выберите **Всё равно открыть**.
- При использовании Fn/Globe установите для неё действие **Ничего не делать** в настройках клавиатуры macOS, чтобы системное действие не конфликтовало с Language Switcher Plus.

### Разрешения

| Разрешение | Для чего используется |
| --- | --- |
| **Мониторинг ввода** | Переключение языка и глобальные сочетания |
| **Универсальный доступ** | Перехват назначенных сочетаний с буквами и цифрами, чтение и замена текста |

Если мониторинг ввода приостановлен, на значке в строке меню появляется точка, а в настройках — предупреждение. Нажмите **Возобновить…**, чтобы узнать, что делать дальше. Если macOS предложит действие **Завершить и открыть снова**, выберите его, а затем повторите нужное действие.

### Действия с текстом

Простой пример: назначьте сочетание для действия **Сменить раскладку**, наберите текст в неправильной раскладке и нажмите сочетание. Language Switcher Plus исправит только что набранный текст.

#### Настройка сочетаний

Сочетания позволяют запускать действия **Сменить раскладку**, **Верхний регистр**, **Нижний регистр**, **С прописной буквы** и **Инвертировать регистр**, не открывая меню.

Откройте **Действия с текстом → Сочетания клавиш → Настроить…**, чтобы назначить сочетания. Поддерживаются Shift, Control, Option, Command и F1–F20. Для букв и цифр нужен Control, Option или Command. К ним можно добавить Shift. Подписи букв и цифр соответствуют физическим позициям на американской клавиатуре. По умолчанию сочетания для действий с текстом не назначены.

С разрешением «Универсальный доступ» Language Switcher перехватывает букву или цифру в назначенном сочетании с первого нажатия, в том числе для двойного жеста. Благодаря этому активное приложение не выполняет свою команду на этих клавишах, а Language Switcher может обработать недавно набранный текст. Редактор блокирует сочетания, которые macOS сообщает как включённые. Для остальных стандартных сочетаний macOS и распространённых команд приложений под полем записи появляется предупреждение. Чтобы продолжить, нажмите **Назначить всё равно**. Чтобы выбрать другие клавиши, запишите новое сочетание. Для предупреждений о командах приложений учитывается активная раскладка.

#### Варианты нажатия

- **Один раз** — один раз нажмите и отпустите сочетание. Пример: нажмите и отпустите `⇧⌥`.
- **Дважды** — дважды полностью нажмите и отпустите сочетание. Пример: нажмите `⇧⌥`, отпустите, затем снова нажмите и отпустите `⇧⌥`.
- **Удержание + двойное нажатие** — удерживайте один или несколько модификаторов и дважды нажмите другой модификатор, функциональную клавишу, букву или цифру. Например, удерживайте `⇧` и дважды нажмите `⌥` или удерживайте `⌃` и дважды нажмите `K`.

Важно, какую клавишу вы удерживаете: удерживать `⇧` и нажимать `⌥` — не то же самое, что удерживать `⌥` и нажимать `⇧`.

Для разных действий можно назначить варианты **Один раз** и **Дважды** с одинаковыми клавишами. В этом случае действие «Один раз» ждёт окончания настроенного интервала двойного нажатия. Если для этих клавиш нет действия «Дважды», «Один раз» выполняется сразу после отпускания.

#### Обрабатывать

Настройка **Обрабатывать** определяет, к какому тексту применяется действие по сочетанию:

- **Набранное** — весь отслеживаемый набранный текст.
- **Последнее слово** — только последнее введённое слово.
- **Выделение** — выделенный текст.

В режимах **Набранное** и **Последнее слово** сочетание сначала использует отслеживаемый текст и обращается к выделению, если подходящего набранного текста нет. Выделение мышью или стандартными сочетаниями клавиш обычно очищает буфер набранного текста. Действия из меню всегда применяются к выделению.

### Лицензия

Исходный код Language Switcher Plus доступен по [лицензии MIT с условием Commons Clause License Condition v1.0](LICENSE). Оригинальные и изменённые сборки можно использовать, изменять и распространять бесплатно. Продажа программы, включая платное распространение через магазины приложений, а также продуктов или услуг, ценность которых в значительной степени основана на ней, запрещена.

Встроенные данные FrequencyWords распространяются отдельно по лицензии CC BY-SA 4.0. Авторские сведения и условия сторонних лицензий приведены в [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
