// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import LanguageSwitcherDomain
@testable import LanguageSwitcherMacOS
import XCTest

final class CGEventKeyboardMonitorTrackingTests: XCTestCase {
    func testStartUsesTheConfiguredInputMonitoringPermission() {
        let monitor = CGEventKeyboardMonitor(
            modifierShortcuts: [], maximumModifierTapDuration: 0.2,
            maximumTextShortcutMultiPressInterval: 0.3, textShortcuts: [:],
            trackedTextBuffer: TrackedTextBuffer(), contextTracker: InputContextTracker(),
            applicationProvider: TrackingApplicationProvider(), onModifierTrigger: {}, onTextAction: { _ in },
            onUnavailable: {}, inputMonitoringPermission: DeniedInputMonitoringPermission()
        )
        XCTAssertFalse(monitor.start())
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(monitor.textShortcutInterception, .inactive)
    }

    func testInterceptedDoublePressConsumesWholeKeyPressAndPreservesTypedText() throws {
        let chord = TextShortcutChord(modifiers: .control, key: .alphanumeric(.init(rawValue: "K")!))
        for characters in ["k", "л"] {
            var activations: [String] = []
            let context = InputContextTracker()
            let (monitor, buffer) = makeMonitor(
                shortcuts: [.convertToNextLayout: .repeatTwice(chord)],
                contextTracker: context,
                diagnostics: { if $0.hasPrefix("shortcut.activated") { activations.append($0) } }
            )
            try type("example", into: monitor)
            let generation = context.generation

            XCTAssertTrue(try sendKey(keyCode: 40, characters: characters, flags: .control,
                                      intercept: true, to: monitor))
            XCTAssertTrue(try sendKey(keyCode: 40, characters: characters, isRepeat: true,
                                      intercept: true, to: monitor))
            XCTAssertTrue(try sendKey(keyCode: 40, characters: characters, type: .keyUp,
                                      intercept: true, to: monitor))
            XCTAssertTrue(activations.isEmpty)
            XCTAssertTrue(try sendKey(keyCode: 40, characters: characters, flags: .control,
                                      intercept: true, to: monitor))
            XCTAssertTrue(try sendKey(keyCode: 40, characters: characters, type: .keyUp,
                                      intercept: true, to: monitor))
            XCTAssertEqual(activations.count, 1)
            XCTAssertEqual(buffer.snapshot(for: "editor")?.text, "example")
            XCTAssertEqual(context.generation, generation)
        }
    }

    func testUnownedPressAndItsRepeatAndReleasePassThrough() throws {
        let chord = TextShortcutChord(modifiers: .control, key: .alphanumeric(.init(rawValue: "K")!))
        let (monitor, buffer) = makeMonitor(shortcuts: [.convertToNextLayout: .once(chord)])

        XCTAssertFalse(try sendKey(keyCode: 40, characters: "k", intercept: true, to: monitor))
        XCTAssertEqual(buffer.snapshot(for: "editor")?.text, "k")
        XCTAssertFalse(try sendKey(keyCode: 40, characters: "k", flags: .control,
                                   isRepeat: true, intercept: true, to: monitor))
        XCTAssertFalse(try sendKey(keyCode: 40, characters: "k", flags: .control,
                                   type: .keyUp, intercept: true, to: monitor))
        XCTAssertFalse(try sendKey(keyCode: 40, characters: "k", flags: [.control, .shift],
                                   intercept: true, to: monitor))
        XCTAssertFalse(try sendKey(keyCode: 40, characters: "k", flags: [.control, .function],
                                   intercept: true, to: monitor))
    }

    func testConfiguredLetterPassesThroughWithoutRecognizingGestureWhenInterceptionIsUnavailable() throws {
        let key = TextShortcutKey.alphanumeric(ShortcutAlphanumericKey(rawValue: "K")!)
        let chord = TextShortcutChord(modifiers: .control, key: key)
        for characters in ["k", "л"] {
            var activations: [String] = []
            let context = InputContextTracker()
            let (monitor, buffer) = makeMonitor(
                shortcuts: [.convertToNextLayout: .repeatTwice(chord)],
                contextTracker: context,
                diagnostics: { message in
                    if message.hasPrefix("shortcut.activated") { activations.append(message) }
                }
            )
            try type("example", into: monitor)
            try sendKey(keyCode: 40, characters: characters, to: monitor)
            XCTAssertEqual(buffer.snapshot(for: "editor")?.text, "example" + characters)
            try sendKey(keyCode: 40, characters: characters, type: .keyUp, to: monitor)
            let generationBeforeShortcut = context.generation
            XCTAssertFalse(try sendKey(keyCode: 40, characters: characters, flags: .control, to: monitor))
            XCTAssertNil(buffer.snapshot(for: "editor"))
            try sendKey(keyCode: 40, characters: characters, type: .keyUp, to: monitor)
            XCTAssertTrue(activations.isEmpty)
            try sendKey(keyCode: 40, characters: characters, flags: .control, to: monitor)
            try sendKey(keyCode: 40, characters: characters, type: .keyUp, to: monitor)
            XCTAssertEqual(context.generation, generationBeforeShortcut + 2)
            XCTAssertTrue(activations.isEmpty, "The foreground app received both presses")
        }
    }

