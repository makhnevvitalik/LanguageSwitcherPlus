// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import LanguageSwitcherApplication
import LanguageSwitcherDomain

@MainActor
final class TextShortcutSettingsWindowController: NSObject, NSWindowDelegate {
    private static let windowWidth: CGFloat = 780
    private let shortcut: (TextAction) -> TextActionShortcut?
    private let validateShortcut: (
        TextActionShortcut,
        TextAction
    ) -> TextActionShortcutValidationResult
    private let setShortcut: (TextActionShortcut?, TextAction, TextShortcutConflict?) -> ConfigureTextActionShortcutResult
    private let onRecordingChanged: (Bool) -> Void
    private var settingsWindow: NSWindow?
    private var editor: TextShortcutEditorSheetController?
    private var returnToSource: (() -> Void)?

    init(
        shortcut: @escaping (TextAction) -> TextActionShortcut?,
        validateShortcut: @escaping (
            TextActionShortcut,
            TextAction
        ) -> TextActionShortcutValidationResult,
        setShortcut: @escaping (TextActionShortcut?, TextAction, TextShortcutConflict?) -> ConfigureTextActionShortcutResult,
        onRecordingChanged: @escaping (Bool) -> Void
    ) {
        self.shortcut = shortcut
        self.validateShortcut = validateShortcut
        self.setShortcut = setShortcut
        self.onRecordingChanged = onRecordingChanged
    }

