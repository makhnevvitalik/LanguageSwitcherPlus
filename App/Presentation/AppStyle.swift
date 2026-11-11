// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit

// Правила применения типографики для Language Switcher Plus/Dev и Wakecup:
// • Роль выбирается по задаче текста и уровню вёрстки, включая соседние элементы.
//   Тип кнопки (.link/.bordered), цвет и расположение справа сами по себе не задают размер.
// • Font описывает только шрифт. Цвет, размеры контрола и отступы задаются отдельно.
// • Общие роли сохраняют одинаковые имена и параметры между приложениями.
//   Роли могут ссылаться на одну базу, сохраняя отдельный смысл (например, fieldLabel).
// • Своя роль допустима для отдельного типа содержимого/ввода. В комментарии указываем
//   назначение, пример и правила состояний; используем существующую шкалу, где она подходит.
// • Новую роль не создаём только ради другого окна. Сначала проверяем существующие роли.
// • Для нового использования проверяем RU/EN, длинный текст, фокус и ошибку ввода.
//   Системные диалоги и внутреннюю типографику нативных виджетов оставляем системе.
@MainActor
enum AppStyle {
    enum Font {
        // Основной текст: подписи строк главного меню, описание, версия, автор и лицензия.
        // Regular 13. Короткая подпись поля в редакторе использует fieldLabel.
        static let body = NSFont.systemFont(ofSize: 13)
        // Акцент в основном тексте: название действия в списке сочетаний.
        // Medium 13. База для ролей той же выразительности, без увеличения размера.
        static let emphasizedBody = NSFont.systemFont(ofSize: 13, weight: .medium)

        // Имя продукта в шапке меню и About: «Language Switcher».
        // Semibold 16. Это идентичность приложения, а не заголовок произвольного окна.
        static let appName = NSFont.systemFont(ofSize: 16, weight: .semibold)
        // Название редакции непосредственно под именем продукта: Plus / Developer Edition.
        // Medium 13. Сохраняем отдельную роль, хотя параметры совпадают с emphasizedBody.
        static let appEdition = emphasizedBody
        // Главный заголовок отдельного окна: лицензии, настройки или редактор сочетания.
        // Semibold 20. Заголовки групп внутри окна используют sectionTitle.
        static let windowTitle = NSFont.systemFont(ofSize: 20, weight: .semibold)
        // Заголовок группы настроек или раздела инструкции: «Основные».
        // Medium 13. Применяется одинаково в основном интерфейсе и вспомогательных окнах.
        static let sectionTitle = emphasizedBody
        // Имя поля редактора: «Сочетание», «Способ нажатия».
        // Medium 13. Обычные подписи строк меню остаются body.
        static let fieldLabel = emphasizedBody

        // Пояснение к строке, инструкция под полем или подробность ошибки ввода.
        // Regular 12. Серый цвет сам по себе не повод уменьшать основной текст до 12.
        static let supportingText = NSFont.systemFont(ofSize: 12)
        // Подпись обычного действия/значения: «Настроить…», «О приложении», GitHub,
        // кнопки диалога, список и сегменты. Regular 13, независимо от оформления кнопки.
        // Действие, встроенное в строку пояснения, может использовать роль этой строки.
        static let controlLabel = body
        // Краткий статус объекта или результат операции: «Установлена последняя версия».
        // Regular 13. Цвет успеха/ошибки задаётся отдельно; он не меняет шрифт.
        static let statusText = body
        // Короткие подписи компактных кнопок выбора: ⌘, fn, EN, RU.
        // Medium 12. Не применяется к обычным текстовым действиям вроде «Настроить…».
        static let compactControlLabel = NSFont.systemFont(ofSize: 12, weight: .medium)
        // Пример преобразования текста под названием действия: «ghbdtn → привет».
        // Monospaced regular 12. Это образец текста, а не значение поля сочетания.
        static let textExample = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        // Записанное сочетание или удерживаемые модификаторы в области записи: «⌥ ⇧ F1».
        // Monospaced medium 16. Приглашение к вводу в той же области использует body.
        static let shortcutValue = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
    }

    enum Layout {
        static let windowInset: CGFloat = 24
        static let windowTopInset: CGFloat = 20
    }

    enum AboutLayout {
        static let width: CGFloat = 400
        static let height: CGFloat = 216
        static let iconSize: CGFloat = 56
        static let headerSpacing: CGFloat = 14
        static let contentSpacing: CGFloat = 8
        static let actionSpacing: CGFloat = 12
        static let statusHeight: CGFloat = 16
        static let statusFooterSpacing: CGFloat = 6
        static let updateButtonWidth: CGFloat = 170
        static let bottomInset: CGFloat = 16
    }

    enum Color {
        static let success = NSColor(name: "SuccessStatus") { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(calibratedRed: 0.44, green: 0.79, blue: 0.55, alpha: 1)
            }
            return NSColor(calibratedRed: 0.10, green: 0.43, blue: 0.23, alpha: 1)
        }
        static let activeControl = NSColor.controlAccentColor
        static let inactiveControl = NSColor.tertiaryLabelColor.withAlphaComponent(0.45)
    }
}