    func testBackspaceRemovesOneTrackedCharacter() throws {
        for flags: NSEvent.ModifierFlags in [[], .shift] {
            let (monitor, buffer) = makeMonitor()
            try type("one two", into: monitor)

            try sendKey(keyCode: 51, characters: "\u{7f}", flags: flags, to: monitor)

            let snapshot = try XCTUnwrap(buffer.snapshot(for: "editor"))
            XCTAssertEqual(snapshot.text, "one tw")
            XCTAssertEqual(snapshot.inputs.map(\.text).joined(), "one tw")
        }
    }

    func testTracksTextAcrossEmojiAndJoinerEvents() throws {
        let cases: [([String], String)] = [
            (["hello ", "👩‍💻", " world"], "hello 👩‍💻 world"),
            (["hello ", "👩", "\u{200D}", "💻", " world"], "hello 👩‍💻 world"),
            (["text ", "می", "\u{200C}", "روم"], "text می‌روم"),
            (["flag ", "🏴", "\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"],
             "flag 🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}")
        ]
        for (events, expected) in cases {
            let (monitor, buffer) = makeMonitor()
            for text in events {
                try sendKey(keyCode: 0, characters: text, to: monitor)
            }
            XCTAssertEqual(buffer.snapshot(for: "editor")?.text, expected)
        }
    }

    func testControlCharacterStillClearsTrackedText() throws {
        let (monitor, buffer) = makeMonitor()
        try type("text", into: monitor)

        try sendKey(keyCode: 0, characters: "\u{001B}", to: monitor)

        XCTAssertNil(buffer.snapshot(for: "editor"))
    }

    func testModifiedBackspaceInvalidatesTrackedText() throws {
        for flags in modifiedBackspaceFlags {
            let (monitor, buffer) = makeMonitor()
            try type("one two", into: monitor)
            XCTAssertNotNil(buffer.snapshot(for: "editor"))

            try sendKey(keyCode: 51, characters: "\u{7f}", flags: flags, to: monitor)

            XCTAssertNil(buffer.snapshot(for: "editor"), "Modifier flags: \(flags.rawValue)")
        }
    }

    func testTypingAfterModifiedBackspaceStartsFreshTrackedText() throws {
        for flags in modifiedBackspaceFlags {
            let (monitor, buffer) = makeMonitor()
            try type("one two", into: monitor)
            let previous = try XCTUnwrap(buffer.snapshot(for: "editor"))
            try sendKey(keyCode: 51, characters: "\u{7f}", flags: flags, to: monitor)

            try type("new", into: monitor)

            let current = try XCTUnwrap(buffer.snapshot(for: "editor"))
            XCTAssertFalse(buffer.isCurrent(previous))
            XCTAssertEqual(current.text, "new", "Modifier flags: \(flags.rawValue)")
            XCTAssertEqual(current.inputs.map(\.text).joined(), "new")
        }
    }

    private var modifiedBackspaceFlags: [NSEvent.ModifierFlags] {
        let modifiers: [NSEvent.ModifierFlags] = [.option, .command, .control, .function]
        return modifiers + modifiers.map { $0.union(.shift) }
    }

    private func makeMonitor(
        shortcuts: [TextAction: TextActionShortcut] = [:],
        contextTracker: InputContextTracker = InputContextTracker(),
        diagnostics: ((String) -> Void)? = nil
    ) -> (CGEventKeyboardMonitor, TrackedTextBuffer) {
        let buffer = TrackedTextBuffer()
        let monitor = CGEventKeyboardMonitor(
            modifierShortcuts: [],
            maximumModifierTapDuration: 0.2,
            maximumTextShortcutMultiPressInterval: 0.3,
            textShortcuts: shortcuts,
            trackedTextBuffer: buffer,
            contextTracker: contextTracker,
            applicationProvider: TrackingApplicationProvider(),
            onModifierTrigger: { XCTFail("Unexpected input-source switch") },
            onTextAction: { _ in XCTFail("An offscreen monitor must not dispatch a text action") },
            onUnavailable: { XCTFail("No event tap should be started") },
            diagnostics: diagnostics
        )
        return (monitor, buffer)
    }

    private func type(_ text: String, into monitor: CGEventKeyboardMonitor) throws {
        for character in text {
            try sendKey(keyCode: 0, characters: String(character), to: monitor)
        }
    }

    @discardableResult
    private func sendKey(
        keyCode: UInt16,
        characters: String,
        flags: NSEvent.ModifierFlags = [],
        type: NSEvent.EventType = .keyDown,
        isRepeat: Bool = false,
        intercept: Bool = false,
        to monitor: CGEventKeyboardMonitor
    ) throws -> Bool {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isRepeat,
            keyCode: keyCode
        )?.cgEvent)
        let utf16 = Array(characters.utf16)
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        return monitor.handle(type: type == .keyDown ? .keyDown : .keyUp, event: event,
                              interceptionAllowed: intercept)
    }
}

private final class DeniedInputMonitoringPermission: InputMonitoringPermissionChecking {
    let isAllowed = false
}

private final class TrackingApplicationProvider: FrontmostApplicationProviding {
    var applicationID: String? { "editor" }
}