    func showWindow(returningTo source: (() -> Void)? = nil) {
        if settingsWindow == nil {
            settingsWindow = makeWindow()
        }
        if let source { returnToSource = source }
        if settingsWindow?.isVisible != true {
            refreshContent()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        editor?.cancel()
        editor = nil
        if let returnToSource {
            self.returnToSource = nil
            DispatchQueue.main.async { [weak self] in
                guard self?.settingsWindow?.isVisible == false else { return }
                returnToSource()
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let window = AppStyle.SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 336),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = localized("Text action shortcuts")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func refreshContent(focusingActionAt focusedIndex: Int? = nil) {
        guard let window = settingsWindow else { return }

        let content = ShortcutSettingsContentView()
        let title = NSTextField(labelWithString: localized("Text action shortcuts"))
        title.font = AppStyle.Font.windowTitle

        var editButtons: [NSButton] = []
        var rowButtons: [NSButton] = []
        var shortcutLabels: [NSTextField] = []
        let actionWidth: CGFloat = 190
        let rowSpacing = AppStyle.Layout.rowItemSpacing
        let rows = TextAction.allCases.enumerated().map { index, action -> NSView in
            let configured = shortcut(action)
            let actionLabel = NSTextField(labelWithString: action.title)
            actionLabel.font = AppStyle.Font.emphasizedBody
            let exampleLabel = NSTextField(labelWithString: action.example)
            exampleLabel.font = AppStyle.Font.textExample
            exampleLabel.textColor = .secondaryLabelColor
            let actionLabels = NSStackView(views: [actionLabel, exampleLabel])
            actionLabels.orientation = .vertical
            actionLabels.alignment = .leading
            actionLabels.spacing = 2

            let shortcutLabel = NSTextField(wrappingLabelWithString: TextActionShortcutFormatter.string(for: configured))
            shortcutLabel.textColor = configured == nil ? .secondaryLabelColor : AppStyle.Color.stateDetailText
            shortcutLabel.font = AppStyle.Font.controlLabel
            shortcutLabel.lineBreakMode = .byWordWrapping
            shortcutLabel.alignment = .center
            shortcutLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            shortcutLabels.append(shortcutLabel)

            let setButton = NSButton(
                title: configured == nil ? localized("Set…") : localized("Change…"),
                target: self,
                action: #selector(editShortcut(_:))
            )
            AppStyle.configureCompactButton(setButton)
            setButton.tag = index

            let clearButton = NSButton(
                title: localized("Clear"),
                target: self,
                action: #selector(clearShortcut(_:))
            )
            AppStyle.configureCompactButton(clearButton)
            clearButton.tag = index
            clearButton.isEnabled = configured != nil

            editButtons.append(setButton)
            rowButtons.append(contentsOf: [setButton, clearButton])
            let row = NSStackView(views: [actionLabels, shortcutLabel, setButton, clearButton])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.spacing = rowSpacing
            actionLabels.widthAnchor.constraint(equalToConstant: actionWidth).isActive = true
            return row
        }

        let buttonWidth = ceil(rowButtons.map(\.intrinsicContentSize.width).max() ?? 0)
        for button in rowButtons {
            button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
        }
        let valueWidth = Self.windowWidth - 2 * AppStyle.Layout.windowInset - actionWidth - 3 * rowSpacing - 2 * buttonWidth
        for label in shortcutLabels {
            label.preferredMaxLayoutWidth = valueWidth
        }

        let rowsStack = NSStackView(views: rows)
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 14
        for row in rows {
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }

        let stack = NSStackView(views: [title, rowsStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: AppStyle.Layout.windowInset),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -AppStyle.Layout.windowInset),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: AppStyle.Layout.windowTopInset),
            rowsStack.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.contentView = content
        window.initialFirstResponder = content
        window.autorecalculatesKeyViewLoop = false
        let keyViews: [NSView] = [content] + rowButtons
        for (view, next) in zip(keyViews, keyViews.dropFirst() + [content]) {
            view.nextKeyView = next
        }
        if let focusedIndex, editButtons.indices.contains(focusedIndex) {
            window.makeFirstResponder(editButtons[focusedIndex])
        } else {
            window.makeFirstResponder(content)
        }
    }

    @objc private func editShortcut(_ sender: NSButton) {
        guard let window = settingsWindow,
              editor == nil,
              TextAction.allCases.indices.contains(sender.tag) else {
            return
        }
        let action = TextAction.allCases[sender.tag]
        let editor = TextShortcutEditorSheetController(
            action: action,
            currentShortcut: shortcut(action),
            shortcuts: { [shortcut] in
                Dictionary(uniqueKeysWithValues: TextAction.allCases.compactMap { action in
                    shortcut(action).map { (action, $0) }
                })
            },
            validate: { [validateShortcut] newShortcut in
                validateShortcut(newShortcut, action)
            },
            save: { [setShortcut] newShortcut, reviewedConflict in
                setShortcut(newShortcut, action, reviewedConflict)
            },
            onRecordingChanged: onRecordingChanged,
            onFinish: { [weak self, weak sender] didSave in
                guard let self else { return }
                self.editor = nil
                if didSave {
                    self.refreshContent(focusingActionAt: TextAction.allCases.firstIndex(of: action))
                } else if let sender, sender.window?.isVisible == true {
                    sender.window?.makeFirstResponder(sender)
                }
            }
        )
        self.editor = editor
        editor.beginSheet(for: window)
    }

    @objc private func clearShortcut(_ sender: NSButton) {
        guard TextAction.allCases.indices.contains(sender.tag) else { return }
        let action = TextAction.allCases[sender.tag]
        if setShortcut(nil, action, nil) == .updated {
            refreshContent(focusingActionAt: sender.tag)
        }
    }
}

private final class ShortcutSettingsContentView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { false }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 48 else {
            super.keyDown(with: event)
            return
        }
        if event.modifierFlags.contains(.shift) {
            window?.selectPreviousKeyView(self)
        } else {
            window?.selectNextKeyView(self)
        }
    }
}

@MainActor
enum TextActionShortcutFormatter {
    static func string(for shortcut: TextActionShortcut?) -> String {
        guard let shortcut else { return localized("Not Set") }
        switch shortcut {
        case let .once(chord):
            return "\(KeyChordFormatter.string(for: chord)) ×1"
        case let .repeatTwice(chord):
            return "\(KeyChordFormatter.string(for: chord)) ×2"
        case let .holdAndTapTwice(heldModifiers, tapKey):
            return localizedFormat(
                "Hold %@ · Tap %@ ×2",
                KeyChordFormatter.modifierSymbols(for: heldModifiers),
                KeyChordFormatter.string(for: tapKey)
            )
        }
    }

}

enum KeyChordFormatter {
    static func string(for chord: TextShortcutChord) -> String {
        modifierSymbols(for: chord.modifiers)
            + (chord.nonModifierKey.map { string(for: $0) } ?? "")
    }

    static func string(for key: TextShortcutKey) -> String {
        switch key {
        case let .modifier(modifier): modifierSymbols(for: modifier.mask)
        case let .function(functionKey): "F\(functionKey.rawValue)"
        case let .alphanumeric(key): key.rawValue
        }
    }

    static func modifierSymbols(for modifiers: KeyModifiers) -> String {
        var result = ""
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }
}
