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
            case .repeatTwice: localized("Press the entire shortcut twice.")
            case .holdAndTapTwice:
                localized("Hold modifier keys and tap the final key twice.")
            }
        }
    }

    private let action: TextAction
    private let shortcuts: () -> [TextAction: TextActionShortcut]
    private let validate: (TextActionShortcut) -> TextActionShortcutValidationResult
    private let save: (TextActionShortcut, TextShortcutConflict?) -> ConfigureTextActionShortcutResult
    private let onRecordingChanged: (Bool) -> Void
    private let onFinish: (Bool) -> Void
    private var draft: TextActionShortcut?
    private var selectedKind: GestureKind
    private var sheetWindow: NSWindow?
    private weak var parentWindow: NSWindow?
    private var eventMonitor: Any?
    private var classicModifierCandidate: KeyModifiers = []
    private var pendingHoldKey: (held: KeyModifiers, key: TextShortcutKey)?
    private var discardingFnModifiers = false
    private var didFinish = false
    private var displayedConflict: TextShortcutConflict?
    private var captureError: String?

    private let shortcutValueLabel = NSTextField(wrappingLabelWithString: localized("Press a shortcut"))
    private let captureHintLabel = NSTextField(labelWithString: "")
    private let captureBox = ShortcutCaptureBox()
    private var patternButtons: [NSButton] = []
    private let feedback = ShortcutFeedbackLayout()
    private let saveButton = NSButton(title: localized("Save"), target: nil, action: nil)

    init(
        action: TextAction,
        currentShortcut: TextActionShortcut?,
        shortcuts: @escaping () -> [TextAction: TextActionShortcut],
        validate: @escaping (TextActionShortcut) -> TextActionShortcutValidationResult,
        save: @escaping (TextActionShortcut, TextShortcutConflict?) -> ConfigureTextActionShortcutResult,
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
            guard let self else { return }
            self.resetCaptureState()
            let modifiers = KeyModifiers(eventModifierFlags: NSEvent.modifierFlags)
            if modifiers.intersection([.textShortcutModifiers, .function]).isEmpty {
                self.discardingFnModifiers = false
            }
            self.refresh()
        }
        captureBox.setAccessibilityLabel(localized("Shortcut"))
        captureBox.titlePosition = .noTitle
        captureBox.boxType = .custom
        captureBox.fillColor = .controlBackgroundColor
        captureBox.borderColor = .separatorColor
        captureBox.borderWidth = 1
        captureBox.cornerRadius = 9
        captureBox.contentViewMargins = .zero
        captureBox.translatesAutoresizingMaskIntoConstraints = false

        shortcutValueLabel.font = AppStyle.Font.shortcutValue
        shortcutValueLabel.isSelectable = false
        shortcutValueLabel.alignment = .center
        shortcutValueLabel.lineBreakMode = .byWordWrapping
        shortcutValueLabel.preferredMaxLayoutWidth = AppStyle.Layout.shortcutEditorWidth - 2 * AppStyle.Layout.windowInset - 24
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

        let cancelButton = NSButton(
            title: localized("Cancel"),
            target: self,
            action: #selector(cancelPressed)
        )
        AppStyle.configureCompactButton(cancelButton)
        AppStyle.configureCompactButton(saveButton)
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
            feedback.slot
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.detachesHiddenViews = true
        stack.setCustomSpacing(14, after: exampleLabel)
        stack.setCustomSpacing(5, after: patternTitle)
        stack.setCustomSpacing(14, after: patternOptions)
        stack.setCustomSpacing(5, after: shortcutTitle)
        stack.setCustomSpacing(0, after: captureBox)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: AppStyle.Layout.shortcutEditorWidth),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: AppStyle.Layout.windowInset),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -AppStyle.Layout.windowInset),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: AppStyle.Layout.windowTopInset),
            captureBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            captureBox.heightAnchor.constraint(equalToConstant: 66),
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
            feedback.slot.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -AppStyle.Layout.windowInset),
            buttonStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -12)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: AppStyle.Layout.shortcutEditorWidth, height: 422),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = localized("Set shortcut")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.initialFirstResponder = captureBox
        window.autorecalculatesKeyViewLoop = false
        let keyViews: [NSView] = [captureBox] + patternButtons + [cancelButton, saveButton]
        for (view, next) in zip(keyViews, keyViews.dropFirst() + [captureBox]) {
            view.nextKeyView = next
        }
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
        let input = TextShortcutKeyInput(event: event)
        let modifiers = input.modifiers
        if event.keyCode == 36, modifiers.isEmpty, !input.hasFn, !discardingFnModifiers {
            if saveButton.isEnabled, saveButton.keyEquivalent == "\r" { savePressed() }
            return nil
        }
        guard !event.isARepeat else { return nil }
        guard let key = input.key else {
            rejectCapture(localized("F1–F20, modifiers, or a letter or digit with Control, Option, or Command."))
            return nil
        }
        if case .alphanumeric = key {
            if input.rejectsFn { rejectFnModifier() }
            if discardingFnModifiers { return nil }
        }
        guard key.accepts(modifiers) else {
            rejectCapture(localized("Use Control, Option, or Command with a letter or digit."))
            return nil
        }

        switch selectedKind {
        case .once, .repeatTwice:
            let shortcut = classicShortcut(TextShortcutChord(modifiers: modifiers, key: key))
            resetCaptureState()
            setDraft(shortcut)
        case .holdAndTapTwice:
            guard !modifiers.isEmpty else {
                rejectCapture(localized("Hold at least one modifier, then press the final key."))
                return nil
            }
            pendingHoldKey = (modifiers, key)
            showCapture(
                localizedFormat(
                    "Hold %@ · Tap %@",
                    KeyChordFormatter.modifierSymbols(for: modifiers),
                    KeyChordFormatter.string(for: key)
                ),
                hint: localized("Release the final key to record")
            )
        }
        return nil
    }

    private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
        guard isCapturing(event) else { return event }
        let input = TextShortcutKeyInput(event: event)
        guard selectedKind == .holdAndTapTwice,
              let key = input.key,
              let pending = pendingHoldKey,
              pending.key == key else {
            return event
        }
        if input.rejectsFn {
            rejectFnModifier()
            return nil
        }
        pendingHoldKey = nil
        let active = input.modifiers
        guard active == pending.held else {
            rejectCapture(localized("Keep the held modifier keys down until the final key is released."))
            return nil
        }
        setDraft(.holdAndTapTwice(
            heldModifiers: pending.held,
            tapKey: key
        ))
        return nil
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard isCapturing(event) else { return }
        let input = TextShortcutKeyInput(event: event)
        let active = input.modifiers
        if input.hasFn {
            if !discardingFnModifiers { rejectFnModifier() }
            return
        }
        if discardingFnModifiers {
            // Ignore releases from the rejected gesture, even if Fn was released first.
            if active.isEmpty { discardingFnModifiers = false }
            return
        }
        guard case let .modifier(modifier)? = input.key else {
            return
        }
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
            guard pendingHoldKey == nil else { return }
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
                    rejectCapture(localized("The held and tapped modifier keys must be different."))
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

    private func setDraft(_ shortcut: TextActionShortcut) {
        captureError = nil
        draft = shortcut
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
                : localized("F1–F20, modifiers, or a letter or digit with Control, Option, or Command.")
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
        updateSaveButton(enabled: false)
    }

    private func resetCaptureState() {
        classicModifierCandidate = []
        pendingHoldKey = nil
    }

    private func rejectFnModifier() {
        discardingFnModifiers = true
        rejectCapture(localized("The Fn/Globe key is unsupported"))
    }

    private func rejectCapture(_ message: String) {
        resetCaptureState()
        captureError = message
        refresh()
    }

    private func refreshDraftStatus() {
        if let captureError {
            showError(captureError)
            return
        }
        guard let draft else {
            updateSaveButton(enabled: false)
            hideDraftStatus()
            return
        }
        switch validate(draft) {
        case .valid:
            showConflict(nil, for: draft)
        case let .externalConflict(conflict):
            showConflict(conflict, for: draft)
        case let .conflict(conflictingAction):
            showError(localizedFormat("Already assigned to %@.", conflictingAction.title))
        case .conflictWithReservedShortcut:
            showError(
                localized("Command alone is used by Keyboard switching. Choose different keys.")
            )
        case .invalid:
            showError(localized("Choose a valid shortcut."))
        }
    }

    private func showRelatedAssignments(for draft: TextActionShortcut) {
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
        guard !related.isEmpty else {
            hideDraftStatus()
            return
        }
        showFeedback(
            related.count == 1 ? localized("Related shortcut") : localized("Related shortcuts"),
            detail: related.joined(separator: "; "),
            style: .information
        )
    }

    private func hideDraftStatus() {
        displayedConflict = nil
        feedback.hide()
    }

    private func showError(_ message: String) {
        displayedConflict = nil
        showFeedback(message)
        updateSaveButton(enabled: false)
    }

    private func showFeedback(_ title: String, detail: String? = nil, style: ShortcutFeedbackLayout.Style = .error) {
        feedback.show(title, detail: detail, style: style)
    }

    private func updateSaveButton(enabled: Bool, requiresConfirmation: Bool = false) {
        saveButton.isEnabled = enabled
        saveButton.title = localized(requiresConfirmation ? "Assign Anyway" : "Save")
        saveButton.keyEquivalent = requiresConfirmation ? "" : "\r"
    }

    private func showConflict(_ conflict: TextShortcutConflict?, for draft: TextActionShortcut) {
        switch conflict {
        case nil:
            showRelatedAssignments(for: draft)
            updateSaveButton(enabled: true)
        case .system:
            showFeedback(localized("This shortcut is already used by macOS"))
            updateSaveButton(enabled: false)
        case let .documentedSystemCommand(command):
            showFeedback(
                localized("A macOS shortcut may take precedence"),
                detail: localized(command),
                style: .warning
            )
            updateSaveButton(enabled: true, requiresConfirmation: true)
        case let .commonCommand(command):
            showFeedback(
                localized("Common keyboard shortcut"),
                detail: localizedFormat("Replaces “%@”.", localized(command)),
                style: .warning
            )
            updateSaveButton(enabled: true, requiresConfirmation: true)
        case let .typing(layout, effect):
            let detail = switch effect {
            case .insertsText(let text):
                localizedFormat("In %1$@, it types “%2$@”.", layout, text)
            case .startsComposition:
                localizedFormat("In %@, it starts composing a character.", layout)
            }
            showFeedback(localized("This shortcut intercepts typing"), detail: detail, style: .warning)
            updateSaveButton(enabled: true, requiresConfirmation: true)
        }
        displayedConflict = conflict
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
                .foregroundColor: AppStyle.Color.stateDetailText
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
        refresh()
    }

    @objc private func savePressed() {
        guard !didFinish, saveButton.isEnabled, let draft, sheetWindow != nil else { return }
        switch save(draft, displayedConflict) {
        case .updated:
            finish(saved: true)
        case let .requiresConflictReview(conflict):
            showConflict(conflict, for: draft)
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The value and hint belong to one keyboard capture control.
        super.hitTest(point) == nil ? nil : self
    }

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
