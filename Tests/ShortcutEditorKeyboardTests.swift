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
        try require(editor.errorLabel.isHidden, "Navigation must not show an invalid-shortcut error")
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

        editor.selectPattern(.holdAndTapTwice)
        editor.handleFlagsChanged(keyEvent(.flagsChanged, key: 56, flags: [.shift], window: window))
        _ = editor.handleKeyDown(keyEvent(.keyDown, key: 122, flags: [.shift], window: window))
        _ = editor.handleKeyUp(keyEvent(.keyUp, key: 122, flags: [.shift], window: window))
        try require(editor.draft?.isValidGlobalShortcut == true,
                    "Hold-and-tap shortcuts must still record in the capture area")
        window.makeFirstResponder(radio)
        let enter = keyEvent(.keyDown, key: 36, window: window)
        try require(editor.handleKeyDown(enter) === enter && saves == 0,
                    "Enter outside capture must remain available to native default-button handling")
        window.makeFirstResponder(editor.captureBox)
        try require(editor.handleKeyDown(enter) == nil && saves == 1 && finished == true,
                    "Enter in capture must still save a valid shortcut")
        print("PASS: shortcut editor focus, navigation, capture and unfinished-gesture cancellation")
    }

    private static func keyEvent(_ type: NSEvent.EventType, key: UInt16,
                                 flags: NSEvent.ModifierFlags = [], window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: key)!
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "ShortcutEditorKeyboardTests", code: 1,
                                     userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}

@main struct ShortcutEditorKeyboardTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do { try TextShortcutEditorSheetController.runKeyboardTests() }
        catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
