// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import LanguageSwitcherApplication
import LanguageSwitcherDomain

@MainActor
final class TextShortcutSettingsWindowController: NSObject, NSWindowDelegate {
    private let shortcut: (TextAction) -> TextActionShortcut?
    private let validateShortcut: (
        TextActionShortcut,
        TextAction
    ) -> TextActionShortcutValidationResult
    private let setShortcut: (TextActionShortcut?, TextAction) -> ConfigureTextActionShortcutResult
    private let onRecordingChanged: (Bool) -> Void
    private var settingsWindow: NSWindow?
    private var editor: TextShortcutEditorSheetController?

    init(
        shortcut: @escaping (TextAction) -> TextActionShortcut?,
        validateShortcut: @escaping (
            TextActionShortcut,
            TextAction
        ) -> TextActionShortcutValidationResult,
        setShortcut: @escaping (TextActionShortcut?, TextAction) -> ConfigureTextActionShortcutResult,
        onRecordingChanged: @escaping (Bool) -> Void
    ) {
        self.shortcut = shortcut
        self.validateShortcut = validateShortcut
        self.setShortcut = setShortcut
        self.onRecordingChanged = onRecordingChanged
    }

    func showWindow() {
        if settingsWindow == nil {
            settingsWindow = makeWindow()
        }
        refreshContent()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        editor?.cancel()
        editor = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 360),
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

    private func refreshContent() {
        guard let window = settingsWindow else { return }

        let content = ShortcutSettingsContentView()
        let title = NSTextField(labelWithString: localized("Text action shortcuts"))
        title.font = AppStyle.Font.windowTitle

        let hint = NSTextField(
            wrappingLabelWithString: localized("Choose whether to press a shortcut once, repeat the whole shortcut, or hold modifiers and tap the final key twice.")
        )
        hint.textColor = .secondaryLabelColor
        hint.font = AppStyle.Font.supportingText
        hint.maximumNumberOfLines = 2

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

            let shortcutLabel = NSTextField(
                labelWithString: TextActionShortcutFormatter.string(for: configured)
            )
            shortcutLabel.textColor = configured == nil ? .tertiaryLabelColor : .secondaryLabelColor
            shortcutLabel.font = AppStyle.Font.body
            shortcutLabel.alignment = .center
            shortcutLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            let setButton = NSButton(
                title: configured == nil ? localized("Set…") : localized("Change…"),
                target: self,
                action: #selector(editShortcut(_:))
            )
            setButton.font = AppStyle.Font.controlLabel
            setButton.tag = index
            setButton.bezelStyle = .rounded
            setButton.widthAnchor.constraint(equalToConstant: 100).isActive = true

            let clearButton = NSButton(
                title: localized("Clear"),
                target: self,
                action: #selector(clearShortcut(_:))
            )
            clearButton.font = AppStyle.Font.controlLabel
            clearButton.tag = index
            clearButton.bezelStyle = .rounded
            clearButton.alignment = .center
            clearButton.isEnabled = configured != nil

            let clearSlot = NSView()
            clearSlot.widthAnchor.constraint(equalToConstant: 86).isActive = true
            clearButton.translatesAutoresizingMaskIntoConstraints = false
            clearSlot.addSubview(clearButton)
            NSLayoutConstraint.activate([
                clearButton.leadingAnchor.constraint(equalTo: clearSlot.leadingAnchor),
                clearButton.trailingAnchor.constraint(equalTo: clearSlot.trailingAnchor),
                clearButton.centerYAnchor.constraint(equalTo: clearSlot.centerYAnchor)
            ])

            let row = NSStackView(views: [actionLabels, shortcutLabel, setButton, clearSlot])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.spacing = 12
            actionLabels.widthAnchor.constraint(equalToConstant: 190).isActive = true
            return row
        }

        let rowsStack = NSStackView(views: rows)
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 14
        for row in rows {
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }

        let stack = NSStackView(views: [title, hint, rowsStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.setCustomSpacing(20, after: hint)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: AppStyle.Layout.windowInset),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -AppStyle.Layout.windowInset),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: AppStyle.Layout.windowTopInset),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            rowsStack.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.contentView = content
        window.initialFirstResponder = content
        window.makeFirstResponder(content)
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
            save: { [setShortcut] newShortcut in
                setShortcut(newShortcut, action)
            },
            onRecordingChanged: onRecordingChanged,
            onFinish: { [weak self] didSave in
                guard let self else { return }
                self.editor = nil
                if didSave {
                    self.refreshContent()
                }
            }
        )
        self.editor = editor
        editor.beginSheet(for: window)
    }

    @objc private func clearShortcut(_ sender: NSButton) {
        guard TextAction.allCases.indices.contains(sender.tag) else { return }
        let action = TextAction.allCases[sender.tag]
        if setShortcut(nil, action) == .updated {
            refreshContent()
        }
    }
}

private final class ShortcutSettingsContentView: NSView {
    override var acceptsFirstResponder: Bool { true }
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
            + (chord.functionKey.map { "F\($0.rawValue)" } ?? "")
    }

    static func string(for key: TextShortcutKey) -> String {
        switch key {
        case let .modifier(modifier): modifierSymbols(for: modifier.mask)
        case let .function(functionKey): "F\(functionKey.rawValue)"
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
