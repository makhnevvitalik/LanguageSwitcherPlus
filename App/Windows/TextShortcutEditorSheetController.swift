// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import LanguageSwitcherApplication
import LanguageSwitcherDomain
import LanguageSwitcherMacOS

@MainActor
final class TextShortcutEditorSheetController: NSObject, NSWindowDelegate {
    @MainActor
    private enum GestureKind: Int, CaseIterable {
        case once
        case repeatTwice
        case holdAndTapTwice

        var title: String {
            switch self {
            case .once: localized("Once")
            case .repeatTwice: localized("Twice")
            case .holdAndTapTwice: localized("Hold + twice")
            }
        }

        var explanation: String {
            switch self {
            case .once: localized("Press and release the shortcut once.")
            case .repeatTwice: localized("Repeat the whole shortcut twice.")
            case .holdAndTapTwice:
                localized("Hold modifier keys and tap the final key twice.")
            }
        }
    }

    private let action: TextAction
    private let shortcuts: () -> [TextAction: TextActionShortcut]
    private let validate: (TextActionShortcut) -> TextActionShortcutValidationResult
    private let save: (TextActionShortcut) -> ConfigureTextActionShortcutResult
    private let onRecordingChanged: (Bool) -> Void
    private let onFinish: (Bool) -> Void
    private var draft: TextActionShortcut?
    private var selectedKind: GestureKind
    private var sheetWindow: NSWindow?
    private weak var parentWindow: NSWindow?
    private var eventMonitor: Any?
    private var classicModifierCandidate: KeyModifiers = []
    private var pendingHoldFunction: (held: KeyModifiers, key: ShortcutFunctionKey)?
    private var didFinish = false

