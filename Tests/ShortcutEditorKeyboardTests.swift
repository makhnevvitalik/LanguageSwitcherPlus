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
            shortcuts: { [:] }, validate: { _ in .valid }, checkConflict: { _ in nil },
            save: { _ in saves += 1; return .updated },
            onRecordingChanged: { _ in }, onFinish: { finished = $0 }
        )
        let window = editor.makeWindow()
        editor.sheetWindow = window
        editor.refresh()
        defer { window.orderOut(nil) }
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
        try require(editor.feedbackBanner.isHidden, "Navigation must not show an invalid-shortcut error")
        let f1Inside = keyEvent(.keyDown, key: 122, window: window)
        try require(editor.handleKeyDown(f1Inside) == nil && editor.draft != nil,
                    "Focused capture area must still record F1")
        try require(editor.captureBox.borderWidth == 2, "Focused capture must be highlighted")
        let savedDraft = editor.draft
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
        try require(editor.draft == previousDraft && !editor.feedbackBanner.isHidden,
                    "Shift plus a letter is rejected without recording Shift alone")
        let letter = TextShortcutKey.alphanumeric(ShortcutAlphanumericKey(rawValue: "K")!)
        for characters in ["k", "л"] {
            _ = editor.handleKeyDown(keyEvent(.keyDown, key: 40, flags: .command, characters: characters, window: window))
            try require(editor.draft == .once(TextShortcutChord(modifiers: .command, key: letter))
                        && editor.shortcutValueLabel.stringValue == "⌘K ×1",
                        "The editor must record and display the physical key in either layout")
        }
        let beforeFn = editor.draft
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 63, flags: .function, window: window))
        try require(!editor.feedbackBanner.isHidden && !editor.saveButton.isEnabled,
                    "Pressing Fn by itself must immediately show an error")
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 58, flags: [.option, .function], window: window))
        _ = editor.handleKeyDown(keyEvent(.keyDown, key: 40, flags: [.option, .function], window: window))
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 58, flags: [.function], window: window))
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 63, window: window))
        try require(editor.draft == beforeFn && !editor.feedbackBanner.isHidden,
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
        try require(editor.draft == previousHold && !editor.feedbackBanner.isHidden && !editor.saveButton.isEnabled,
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
        let copy = TextActionShortcut.once(TextShortcutChord(
            modifiers: .command, key: .alphanumeric(.init(rawValue: "C")!)
        ))
        for conflict in [
            TextShortcutConflict.system, .documentedSystemCommand("Toggle Dock"), .commonCommand("Copy")
        ] {
            var detected: TextShortcutConflict? = conflict
            var saved: TextActionShortcut?
            let editor = TextShortcutEditorSheetController(
                action: .changeCase(.uppercase), currentShortcut: nil,
                shortcuts: { [:] }, validate: { _ in .valid }, checkConflict: { _ in detected },
                save: { saved = $0; return .updated }, onRecordingChanged: { _ in }, onFinish: { _ in }
            )
            let window = editor.makeWindow()
            editor.sheetWindow = window
            editor.refresh()
            window.makeFirstResponder(editor.captureBox)
            defer { editor.cancel(); window.orderOut(nil) }

            let view = window.contentView!
            view.layoutSubtreeIfNeeded()
            let initialSize = view.bounds.size
            let initialField = editor.captureBox.frame
            try require(editor.feedbackSlot.frame.height == 46 && editor.feedbackBanner.isHidden,
                        "The editor must reserve 46 points before showing feedback")
            let initialButtons = editor.saveButton.superview!.frame.minY

            _ = editor.handleKeyDown(keyEvent(.keyDown, key: 8, flags: .command, window: window))
            view.layoutSubtreeIfNeeded()
            try require(editor.draft == copy && window.attachedSheet == nil,
                        "Conflicts must appear in the editor after recording")
            try require(!editor.feedbackBanner.isHidden && editor.feedbackSlot.frame.height == 46,
                        "A conflict must be visible in the reserved feedback slot")
            let conflictMessage = editor.feedbackLabel.stringValue
            try require(editor.saveButton.isEnabled == (conflict != .system),
                        "Only an enabled macOS shortcut must be blocked")
            try require(view.bounds.size == initialSize && editor.captureBox.frame == initialField
                        && editor.saveButton.superview!.frame.minY == initialButtons,
                        "Showing feedback must not move the field or buttons vertically")

            let enter = keyEvent(.keyDown, key: 36, window: window)
            _ = editor.handleKeyDown(enter)
            try require(saved == nil && editor.feedbackLabel.stringValue == conflictMessage,
                        "Return in the capture field must leave the conflict visible without saving")

            if conflict == .system {
                editor.savePressed()
                try require(saved == nil, "The enabled system shortcut must never be saved")
                detected = nil
                _ = editor.handleKeyDown(keyEvent(.keyDown, key: 122, window: window))
                try require(editor.saveButton.title == "Save" && editor.saveButton.isEnabled,
                            "Recording a different shortcut must restore ordinary saving")
            } else {
                try require(editor.saveButton.title == "Assign Anyway" && editor.saveButton.keyEquivalent.isEmpty,
                            "An inline warning must require an explicit Assign Anyway action")
                editor.savePressed()
                try require(saved == copy && editor.didFinish && window.attachedSheet == nil,
                            "Assign Anyway must save from the current editor without opening another sheet")
            }
        }

        var conflict: TextShortcutConflict?
        var saved = false
        let editor = TextShortcutEditorSheetController(
            action: .changeCase(.uppercase), currentShortcut: copy,
            shortcuts: { [:] }, validate: { _ in .valid }, checkConflict: { _ in conflict },
            save: { _ in saved = true; return .updated }, onRecordingChanged: { _ in }, onFinish: { _ in }
        )
        let window = editor.makeWindow()
        editor.sheetWindow = window
        editor.refresh()
        defer { editor.cancel(); window.orderOut(nil) }

        conflict = .commonCommand("Copy")
        editor.savePressed()
        try require(!saved && editor.saveButton.title == "Assign Anyway",
                    "A newly detected warning must be displayed before the user can accept it")

        conflict = .system
        editor.savePressed()
        try require(!saved && !editor.saveButton.isEnabled,
                    "A system shortcut that becomes enabled before saving must be blocked")
        print("PASS: inline conflict warnings, system blocking, keyboard confirmation and stable layout")
    }

    private static func keyEvent(_ type: NSEvent.EventType, key: UInt16,
                                 flags: NSEvent.ModifierFlags = [], characters: String = "", window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: key)!
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "ShortcutEditorKeyboardTests", code: 1,
                                     userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}

@main struct ShortcutEditorKeyboardTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try TextShortcutEditorSheetController.runKeyboardTests()
            try TextShortcutEditorSheetController.runInlineConflictTests()
        }
        catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
