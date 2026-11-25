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
    enum FeedbackTransition {
        static let duration: TimeInterval = 0.16

        static func progress(_ fraction: CGFloat) -> CGFloat {
            let remaining = 1 - fraction
            return 1 - remaining * remaining * remaining
        }
    }

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
        static let shortcutEditorWidth: CGFloat = 540
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
        static let stateDetailText = NSColor(name: "StateDetailText") { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let contrast = appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua
            ])
            if contrast == .accessibilityHighContrastAqua || contrast == .accessibilityHighContrastDarkAqua {
                return dark ? .white : .black
            }
            let gray: CGFloat = dark ? 0.72 : 0.38
            return NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1)
        }
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
    static func configureCompactButton(_ button: NSButton) {
        button.controlSize = .small
        button.bezelStyle = .rounded
        button.isBordered = true
        button.font = Font.controlLabel
    }

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
        private(set) var isTrackingMouseMenu = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            let previousRing = focusRingType
            isTrackingMouseMenu = true
            defer {
                isTrackingMouseMenu = false
                focusRingType = previousRing
            }
            focusRingType = .none
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
            if let window, window.firstResponder === self {
                window.makeFirstResponder(nil)
            }
        }
    }

    static func restorableControl(in window: NSWindow) -> NSControl? {
        let responder = window.firstResponder as? NSControl
        // The gear has temporary focus while tracking a mouse-opened menu.
        if (responder as? SettingsMenuButton)?.isTrackingMouseMenu == true { return nil }
        return responder
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

/// The feedback and the window share one transition so the capture field stays anchored.
@MainActor
final class ShortcutFeedbackLayout {
    enum Style { case error, warning, information }

    let slot = NSView()
    let banner = NSBox()
    let label = NSTextField(wrappingLabelWithString: "")

    private let icon = NSImageView()
    private let bannerTopInset: CGFloat = 8
    private lazy var slotHeight = slot.heightAnchor.constraint(equalToConstant: 0)
    private lazy var bannerHeight = banner.heightAnchor.constraint(equalToConstant: 0)
    private var targetHeight: CGFloat = 0
    private var transition: Timer?

    init() {
        slot.wantsLayer = true
        slot.layer?.masksToBounds = true
        banner.boxType = .custom
        banner.titlePosition = .noTitle
        banner.cornerRadius = 9
        banner.wantsLayer = true
        banner.layer?.masksToBounds = true
        banner.contentViewMargins = .zero
        banner.isHidden = true
        banner.alphaValue = 0
        banner.translatesAutoresizingMaskIntoConstraints = false
        slot.addSubview(banner)

        let content = banner.contentView!
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        icon.setAccessibilityElement(false)
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(icon)
        content.addSubview(label)
        NSLayoutConstraint.activate([
            slotHeight, bannerHeight,
            banner.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            banner.topAnchor.constraint(equalTo: slot.topAnchor, constant: bannerTopInset),
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
    }

    func show(_ title: String, detail: String?, style: Style) {
        let (color, symbol): (NSColor, String) = switch style {
        case .error: (.systemRed, "exclamationmark.circle.fill")
        case .warning: (.systemOrange, "exclamationmark.triangle.fill")
        case .information: (.systemBlue, "info.circle.fill")
        }
        banner.fillColor = color.withAlphaComponent(0.10)
        banner.borderColor = color.withAlphaComponent(0.35)
        banner.borderWidth = style == .information ? 1 : 0
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = color
        let message = NSMutableAttributedString(string: title, attributes: [
            .font: detail == nil ? AppStyle.Font.body : AppStyle.Font.sectionTitle,
            .foregroundColor: NSColor.labelColor
        ])
        if let detail {
            message.append(NSAttributedString(string: "\n" + detail, attributes: [
                .font: AppStyle.Font.supportingText,
                .foregroundColor: AppStyle.Color.stateDetailText
            ]))
        }
        label.attributedStringValue = message
        label.toolTip = message.string
        slot.window?.contentView?.layoutSubtreeIfNeeded()
        // NSTextField uses a two-point text inset on each side.
        let bounds = message.boundingRect(
            with: NSSize(width: max(1, label.bounds.width - 4), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        banner.isHidden = false
        resize(to: ceil(bounds.height) + 16 + bannerTopInset)
    }

    func hide() {
        resize(to: 0)
    }

    private func resize(to height: CGFloat) {
        guard let window = slot.window, targetHeight != height else { return }
        targetHeight = height
        transition?.invalidate()
        transition = nil
        let startHeight = slotHeight.constant
        let startOpacity = banner.alphaValue
        let endOpacity: CGFloat = height > 0 ? 1 : 0
        let compactWindowHeight = window.frame.height - startHeight

        let update: (CGFloat) -> Void = { [weak self, weak window] progress in
            guard let self, let window else { return }
            banner.alphaValue = startOpacity + (endOpacity - startOpacity) * progress
            slotHeight.constant = (startHeight + (height - startHeight) * progress).rounded()
            bannerHeight.constant = max(0, slotHeight.constant - bannerTopInset)
            resizeWindow(window, height: compactWindowHeight + slotHeight.constant)
            window.contentView?.layoutSubtreeIfNeeded()
            if progress == 1 && height == 0 {
                banner.isHidden = true
                label.stringValue = ""
                label.toolTip = nil
            }
            window.displayIfNeeded()
        }

        guard window.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            update(1)
            return
        }
        let start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak window] timer in
            MainActor.assumeIsolated {
                guard let self, let window else { timer.invalidate(); return }
                let fraction = window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    ? min((ProcessInfo.processInfo.systemUptime - start) / AppStyle.FeedbackTransition.duration, 1)
                    : 1
                update(AppStyle.FeedbackTransition.progress(fraction))
                if fraction == 1 {
                    timer.invalidate()
                    self.transition = nil
                }
            }
        }
        transition = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func resizeWindow(_ window: NSWindow, height: CGFloat) {
        var frame = window.frame
        frame.size.height = height
        frame.origin.y = window.frame.maxY - height
        let visibleFrame = window.isVisible ? (window.screen ?? NSScreen.main)?.visibleFrame : nil
        if let visibleFrame, window.sheetParent == nil {
            frame.origin.y = max(frame.minY, visibleFrame.minY)
        }
        window.setFrame(frame, display: false)

        // AppKit positions a sheet relative to its parent, so move the parent
        // only if the actual sheet frame would leave its actions below the screen.
        guard let visibleFrame, let parent = window.sheetParent else { return }
        let overflow = visibleFrame.minY - window.frame.minY
        let roomAboveParent = visibleFrame.maxY - parent.frame.maxY
        let shift = min(overflow, roomAboveParent)
        if shift > 0 {
            parent.setFrameOrigin(NSPoint(x: parent.frame.minX, y: parent.frame.minY + shift))
        }
    }
}