    private let shortcutValueLabel = NSTextField(labelWithString: localized("Press a shortcut"))
    private let captureHintLabel = NSTextField(labelWithString: "")
    private let captureBox = ShortcutCaptureBox()
    private var patternButtons: [NSButton] = []
    private let relatedAssignmentsLabel = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: localized("Save"), target: nil, action: nil)

    init(
        action: TextAction,
        currentShortcut: TextActionShortcut?,
        shortcuts: @escaping () -> [TextAction: TextActionShortcut],
        validate: @escaping (TextActionShortcut) -> TextActionShortcutValidationResult,
        save: @escaping (TextActionShortcut) -> ConfigureTextActionShortcutResult,
        onRecordingChanged: @escaping (Bool) -> Void,
        onFinish: @escaping (Bool) -> Void
    ) {
        self.action = action
        draft = currentShortcut
        selectedKind = Self.kind(for: currentShortcut)
        self.shortcuts = shortcuts
        self.validate = validate
        self.save = save
        self.onRecordingChanged = onRecordingChanged
        self.onFinish = onFinish
        super.init()
    }

    func beginSheet(for parentWindow: NSWindow) {
        self.parentWindow = parentWindow
        let window = makeWindow()
        sheetWindow = window
        installEventMonitor()
        onRecordingChanged(true)
        refresh()
        parentWindow.beginSheet(window)
        window.makeFirstResponder(captureBox)
    }

    func cancel() {
        finish(saved: false)
    }

    func windowWillClose(_ notification: Notification) {
        finish(saved: false)
    }

    private func makeWindow() -> NSWindow {
        let content = NSView()

        let title = NSTextField(
            labelWithString: localizedFormat("%@ shortcut", action.title)
        )
        title.font = AppStyle.Font.windowTitle
        let exampleLabel = NSTextField(labelWithString: action.example)
        exampleLabel.font = AppStyle.Font.textExample
        exampleLabel.textColor = .secondaryLabelColor

        captureBox.focusDidChange = { [weak self] in
            self?.resetCaptureState()
            self?.refresh()
        }
        captureBox.setAccessibilityLabel(localized("Shortcut"))
        captureBox.titlePosition = .noTitle
        captureBox.boxType = .custom
        captureBox.fillColor = .controlBackgroundColor
        captureBox.borderColor = .separatorColor
        captureBox.borderWidth = 1
        captureBox.cornerRadius = 9
        captureBox.translatesAutoresizingMaskIntoConstraints = false

        shortcutValueLabel.font = AppStyle.Font.shortcutValue
        shortcutValueLabel.alignment = .center
        shortcutValueLabel.lineBreakMode = .byTruncatingTail
        shortcutValueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        captureHintLabel.font = AppStyle.Font.supportingText
        captureHintLabel.textColor = .secondaryLabelColor
        captureHintLabel.alignment = .center
        captureHintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let captureStack = NSStackView(views: [shortcutValueLabel, captureHintLabel])
        captureStack.orientation = .vertical
        captureStack.alignment = .centerX
        captureStack.spacing = 5
        captureStack.translatesAutoresizingMaskIntoConstraints = false
        captureBox.contentView?.addSubview(captureStack)

        let shortcutTitle = NSTextField(labelWithString: localized("Shortcut"))
        shortcutTitle.font = AppStyle.Font.fieldLabel
        shortcutTitle.textColor = .secondaryLabelColor

        let patternTitle = NSTextField(labelWithString: localized("Press pattern"))
        patternTitle.font = AppStyle.Font.fieldLabel
        patternTitle.textColor = .secondaryLabelColor

        let patternOptions = NSStackView()
        patternOptions.orientation = .vertical
        patternOptions.alignment = .leading
        patternOptions.spacing = 7
        for kind in GestureKind.allCases {
            let button = NSButton(
                radioButtonWithTitle: "",
                target: self,
                action: #selector(changePattern(_:))
            )
            button.tag = kind.rawValue
            button.attributedTitle = attributedPatternTitle(for: kind)
            button.cell?.wraps = true
            button.cell?.usesSingleLineMode = false
            button.cell?.lineBreakMode = .byWordWrapping
            button.alignment = .left
            button.setAccessibilityLabel(kind.title)
            button.setAccessibilityHelp(kind.explanation)
            patternButtons.append(button)
            patternOptions.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: patternOptions.widthAnchor).isActive = true
        }

        relatedAssignmentsLabel.font = AppStyle.Font.supportingText
        relatedAssignmentsLabel.textColor = .secondaryLabelColor
        relatedAssignmentsLabel.maximumNumberOfLines = 2
        relatedAssignmentsLabel.isHidden = true

        errorLabel.font = AppStyle.Font.supportingText
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true

        let cancelButton = NSButton(
            title: localized("Cancel"),
            target: self,
            action: #selector(cancelPressed)
        )
        cancelButton.font = AppStyle.Font.controlLabel
        saveButton.font = AppStyle.Font.controlLabel
        cancelButton.keyEquivalent = "\u{1b}"
        saveButton.target = self
        saveButton.action = #selector(savePressed)
        saveButton.keyEquivalent = "\r"
        let buttonStack = NSStackView(views: [cancelButton, saveButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        let stack = NSStackView(views: [
            title,
            exampleLabel,
            patternTitle,
            patternOptions,
            shortcutTitle,
            captureBox,
            relatedAssignmentsLabel,
            errorLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.detachesHiddenViews = true
        stack.setCustomSpacing(14, after: exampleLabel)
        stack.setCustomSpacing(5, after: patternTitle)
        stack.setCustomSpacing(14, after: patternOptions)
        stack.setCustomSpacing(5, after: shortcutTitle)
        stack.setCustomSpacing(8, after: captureBox)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: AppStyle.Layout.windowInset),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -AppStyle.Layout.windowInset),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: AppStyle.Layout.windowTopInset),
            captureBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            captureBox.heightAnchor.constraint(equalToConstant: 58),
            patternOptions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            captureStack.centerXAnchor.constraint(equalTo: captureBox.contentView!.centerXAnchor),
            captureStack.centerYAnchor.constraint(equalTo: captureBox.contentView!.centerYAnchor),
            captureStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: captureBox.contentView!.leadingAnchor,
                constant: 12
            ),
            captureStack.trailingAnchor.constraint(
                lessThanOrEqualTo: captureBox.contentView!.trailingAnchor,
                constant: -12
            ),
            relatedAssignmentsLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -AppStyle.Layout.windowInset),
            buttonStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: buttonStack.topAnchor, constant: -12)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 390),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = localized("Set shortcut")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = content
        window.initialFirstResponder = captureBox
        return window
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown:
                return self.handleKeyDown(event)
            case .keyUp:
                return self.handleKeyUp(event)
            case .flagsChanged:
                self.handleFlagsChanged(event)
                return event
            default:
                return event
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard isCapturing(event) else { return event }
        // Let AppKit navigate controls; modifier releases from Shift+Tab must
        // not turn keyboard navigation into a recorded shortcut.
        if [48, 49, 123, 124, 125, 126].contains(event.keyCode) {
            resetCaptureState()
            refresh()
            return event
        }
        if event.keyCode == 53 {
            cancel()
            return nil
        }
        let modifiers = supportedModifiers(in: event)
        if event.keyCode == 36, modifiers.isEmpty, saveButton.isEnabled {
            savePressed()
            return nil
        }
        guard !event.isARepeat,
              let functionKey = ShortcutFunctionKey(keyCode: event.keyCode) else {
            showError(localized("Use Shift, Control, Option, Command, or F1–F20."))
            return nil
        }

        switch selectedKind {
        case .once, .repeatTwice:
            let shortcut = classicShortcut(TextShortcutChord(
                modifiers: modifiers,
                functionKey: functionKey
            ))
            resetCaptureState()
            setDraft(shortcut)
        case .holdAndTapTwice:
            guard !modifiers.isEmpty else {
                showError(localized("Hold at least one modifier, then press F1–F20."))
                return nil
            }
            pendingHoldFunction = (modifiers, functionKey)
            showCapture(
                localizedFormat(
                    "Hold %@ · Tap F%d",
                    KeyChordFormatter.modifierSymbols(for: modifiers),
                    functionKey.rawValue
                ),
                hint: localized("Release the final key to record")
            )
        }
        return nil
    }

    private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
        guard isCapturing(event) else { return event }
        guard selectedKind == .holdAndTapTwice,
              let functionKey = ShortcutFunctionKey(keyCode: event.keyCode),
              let pending = pendingHoldFunction,
              pending.key == functionKey else {
            return event
        }
        pendingHoldFunction = nil
        let active = supportedModifiers(in: event)
        guard active == pending.held else {
            resetCaptureState()
            refresh()
            showError(localized("Keep the held modifier keys down until the final key is released."))
            return nil
        }
        setDraft(.holdAndTapTwice(
            heldModifiers: pending.held,
            tapKey: .function(functionKey)
        ))
        return nil
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard isCapturing(event) else { return }
        guard let modifier = ShortcutModifier(keyCode: event.keyCode) else {
            return
        }
        let active = supportedModifiers(in: event)
        let isDown = active.contains(modifier.mask)

        switch selectedKind {
        case .once, .repeatTwice:
            if isDown {
                classicModifierCandidate.formUnion(active)
                showCapture(
                    KeyChordFormatter.modifierSymbols(for: classicModifierCandidate),
                    hint: localized("Release the keys to record")
                )
            } else if active.isEmpty, !classicModifierCandidate.isEmpty {
                let captured = classicModifierCandidate
                resetCaptureState()
                setDraft(classicShortcut(TextShortcutChord(
                    modifiers: captured,
                    functionKey: nil
                )))
            }

        case .holdAndTapTwice:
            if isDown {
                showCapture(
                    KeyChordFormatter.modifierSymbols(for: active),
                    hint: active.count > 1
                        ? localized("Release the final key to record")
                        : localized("Press the final key")
                )
            } else {
                guard !active.isEmpty else {
                    if draft == nil {
                        showCapture(
                            localized("Hold modifier keys"),
                            hint: localized("Then press the final key"),
                            isInstruction: true
                        )
                    }
                    return
                }
                let shortcut = TextActionShortcut.holdAndTapTwice(
                    heldModifiers: active,
                    tapKey: .modifier(modifier)
                )
                guard shortcut.isValidGlobalShortcut else {
                    showError(localized("The held and tapped modifier keys must be different."))
                    return
                }
                resetCaptureState()
                setDraft(shortcut)
            }
        }
    }

    private func isCapturing(_ event: NSEvent) -> Bool {
        guard let sheetWindow else { return false }
        return event.window === sheetWindow && sheetWindow.firstResponder === captureBox
    }

    private func refreshCaptureBorder() {
        let focused = captureBox.hasKeyboardFocus
        captureBox.borderColor = focused ? .controlAccentColor : .separatorColor
        captureBox.borderWidth = focused ? 2 : 1
    }

    private func classicShortcut(_ chord: TextShortcutChord) -> TextActionShortcut {
        switch selectedKind {
        case .once: .once(chord)
        case .repeatTwice: .repeatTwice(chord)
        case .holdAndTapTwice:
            preconditionFailure("Classic shortcut requested for Hold & tap")
        }
    }

    private func supportedModifiers(in event: NSEvent) -> KeyModifiers {
        KeyModifiers(eventModifierFlags: event.modifierFlags)
            .intersection(.textShortcutModifiers)
    }

    private func setDraft(_ shortcut: TextActionShortcut) {
        draft = shortcut
        errorLabel.stringValue = ""
        errorLabel.isHidden = true
        refresh()
    }

    private func refresh() {
        for button in patternButtons {
            button.state = button.tag == selectedKind.rawValue ? .on : .off
        }
        if let draft {
            shortcutValueLabel.stringValue = TextActionShortcutFormatter.string(for: draft)
            shortcutValueLabel.font = AppStyle.Font.shortcutValue
            shortcutValueLabel.textColor = .labelColor
            captureHintLabel.stringValue = localized("Press a new shortcut to replace")
        } else {
            shortcutValueLabel.stringValue = emptyCapturePrompt
            shortcutValueLabel.font = AppStyle.Font.body
            shortcutValueLabel.textColor = .secondaryLabelColor
            captureHintLabel.stringValue = selectedKind == .holdAndTapTwice
                ? localized("Then press the final key")
                : localized("Modifier keys and F1–F20")
        }
        refreshCaptureBorder()
        refreshDraftStatus()
    }

    private var emptyCapturePrompt: String {
        switch selectedKind {
        case .once, .repeatTwice:
            localized("Press a shortcut")
        case .holdAndTapTwice:
            localized("Hold modifier keys")
        }
    }

    private func showCapture(_ value: String, hint: String, isInstruction: Bool = false) {
        shortcutValueLabel.stringValue = value
        shortcutValueLabel.font = isInstruction
            ? AppStyle.Font.body
            : AppStyle.Font.shortcutValue
        shortcutValueLabel.textColor = .labelColor
        captureHintLabel.stringValue = hint
        refreshCaptureBorder()
        saveButton.isEnabled = false
        hideDraftStatus()
    }

    private func resetCaptureState() {
        classicModifierCandidate = []
        pendingHoldFunction = nil
    }

    private func refreshDraftStatus() {
        guard let draft else {
            saveButton.isEnabled = false
            hideDraftStatus()
            return
        }
        switch validate(draft) {
        case .valid:
            saveButton.isEnabled = true
            errorLabel.stringValue = ""
            errorLabel.isHidden = true
            refreshRelatedAssignments(for: draft)
        case let .conflict(conflictingAction):
            saveButton.isEnabled = false
            showError(localizedFormat("Already assigned to %@.", conflictingAction.title))
        case .conflictWithReservedShortcut:
            saveButton.isEnabled = false
            showError(
                localized("Command alone is used by Keyboard switching. Choose different keys.")
            )
        case .invalid:
            saveButton.isEnabled = false
            showError(localized("Choose a valid shortcut."))
        }
    }

    private func refreshRelatedAssignments(for draft: TextActionShortcut) {
        let related = shortcuts()
            .filter { $0.key != action && $0.value.physicalKeys == draft.physicalKeys }
            .sorted { $0.key.title < $1.key.title }
            .map {
                localizedFormat(
                    "%@ uses %@",
                    $0.key.title,
                    TextActionShortcutFormatter.string(for: $0.value)
                )
            }
        relatedAssignmentsLabel.stringValue = related.isEmpty
            ? ""
            : "\(related.count == 1 ? localized("Related shortcut") : localized("Related shortcuts")): "
                + related.joined(separator: "; ")
        relatedAssignmentsLabel.isHidden = related.isEmpty
    }

    private func hideDraftStatus() {
        relatedAssignmentsLabel.stringValue = ""
        relatedAssignmentsLabel.isHidden = true
        errorLabel.stringValue = ""
        errorLabel.isHidden = true
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        relatedAssignmentsLabel.isHidden = true
        saveButton.isEnabled = false
    }

    @objc private func changePattern(_ sender: NSButton) {
        guard let kind = GestureKind(rawValue: sender.tag) else {
            return
        }
        selectPattern(kind)
    }

    private func attributedPatternTitle(for kind: GestureKind) -> NSAttributedString {
        let value = NSMutableAttributedString(
            string: kind.title,
            attributes: [
                .font: AppStyle.Font.body,
                .foregroundColor: NSColor.labelColor
            ]
        )
        value.append(NSAttributedString(
            string: "\n\(kind.explanation)",
            attributes: [
                .font: AppStyle.Font.supportingText,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
        return value
    }

    private func selectPattern(_ kind: GestureKind) {
        guard kind != selectedKind else { return }
        selectedKind = kind
        resetCaptureState()
        switch (kind, draft) {
        case (.once, .some(.repeatTwice(let chord))):
            draft = .once(chord)
        case (.repeatTwice, .some(.once(let chord))):
            draft = .repeatTwice(chord)
        default:
            draft = nil
        }
        errorLabel.stringValue = ""
        errorLabel.isHidden = true
        refresh()
    }

    @objc private func savePressed() {
        guard let draft else { return }
        switch save(draft) {
        case .updated:
            finish(saved: true)
        case let .conflict(conflictingAction):
            showError(localizedFormat("Already assigned to %@.", conflictingAction.title))
        case .conflictWithReservedShortcut:
            showError(
                localized("Command alone is used by Keyboard switching. Choose different keys.")
            )
        case .invalid:
            showError(localized("Choose a valid shortcut before saving."))
        }
    }

    @objc private func cancelPressed() {
        cancel()
    }

    private func finish(saved: Bool) {
        guard !didFinish else { return }
        didFinish = true
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        onRecordingChanged(false)
        if let parentWindow, let sheetWindow, parentWindow.attachedSheet === sheetWindow {
            parentWindow.endSheet(sheetWindow)
        }
        onFinish(saved)
    }

    private static func kind(for shortcut: TextActionShortcut?) -> GestureKind {
        switch shortcut {
        case .some(.repeatTwice): .repeatTwice
        case .some(.holdAndTapTwice): .holdAndTapTwice
        case .some(.once), .none: .once
        }
    }

}

private extension KeyModifiers {
    var count: Int {
        ShortcutModifier.allCases.reduce(0) {
            $0 + (contains($1.mask) ? 1 : 0)
        }
    }
}

/// A focusable capture area; standard controls keep their ordinary key handling.
private final class ShortcutCaptureBox: NSBox {
    var focusDidChange: (() -> Void)?
    private(set) var hasKeyboardFocus = false

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            hasKeyboardFocus = true
            focusDidChange?()
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            hasKeyboardFocus = false
            focusDidChange?()
        }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) {
                window?.selectPreviousKeyView(self)
            } else {
                window?.selectNextKeyView(self)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}
