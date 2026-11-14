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

        // Полное название продукта в основной шапке.
        static let appName = NSFont.systemFont(ofSize: 16, weight: .semibold)
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
        // кнопки диалога и выпадающие списки. Regular 13, независимо от оформления кнопки.
        // Действие, встроенное в строку пояснения, может использовать роль этой строки.
        static let controlLabel = body
        static let metadata = supportingText
        static let secondaryAction = supportingText
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

    enum Icon {
        static let brandSize = NSSize(width: 40, height: 40)
        static let brandVisibleFraction: CGFloat = 0.80
        static let menuBarSize = NSSize(width: 18, height: 18)
        static let settingsPointSize: CGFloat = 16

        static func brandImage(_ artwork: NSImage, size: NSSize) -> NSImage {
            // Normalized bounds of the solid silhouette, measured without its shadow.
            let silhouette = NSRect(x: 0.10, y: 0.107, width: 0.80, height: 0.80)
            return NSImage(size: size, flipped: false) { rect in
                let side = min(rect.width, rect.height) * brandVisibleFraction
                let scale = side / max(silhouette.width, silhouette.height)
                artwork.draw(in: NSRect(x: rect.midX - silhouette.midX * scale,
                                        y: rect.midY - silhouette.midY * scale,
                                        width: scale, height: scale))
                return true
            }
        }

    }

    enum Layout {
        static let panelInset: CGFloat = 10
        static let cardSpacing: CGFloat = 8
        static let cardInset: CGFloat = 14
        static let cardCornerRadius: CGFloat = 11
        static let sectionHeaderHeight: CGFloat = 30
        static let detailedRowHeight: CGFloat = 46
        static let rowHeight: CGFloat = 40
        static let rowItemSpacing: CGFloat = 10
        static let headerIconFrame: CGFloat = 40
        static let headerHeight: CGFloat = 44
        static let headerItemSpacing: CGFloat = 10
        static let headerHorizontalInset: CGFloat = 4
        static let headerVersionSpacing: CGFloat = 6
        static let headerStatusSpacing: CGFloat = 1
        static let headerStatusHeight: CGFloat = 16
        static let settingsButtonSize = NSSize(width: 34, height: 30)
        static let windowInset: CGFloat = 24
        static let windowTopInset: CGFloat = 20
    }

    enum AboutLayout {
        static let width: CGFloat = 400
        static let iconSize: CGFloat = 56
        static let headerSpacing: CGFloat = 14
        static let versionSpacing: CGFloat = 4
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
        static let cardBackground = NSColor.controlBackgroundColor
        static let inactiveControl = NSColor.tertiaryLabelColor.withAlphaComponent(0.45)

        static func compactSelectionBackground(accent: NSColor = .controlAccentColor) -> NSColor {
            guard let rgb = accent.usingColorSpace(.sRGB) else {
                return NSColor(srgbRed: 0, green: 0.39, blue: 0.82, alpha: 1)
            }
            func linear(_ channel: CGFloat) -> CGFloat {
                let component = min(max(channel, 0), 1)
                return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            let red = linear(rgb.redComponent)
            let green = linear(rgb.greenComponent)
            let blue = linear(rgb.blueComponent)
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            // Keep white text at 4.5:1 by lowering luminance while preserving the accent's hue.
            let maximumLuminance = 1.05 / 4.5 - 0.05
            guard luminance > maximumLuminance else { return rgb }
            let scale = maximumLuminance / luminance
            func srgb(_ component: CGFloat) -> CGFloat {
                let value = component * scale
                return value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
            }
            return NSColor(srgbRed: srgb(red), green: srgb(green), blue: srgb(blue), alpha: 1)
        }
    }
}

extension AppStyle {
    static func showWithoutInitialControlFocus(_ window: NSWindow) {
        let wasVisible = window.isVisible
        window.makeKeyAndOrderFront(nil)
        if !wasVisible {
            window.makeFirstResponder(nil)
        }
    }

    static func clearUnchangedFocus(in window: NSWindow, after event: NSEvent, previous: NSResponder?) {
        guard event.type == .leftMouseDown || event.type == .rightMouseDown,
              window.isVisible, window.firstResponder === previous,
              (previous as? NSTextView)?.isFieldEditor != true else { return }
        window.makeFirstResponder(nil)
    }

    final class SettingsWindow: NSWindow {
        override func sendEvent(_ event: NSEvent) {
            let previous = firstResponder
            super.sendEvent(event)
            AppStyle.clearUnchangedFocus(in: self, after: event, previous: previous)
        }
    }

    final class InformationWindow: NSWindow {
        override func sendEvent(_ event: NSEvent) {
            super.sendEvent(event)
            if event.type == .leftMouseDown, isVisible {
                makeFirstResponder(nil)
            }
        }
    }

    final class SettingsMenuButton: NSPopUpButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            let previousRing = focusRingType
            focusRingType = .none
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
            if let window, window.firstResponder === self {
                window.makeFirstResponder(nil)
            }
            focusRingType = previousRing
        }
    }

    static func makeAboutIdentityView(name: String, availableWidth: CGFloat) -> NSStackView {
        let title = NSTextField(wrappingLabelWithString: name)
        title.isSelectable = false
        title.font = Font.windowTitle
        title.preferredMaxLayoutWidth = availableWidth

        let stack = NSStackView(views: [title])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = AboutLayout.versionSpacing
        title.widthAnchor.constraint(lessThanOrEqualToConstant: availableWidth).isActive = true

        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            let label = NSTextField(wrappingLabelWithString: version)
            label.isSelectable = false
            label.font = Font.metadata
            label.textColor = .secondaryLabelColor
            label.preferredMaxLayoutWidth = availableWidth
            label.lineBreakMode = .byCharWrapping
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(lessThanOrEqualToConstant: availableWidth).isActive = true
        }
        return stack
    }

    static func sizeAboutWindow(_ window: NSWindow, to contentStack: NSStackView) {
        window.contentView?.layoutSubtreeIfNeeded()
        let height = ceil(contentStack.fittingSize.height + Layout.windowTopInset + AboutLayout.bottomInset)
        let frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: AboutLayout.width, height: height))
        if window.frame.size != frame.size {
            window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - frame.height,
                                   width: frame.width, height: frame.height), display: window.isVisible)
        }
    }
}
