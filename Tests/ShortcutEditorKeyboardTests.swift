// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

// Appended to the controller source by the runner so tests can exercise private
// AppKit handlers without adding test hooks or installing an event monitor.
func localized(_ value: String) -> String { value }
func localizedFormat(_ value: String, _ arguments: CVarArg...) -> String {
    String(format: value, arguments: arguments)
}

extension TextShortcutEditorSheetController {
    static func runKeyboardTests() throws {
        var saves = 0
        var finished: Bool?
        let editor = TextShortcutEditorSheetController(
            action: .changeCase(.uppercase),
            currentShortcut: nil,
            shortcuts: { [:] }, validate: { _ in .valid },
            save: { _, _ in saves += 1; return .updated },
            onRecordingChanged: { _ in }, onFinish: { finished = $0 }
        )
        let window = editor.makeWindow()
        editor.sheetWindow = window
        editor.refresh()
        defer { window.orderOut(nil) }
        try require(editor.captureHintLabel.stringValue ==
                    "F1–F20, modifiers, or a letter or digit with Control, Option, or Command.",
                    "An empty recorder must explain the modifier requirement for letters and digits")
        let radio = editor.patternButtons[0]
        window.makeFirstResponder(radio)
        for key: UInt16 in [48, 49, 123, 124, 125, 126] {
            let input = keyEvent(.keyDown, key: key, window: window)
            try require(editor.handleKeyDown(input) === input,
                        "Navigation key \(key) was swallowed outside the capture area")
        }
        let shiftTab = keyEvent(.keyDown, key: 48, flags: [.shift], window: window)
        try require(editor.handleKeyDown(shiftTab) === shiftTab, "Shift+Tab must reach AppKit")
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 56, flags: [.shift], window: window))
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 56, window: window))
        try require(editor.draft == nil, "Keyboard navigation must not record a Shift shortcut")
        let f1Outside = keyEvent(.keyDown, key: 122, window: window)
        try require(editor.handleKeyDown(f1Outside) === f1Outside && editor.draft == nil,
                    "Only the focused capture area may record shortcuts")

        try require(window.makeFirstResponder(editor.captureBox), "Capture area must accept keyboard focus")
        let nextCapture = ShortcutCaptureBox(frame: NSRect(x: 1, y: 1, width: 5, height: 5))
        window.contentView!.addSubview(nextCapture)
        let originalNext = editor.captureBox.nextKeyView
        window.autorecalculatesKeyViewLoop = false
        editor.captureBox.nextKeyView = nextCapture
        nextCapture.nextKeyView = editor.captureBox
        editor.captureBox.keyDown(with: keyEvent(.keyDown, key: 48, window: window))
        try require(window.firstResponder === nextCapture, "Tab must leave the capture area")
        nextCapture.keyDown(with: shiftTab)
        try require(window.firstResponder === editor.captureBox, "Shift+Tab must follow the reverse key-view loop")
        editor.captureBox.nextKeyView = originalNext
        nextCapture.removeFromSuperview()
        for key: UInt16 in [48, 49, 123, 124, 125, 126] {
            let input = keyEvent(.keyDown, key: key, window: window)
            try require(editor.handleKeyDown(input) === input,
                        "Navigation key \(key) must not be recorded as a shortcut")
        }
        try require(editor.feedback.banner.isHidden, "Navigation must not show an invalid-shortcut error")
        let f1Inside = keyEvent(.keyDown, key: 122, window: window)
        try require(editor.handleKeyDown(f1Inside) == nil && editor.draft != nil,
                    "Focused capture area must still record F1")
        try require(editor.captureBox.borderWidth == 2, "Focused capture must be highlighted")
        let savedDraft = editor.draft
        window.contentView?.layoutSubtreeIfNeeded()
        for label in [editor.shortcutValueLabel, editor.captureHintLabel] {
            window.makeFirstResponder(radio)
            let point = NSPoint(x: label.bounds.midX, y: label.bounds.midY)
            let location = label.convert(point, to: nil)
            let content = window.contentView!
            let target = content.hitTest(label.convert(point, to: content.superview))
            let click = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                                          timestamp: 0, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            try require(target === editor.captureBox, "A click on the recorder text must reach the capture area")
            target?.mouseDown(with: click)
            try require(window.firstResponder === editor.captureBox && editor.captureBox.borderWidth == 2,
                        "Clicking either line must focus and highlight shortcut recording")
        }
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 56, flags: [.shift], window: window))
        window.makeFirstResponder(radio)
        try require(editor.captureBox.borderWidth == 1, "Capture highlight must leave with focus")
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 56, window: window))
        try require(editor.draft == savedDraft, "Leaving capture must discard an unfinished gesture")

        window.makeFirstResponder(editor.captureBox)
        let otherWindow = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let foreignInput = keyEvent(.keyDown, key: 120, window: otherWindow)
        try require(editor.handleKeyDown(foreignInput) === foreignInput && editor.draft == savedDraft,
                    "Editor must not capture events belonging to another window")
        editor.selectPattern(.once)
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 56, flags: [.shift], window: window))
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 56, window: window))
        try require(editor.draft == .once(TextShortcutChord(modifiers: .shift, functionKey: nil)),
                    "Modifier-only shortcuts must still record in the capture area")

        let previousDraft = editor.draft
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 56, flags: .shift, window: window))
        _ = editor.handleKeyDown(keyEvent(.keyDown, key: 40, flags: .shift, window: window))
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 56, window: window))
        try require(editor.draft == previousDraft && !editor.feedback.banner.isHidden,
                    "Shift plus a letter is rejected without recording Shift alone")
        let captureError = editor.feedback.label.stringValue
        let tab = keyEvent(.keyDown, key: 48, window: window)
        try require(editor.handleKeyDown(tab) === tab, "Tab must still reach AppKit after a capture error")
        window.makeFirstResponder(radio)
        try require(editor.feedback.label.stringValue == captureError && !editor.feedback.banner.isHidden
                    && !editor.saveButton.isEnabled,
                    "Leaving capture must preserve its error and prevent saving the previous draft")
        window.makeFirstResponder(editor.captureBox)
        let letter = TextShortcutKey.alphanumeric(ShortcutAlphanumericKey(rawValue: "K")!)
        for characters in ["k", "л"] {
            _ = editor.handleKeyDown(keyEvent(.keyDown, key: 40, flags: .command, characters: characters, window: window))
            try require(editor.draft == .once(TextShortcutChord(modifiers: .command, key: letter))
                        && editor.shortcutValueLabel.stringValue == "⌘K ×1",
                        "The editor must record and display the physical key in either layout")
        }
        let beforeFn = editor.draft
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 63, flags: .function, window: window))
        try require(!editor.feedback.banner.isHidden && !editor.saveButton.isEnabled,
                    "Pressing Fn by itself must immediately show an error")
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 58, flags: [.option, .function], window: window))
        _ = editor.handleKeyDown(keyEvent(.keyDown, key: 40, flags: [.option, .function], window: window))
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 58, flags: [.function], window: window))
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 63, window: window))
        try require(editor.draft == beforeFn && !editor.feedback.banner.isHidden,
                    "Fn plus Option plus a letter must not silently become Option plus that letter")
        editor.selectPattern(.repeatTwice)
        let digit = TextShortcutKey.alphanumeric(ShortcutAlphanumericKey(rawValue: "3")!)
        _ = editor.handleKeyDown(keyEvent(.keyDown, key: 20, flags: [.control, .shift], window: window))
        try require(editor.draft == .repeatTwice(TextShortcutChord(modifiers: [.control, .shift], key: digit)),
                    "A digit with Control and Shift must be valid for the twice gesture")

        editor.selectPattern(.holdAndTapTwice)
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 56, flags: [.shift], window: window))
        _ = editor.handleKeyDown(keyEvent(.keyDown, key: 122, flags: [.shift], window: window))
        _ = editor.handleKeyUp(keyEvent(.keyUp, key: 122, flags: [.shift], window: window))
        try require(editor.draft?.isValidGlobalShortcut == true,
                    "Hold-and-tap shortcuts must still record in the capture area")
        _ = editor.handleKeyDown(keyEvent(.keyDown, key: 20, flags: .option, window: window))
        _ = editor.handleKeyUp(keyEvent(.keyUp, key: 20, flags: .option, window: window))
        try require(editor.draft == .holdAndTapTwice(heldModifiers: .option, tapKey: digit),
                    "A digit must also work as the final key of a hold gesture")
        let previousHold = editor.draft
        for (key, flags): (UInt16, NSEvent.ModifierFlags) in [
            (63, .function), (59, [.function, .control]), (58, [.function, .control, .option])
        ] {
            editor.handleFlagsChanged(keyEvent(.flagsChanged, key: key, flags: flags, window: window))
        }
        _ = editor.handleKeyDown(keyEvent(.keyDown, key: 40, flags: [.function, .control, .option], window: window))
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 63, flags: [.control, .option], window: window))
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 58, flags: .control, window: window))
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 59, window: window))
        try require(editor.draft == previousHold && !editor.feedback.banner.isHidden && !editor.saveButton.isEnabled,
                    "Releasing the modifiers after an Fn gesture must leave its error and keep the previous draft")
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 63, flags: .function, window: window))
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 56, flags: [.function, .shift], window: window))
        _ = editor.handleKeyDown(keyEvent(.keyDown, key: 122, flags: [.function, .shift], window: window))
        _ = editor.handleKeyUp(keyEvent(.keyUp, key: 122, flags: [.function, .shift], window: window))
        try require(editor.draft == .holdAndTapTwice(heldModifiers: .shift, tapKey: .function(.init(rawValue: 1)!)),
                    "A function key delivered by macOS must still be recordable using the hardware Fn layer")
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 56, flags: .function, window: window))
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 63, window: window))
        window.makeFirstResponder(radio)
        let enter = keyEvent(.keyDown, key: 36, window: window)
        try require(editor.handleKeyDown(enter) === enter && saves == 0,
                    "Enter outside capture must remain available to native default-button handling")
        window.makeFirstResponder(editor.captureBox)
        try require(editor.handleKeyDown(enter) == nil && saves == 1 && finished == true,
                    "Enter in capture must still save a valid shortcut")
        print("PASS: shortcut editor focus, navigation, capture and unfinished-gesture cancellation")
    }

    static func runInlineConflictTests() throws {
        let longLayout = "Malayalam – Transliteration (Extended Latin and Malayalam)"
        let copy = TextActionShortcut.once(TextShortcutChord(
            modifiers: .command, key: .alphanumeric(.init(rawValue: "C")!)
        ))
        let action = TextAction.changeCase(.uppercase)
        let conflicts: [(TextShortcutConflict, String)] = [
            (.system, "This shortcut is already used by macOS"),
            (.documentedSystemCommand("Toggle Dock"), "Toggle Dock"),
            (.commonCommand("Copy"), "Replaces “Copy”."),
            (.typing(layout: "ABC", effect: .insertsText("™")), "In ABC, it types “™”."),
            (.typing(layout: "ABC", effect: .startsComposition), "In ABC, it starts composing a character."),
            (.typing(layout: longLayout, effect: .startsComposition), "In \(longLayout), it starts composing a character.")
        ]
        for (conflict, expectedMessage) in conflicts {
            var detected: TextShortcutConflict? = conflict
            let store = EditorShortcutStore()
            let useCase = ConfigureTextActionShortcut(store: store, checkConflict: { _ in detected })
            let editor = TextShortcutEditorSheetController(
                action: action, currentShortcut: nil, shortcuts: { [:] },
                validate: { useCase.validateShortcut($0, for: action) },
                save: { useCase.setShortcut($0, for: action, reviewedConflict: $1) },
                onRecordingChanged: { _ in }, onFinish: { _ in }
            )
            let window = editor.makeWindow()
            editor.sheetWindow = window
            editor.refresh()
            window.makeFirstResponder(editor.captureBox)
            defer { editor.cancel(); window.orderOut(nil) }

            let view = window.contentView!
            view.layoutSubtreeIfNeeded()
            let initialSize = view.bounds.size
            try require(initialSize.width == 540, "The shortcut editor uses the shared 540-point width")
            let initialFrame = window.frame
            let initialField = window.convertToScreen(editor.captureBox.convert(editor.captureBox.bounds, to: nil))
            let buttons = editor.saveButton.superview!
            let initialButtons = window.convertToScreen(buttons.convert(buttons.bounds, to: nil))
            try require(editor.feedback.slot.frame.height == 0 && editor.feedback.banner.isHidden
                        && abs(initialField.minY - initialButtons.maxY - 12) < 1,
                        "Without feedback the buttons sit 12 points below the capture field")

            _ = editor.handleKeyDown(keyEvent(.keyDown, key: 8, flags: .command, window: window))
            view.layoutSubtreeIfNeeded()
            try require(editor.draft == copy && window.attachedSheet == nil,
                        "Conflicts must appear in the editor after recording")
            try require(!editor.feedback.banner.isHidden && editor.feedback.slot.frame.height > 0,
                        "A visible conflict opens the feedback area")
            let conflictMessage = editor.feedback.label.stringValue
            try require(conflictMessage.contains(expectedMessage), "Conflict feedback must describe what is affected")
            if conflict == .typing(layout: longLayout, effect: .startsComposition) {
                let label = editor.feedback.label
                let text = label.attributedStringValue
                let detailRange = (text.string as NSString).range(of: expectedMessage)
                let detail = text.attributedSubstring(from: detailRange)
                let width = label.bounds.width - 4
                let wrapped = text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin, .usesFontLeading])
                try require(detail.size().width > width && wrapped.height > 40,
                            "The long warning fixture must need three lines")
                try require(label.bounds.height + 1 >= wrapped.height,
                            "The long warning must lay out all three lines without clipping")
            }
            try require(editor.saveButton.isEnabled == (conflict != .system),
                        "Only an enabled macOS shortcut must be blocked")
            let currentField = window.convertToScreen(editor.captureBox.convert(editor.captureBox.bounds, to: nil))
            let currentButtons = window.convertToScreen(buttons.convert(buttons.bounds, to: nil))
            let growth = window.frame.height - initialFrame.height
            try require(growth > 0 && currentField == initialField && window.frame.maxY == initialFrame.maxY
                        && abs(currentButtons.maxY + growth - initialButtons.maxY) < 1
                        && window.firstResponder === editor.captureBox,
                        "Feedback expands the window downwards and keeps capture position and focus")
            let conflictFrame = window.frame
            editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 58, flags: .option, window: window))
            try require(window.frame == conflictFrame && editor.feedback.label.stringValue == conflictMessage
                        && !editor.saveButton.isEnabled,
                        "Previewing a modifier must retain the existing warning without resizing")
            editor.resetCaptureState()
            editor.refresh()

            let enter = keyEvent(.keyDown, key: 36, window: window)
            _ = editor.handleKeyDown(enter)
            try require(store.shortcut(for: action) == nil && editor.feedback.label.stringValue == conflictMessage,
                        "Return in the capture field must leave the conflict visible without saving")

            if conflict == .system {
                editor.savePressed()
                try require(store.shortcut(for: action) == nil, "The enabled system shortcut must never be saved")
                detected = nil
                _ = editor.handleKeyDown(keyEvent(.keyDown, key: 122, window: window))
                try require(editor.saveButton.title == "Save" && editor.saveButton.isEnabled
                            && editor.feedback.banner.isHidden && window.frame == initialFrame,
                            "Recording a valid shortcut restores ordinary saving and the compact frame")
            } else {
                try require(editor.saveButton.title == "Assign Anyway" && editor.saveButton.keyEquivalent.isEmpty,
                            "An inline warning must require an explicit Assign Anyway action")
                editor.savePressed()
                try require(store.shortcut(for: action) == copy && editor.didFinish && window.attachedSheet == nil,
                            "Assign Anyway must save from the current editor without opening another sheet")
            }
        }

        var conflict: TextShortcutConflict?
        let store = EditorShortcutStore()
        let useCase = ConfigureTextActionShortcut(store: store, checkConflict: { _ in conflict })
        let editor = TextShortcutEditorSheetController(
            action: action, currentShortcut: copy, shortcuts: { [:] },
            validate: { useCase.validateShortcut($0, for: action) },
            save: { useCase.setShortcut($0, for: action, reviewedConflict: $1) },
            onRecordingChanged: { _ in }, onFinish: { _ in }
        )
        let window = editor.makeWindow()
        editor.sheetWindow = window
        editor.refresh()
        defer { editor.cancel(); window.orderOut(nil) }

        conflict = .commonCommand("Copy")
        editor.savePressed()
        try require(store.shortcut(for: action) == nil && editor.saveButton.title == "Assign Anyway",
                    "A newly detected warning must be displayed before the user can accept it")

        conflict = .system
        editor.savePressed()
        try require(store.shortcut(for: action) == nil && !editor.saveButton.isEnabled,
                    "A system shortcut that becomes enabled before saving must be blocked")
        print("PASS: inline conflict warnings, system blocking, keyboard confirmation and stable layout")
    }

    private static func keyEvent(_ type: NSEvent.EventType, key: UInt16,
                                 flags: NSEvent.ModifierFlags = [], characters: String = "", window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: key)!
    }

    static func runRelatedAssignmentsTests() throws {
        let chord = TextShortcutChord(modifiers: [.shift, .control, .option, .command], functionKey: nil)
        let draft = TextActionShortcut.once(chord)
        let related = TextActionShortcut.holdAndTapTwice(heldModifiers: [.control, .option, .command],
                                                        tapKey: .modifier(.shift))
        var assignments: [TextAction: TextActionShortcut] = [.changeCase(.uppercase): related]
        var saved: TextActionShortcut?
        let editor = TextShortcutEditorSheetController(
            action: .changeCase(.lowercase), currentShortcut: draft,
            shortcuts: { assignments }, validate: { _ in .valid },
            save: { shortcut, _ in saved = shortcut; return .updated }, onRecordingChanged: { _ in }, onFinish: { _ in }
        )
        let window = editor.makeWindow()
        editor.sheetWindow = window
        defer { editor.cancel(); window.orderOut(nil) }
        editor.refresh()
        let content = window.contentView!
        content.layoutSubtreeIfNeeded()
        try require(!editor.feedback.banner.isHidden && editor.feedback.banner.borderWidth == 1,
                    "A related shortcut must use the outlined information banner")
        try require(editor.feedback.label.stringValue ==
                    "Related shortcut\n\(TextAction.changeCase(.uppercase).title) uses \(TextActionShortcutFormatter.string(for: related))",
                    "The banner must identify the related action and its full shortcut on a separate line")
        try require(editor.feedback.slot.frame.height > 0 && editor.saveButton.title == "Save",
                    "One related assignment shows feedback and leaves normal saving available")
        let initialHeight = window.frame.height

        let actions = TextAction.allCases.filter { $0 != .changeCase(.lowercase) }
        for (action, modifier) in zip(actions, ShortcutModifier.allCases) {
            assignments[action] = .holdAndTapTwice(
                heldModifiers: chord.modifiers.subtracting(modifier.mask),
                tapKey: .modifier(modifier)
            )
        }
        editor.refresh()
        content.layoutSubtreeIfNeeded()
        let label = editor.feedback.label
        let text = label.attributedStringValue
        let wrapped = text.boundingRect(with: NSSize(width: label.bounds.width - 4, height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        try require(label.bounds.height + 1 >= wrapped.height && window.frame.height > initialHeight,
                    "A list of related assignments must fit without clipping")
        try require(actions.allSatisfy { text.string.contains($0.title) }, "All related actions must be visible")
        editor.showError("An invalid shortcut")
        content.layoutSubtreeIfNeeded()
        try require(editor.feedback.banner.borderWidth == 0 && window.frame.height < initialHeight,
                    "A one-line error must replace the taller blue banner")
        assignments = [.changeCase(.uppercase): related]
        editor.refresh()
        editor.savePressed()
        try require(saved == draft, "Related assignments must not require confirmation")
        print("PASS: related shortcuts use the shared banner and remain readable and savable")
    }

    static func runVisibleFeedbackTests() throws {
        guard let screen = NSScreen.main else { throw CocoaError(.featureUnsupported) }
        let visibleFrame = screen.visibleFrame
        let editor = TextShortcutEditorSheetController(
            action: .changeCase(.uppercase), currentShortcut: nil, shortcuts: { [:] },
            validate: { _ in .valid }, save: { _, _ in .updated },
            onRecordingChanged: { _ in }, onFinish: { _ in }
        )
        let window = editor.makeWindow()
        let parent = NSWindow(contentRect: NSRect(x: visibleFrame.midX - 300, y: visibleFrame.minY + 8,
                                                 width: 600, height: window.frame.height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        editor.sheetWindow = window
        parent.orderFront(nil)
        parent.setFrameOrigin(NSPoint(x: parent.frame.minX, y: visibleFrame.minY + 8))
        parent.beginSheet(window)
        defer { parent.endSheet(window); parent.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        window.makeFirstResponder(editor.captureBox)
        try require(window.isVisible && window.sheetParent === parent, "Feedback must be tested in a visible native sheet")

        editor.feedback.show("Related shortcuts", detail: [
            "Uppercase uses Hold ⌥⇧⌃ · Tap ⌘ ×2",
            "Lowercase uses Hold ⌥⇧⌘ · Tap ⌃ ×2",
            "Title Case uses Hold ⌥⌃⌘ · Tap ⇧ ×2",
            "Invert Case uses Hold ⌃⇧⌘ · Tap ⌥ ×2"
        ].joined(separator: "; "), style: .information)
        RunLoop.main.run(until: Date().addingTimeInterval(0.24))
        window.contentView?.layoutSubtreeIfNeeded()
        let initialBannerHeight = editor.feedback.banner.frame.height
        let expandedFrame = window.frame
        let button = window.convertToScreen(editor.saveButton.convert(editor.saveButton.bounds, to: nil))
        let controlsVisible = visibleFrame.contains(button)
        editor.showError("Choose a valid shortcut.")
        window.contentView?.layoutSubtreeIfNeeded()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try require(editor.feedback.banner.frame.height == initialBannerHeight && window.frame == expandedFrame,
                        "Replacing feedback must start banner and window resizing on the same frame")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.24))
        try require(editor.feedback.banner.frame.height < initialBannerHeight && window.frame.height < expandedFrame.height
                    && window.firstResponder === editor.captureBox,
                    "A shorter error must shrink the banner and window without losing focus")
        try require(controlsVisible, "The sheet must keep the action row visible above the Dock")
        print("PASS: native shortcut sheet keeps actions visible and resizes replacement feedback in sync")
    }

    fileprivate static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "ShortcutEditorKeyboardTests", code: 1,
                                     userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}

private final class EditorShortcutStore: TextActionShortcutStore {
    private var assignments: [TextAction: TextActionShortcut] = [:]

    func shortcut(for action: TextAction) -> TextActionShortcut? {
        assignments[action]
    }

    func setShortcut(_ shortcut: TextActionShortcut?, for action: TextAction) {
        assignments[action] = shortcut
    }
}

extension TextShortcutSettingsWindowController {
    static func runKeyboardTests() throws {
        let assignedAction = TextAction.allCases[0]
        var assignedShortcut: TextActionShortcut? = .holdAndTapTwice(
            heldModifiers: [.shift, .control, .option, .command],
            tapKey: .function(.init(rawValue: 20)!)
        )
        let controller = TextShortcutSettingsWindowController(
            shortcut: { $0 == assignedAction ? assignedShortcut : nil },
            validateShortcut: { _, _ in .valid },
            setShortcut: { shortcut, _, _ in
                assignedShortcut = shortcut
                return .updated
            },
            onRecordingChanged: { _ in }
        )
        let window = controller.makeWindow()
        controller.settingsWindow = window
        controller.refreshContent()
        defer { window.orderOut(nil) }

        func rows() -> [NSStackView] {
            let stack = window.contentView!.subviews[0] as! NSStackView
            return (stack.arrangedSubviews[1] as! NSStackView).arrangedSubviews.map { $0 as! NSStackView }
        }

        let firstRow = rows()[0]
        let firstEdit = firstRow.arrangedSubviews[2] as! NSButton
        let firstClear = firstRow.arrangedSubviews[3] as! NSButton
        let secondEdit = rows()[1].arrangedSubviews[2] as! NSButton
        let secondClear = rows()[1].arrangedSubviews[3] as! NSButton
        let thirdEdit = rows()[2].arrangedSubviews[2] as! NSButton
        let content = window.contentView!
        content.layoutSubtreeIfNeeded()
        try TextShortcutEditorSheetController.require(window.firstResponder === content, "The list must open without a focused action")
        try TextShortcutEditorSheetController.require(
            content.nextKeyView === firstEdit && firstEdit.nextKeyView === firstClear
                && firstClear.nextKeyView === secondEdit && secondEdit.nextKeyView === secondClear
                && secondClear.nextKeyView === thirdEdit && !secondClear.isEnabled,
            "The settings focus loop must follow row order and disable Clear for unassigned actions"
        )
        let canTabToButtons = NSApp.isFullKeyboardAccessEnabled
        if canTabToButtons {
            window.selectNextKeyView(content)
            try TextShortcutEditorSheetController.require(window.firstResponder === firstEdit, "Tab must reach the first edit button")
            window.selectNextKeyView(firstEdit)
            try TextShortcutEditorSheetController.require(window.firstResponder === firstClear, "Tab must reach the corresponding Clear button")
            window.selectNextKeyView(firstClear)
            try TextShortcutEditorSheetController.require(window.firstResponder === secondEdit, "Tab must continue in row order")
            window.selectNextKeyView(secondEdit)
            try TextShortcutEditorSheetController.require(window.firstResponder === thirdEdit, "Tab must skip a disabled Clear button")
            window.selectPreviousKeyView(thirdEdit)
            try TextShortcutEditorSheetController.require(window.firstResponder === secondEdit, "Shift+Tab must follow the reverse row order")
        } else {
            print("macOS keyboard navigation is off; verified the configured focus loop and disabled controls")
        }
        controller.clearShortcut(firstClear)
        let refreshedRow = rows()[0]
        let firstSet = refreshedRow.arrangedSubviews[2] as! NSButton
        let disabledClear = refreshedRow.arrangedSubviews[3] as! NSButton
        try TextShortcutEditorSheetController.require(!disabledClear.isEnabled,
                                                       "Clearing a shortcut must disable Clear")
        if canTabToButtons {
            try TextShortcutEditorSheetController.require(window.firstResponder === firstSet,
                                                           "Clearing a shortcut must return keyboard focus to its Set button")
        }
        var returnTargets: [String] = []
        controller.showWindow(returningTo: { returnTargets.append("first") })
        controller.showWindow(returningTo: { returnTargets.append("latest") })
        controller.showWindow()
        window.performClose(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        try TextShortcutEditorSheetController.require(returnTargets == ["latest"],
                                                       "Closing a reused shortcut window must restore the latest source")
        print("PASS: shortcut settings focus loop, disabled controls and return to source")
    }
}

@main struct ShortcutEditorKeyboardTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try TextShortcutEditorSheetController.runKeyboardTests()
            try TextShortcutEditorSheetController.runInlineConflictTests()
            try TextShortcutEditorSheetController.runRelatedAssignmentsTests()
            try TextShortcutSettingsWindowController.runKeyboardTests()
            try TextShortcutEditorSheetController.runVisibleFeedbackTests()
        }
        catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
