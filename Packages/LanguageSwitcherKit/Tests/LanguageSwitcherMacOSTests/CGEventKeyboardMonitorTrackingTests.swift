// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
@testable import LanguageSwitcherMacOS
import XCTest

final class CGEventKeyboardMonitorTrackingTests: XCTestCase {
    func testBackspaceRemovesOneTrackedCharacter() throws {
        for flags: NSEvent.ModifierFlags in [[], .shift] {
            let (monitor, buffer) = makeMonitor()
            try type("one tw👩‍💻", into: monitor)

            try sendKeyDown(keyCode: 51, characters: "\u{7f}", flags: flags, to: monitor)

            let snapshot = try XCTUnwrap(buffer.snapshot(for: "editor"))
            XCTAssertEqual(snapshot.text, "one tw")
            XCTAssertEqual(snapshot.inputs.map(\.text).joined(), "one tw")
        }
    }

    func testModifiedBackspaceInvalidatesTrackedText() throws {
        for flags in modifiedBackspaceFlags {
            let (monitor, buffer) = makeMonitor()
            try type("one two", into: monitor)
            XCTAssertNotNil(buffer.snapshot(for: "editor"))

            try sendKeyDown(keyCode: 51, characters: "\u{7f}", flags: flags, to: monitor)

            XCTAssertNil(buffer.snapshot(for: "editor"), "Modifier flags: \(flags.rawValue)")
        }
    }

    func testTypingAfterModifiedBackspaceStartsFreshTrackedText() throws {
        for flags in modifiedBackspaceFlags {
            let (monitor, buffer) = makeMonitor()
            try type("one two", into: monitor)
            let previous = try XCTUnwrap(buffer.snapshot(for: "editor"))
            try sendKeyDown(keyCode: 51, characters: "\u{7f}", flags: flags, to: monitor)

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

    private func makeMonitor() -> (CGEventKeyboardMonitor, TrackedTextBuffer) {
        let buffer = TrackedTextBuffer()
        let monitor = CGEventKeyboardMonitor(
            modifierShortcuts: [],
            maximumModifierTapDuration: 0.2,
            maximumTextShortcutMultiPressInterval: 0.3,
            textShortcuts: [:],
            trackedTextBuffer: buffer,
            contextTracker: InputContextTracker(),
            applicationProvider: TrackingApplicationProvider(),
            onModifierTrigger: { XCTFail("Unexpected input-source switch") },
            onTextAction: { _ in XCTFail("Unexpected text action") },
            onUnavailable: { XCTFail("No event tap should be started") }
        )
        return (monitor, buffer)
    }

    private func type(_ text: String, into monitor: CGEventKeyboardMonitor) throws {
        for character in text {
            try sendKeyDown(keyCode: 0, characters: String(character), to: monitor)
        }
    }

    private func sendKeyDown(
        keyCode: UInt16,
        characters: String,
        flags: NSEvent.ModifierFlags = [],
        to monitor: CGEventKeyboardMonitor
    ) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )?.cgEvent)
        monitor.handle(type: .keyDown, event: event)
    }
}

private final class TrackingApplicationProvider: FrontmostApplicationProviding {
    var applicationID: String? { "editor" }
}
