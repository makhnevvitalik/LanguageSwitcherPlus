// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Carbon
import LanguageSwitcherDomain
@testable import LanguageSwitcherMacOS
import XCTest

final class TextShortcutConflictDetectorTests: XCTestCase {
    func testAppleFormattingCommandsWarnWithoutSystemRegistration() {
        let expected = ["B": "Bold", "I": "Italic or Show File Info", "U": "Underline"]
        for (letter, command) in expected {
            XCTAssertEqual(TextShortcutConflictDetector.conflict(
                for: makeShortcut(letter, modifiers: .command), entries: []), .commonCommand(command))
        }
    }

    func testDvorakCommandWarningsUseCharactersAndSystemEntriesUsePhysicalKeys() throws {
        let layout = try keyboardLayout("Dvorak")

        XCTAssertEqual(TextShortcutConflictDetector.conflict(
            for: makeShortcut("I", modifiers: .command), entries: [], layoutData: layout), .commonCommand("Copy"))
        XCTAssertEqual(TextShortcutConflictDetector.conflict(
            for: makeShortcut("C", modifiers: .command), entries: [], layoutData: layout), .commonCommand("Show Finder View Options"))
        XCTAssertEqual(TextShortcutConflictDetector.conflict(for: makeShortcut("C", modifiers: .command),
            entries: [entry(kVK_ANSI_C, cmdKey, enabled: true)], layoutData: layout), .system)
        XCTAssertEqual(TextShortcutConflictDetector.conflict(for: makeShortcut("Z", modifiers: .command),
            entries: [], layoutData: layout), .commonCommand("Find Misspelled Words"))
        XCTAssertEqual(TextShortcutConflictDetector.conflict(for: makeShortcut("Z", modifiers: [.command, .shift]),
            entries: [], layoutData: layout), .commonCommand("Spelling and Grammar"))
    }

    func testFrenchWarningsHandleShiftedDigitsAndDoNotReplaceAccentedCharactersWithUSKeys() throws {
        let french = try keyboardLayout("French")
        let us = try keyboardLayout("US")
        let commandTwo = makeShortcut("2", modifiers: .command)
        XCTAssertNil(TextShortcutConflictDetector.conflict(
            for: commandTwo, entries: [], layoutData: french, fallbackLayoutData: us))
        XCTAssertEqual(TextShortcutConflictDetector.conflict(
            for: commandTwo, entries: [], fallbackLayoutData: us), .commonCommand("Finder List View"))
        XCTAssertEqual(TextShortcutConflictDetector.conflict(
            for: makeShortcut("1", modifiers: [.command, .shift]), entries: [], layoutData: french),
            .commonCommand("Finder Icon View"))
        XCTAssertEqual(TextShortcutConflictDetector.conflict(
            for: makeShortcut("2", modifiers: [.command, .shift]), entries: [], layoutData: french),
            .commonCommand("Finder List View"))
    }

    func testRussianCommandUsesTheActiveLayoutsCommandMapping() throws {
        let russian = try keyboardLayout("Russian")
        XCTAssertEqual(TextShortcutConflictDetector.conflict(
            for: makeShortcut("C", modifiers: .command), entries: [], layoutData: russian), .commonCommand("Copy"))
    }

    func testFinderAndTextEditingCommandsAreIncluded() {
        let samples: [(String, KeyModifiers, String)] = [
            ("4", .command, "Finder Gallery View"),
            ("H", [.command, .option], "Hide Other Apps"),
            ("T", [.command, .control, .shift], "Add Finder Item to Dock"),
            ("V", [.command, .option, .shift], "Paste and Match Style"),
            ("Y", .control, "Paste Text Cut With Control-K")
        ]
        for (key, modifiers, command) in samples {
            XCTAssertEqual(TextShortcutConflictDetector.conflict(
                for: makeShortcut(key, modifiers: modifiers), entries: []), .commonCommand(command))
        }
    }

    func testEnabledSystemChordTakesPrecedenceAndDisabledEntryFallsBackToCommonCommand() {
        let copy = makeShortcut("C", modifiers: .command)
        XCTAssertEqual(TextShortcutConflictDetector.conflict(
            for: copy, entries: [entry(kVK_ANSI_C, cmdKey, enabled: true)]), .system)
        XCTAssertEqual(TextShortcutConflictDetector.conflict(
            for: copy, entries: [entry(kVK_ANSI_C, cmdKey, enabled: false)]), .commonCommand("Copy"))
        XCTAssertEqual(TextShortcutConflictDetector.conflict(
            for: copy, entries: [entry(kVK_ANSI_C, cmdKey | shiftKey, enabled: true)]), .commonCommand("Copy"))
    }

    func testSystemConflictUsesPhysicalChordForHeldGesture() {
        let digit = TextShortcutKey.alphanumeric(.init(rawValue: "3")!)
        let held = TextActionShortcut.holdAndTapTwice(heldModifiers: [.command, .shift], tapKey: digit)
        XCTAssertEqual(TextShortcutConflictDetector.conflict(
            for: held, entries: [entry(kVK_ANSI_3, cmdKey | shiftKey, enabled: true)]), .system)
        XCTAssertEqual(TextShortcutConflictDetector.conflict(
            for: held, entries: [entry(kVK_ANSI_3, cmdKey, enabled: true)]),
            .documentedSystemCommand("Capture Entire Screen"))
        XCTAssertNil(TextShortcutConflictDetector.conflict(
            for: held, entries: [entry(kVK_ANSI_3, cmdKey | shiftKey, enabled: false)]))
    }

    func testStandardFunctionAndDoubleCommandShortcutsCannotBeMistakenForVerifiedAssignments() {
        let focusMenu = TextActionShortcut.once(TextShortcutChord(
            modifiers: .control, functionKey: .init(rawValue: 2)
        ))
        let doubleCommand = TextActionShortcut.repeatTwice(TextShortcutChord(modifiers: .command, functionKey: nil))
        XCTAssertEqual(TextShortcutConflictDetector.conflict(for: focusMenu, entries: []),
                       .documentedSystemCommand("Focus Menu Bar"))
        XCTAssertEqual(TextShortcutConflictDetector.conflict(for: doubleCommand, entries: []),
                       .documentedSystemCommand("Type to Siri"))
        XCTAssertNil(TextShortcutConflictDetector.conflict(
            for: .once(TextShortcutChord(modifiers: .command, functionKey: nil)), entries: []))
    }

    private func makeShortcut(_ letter: String, modifiers: KeyModifiers) -> TextActionShortcut {
        .once(TextShortcutChord(modifiers: modifiers, key: .alphanumeric(.init(rawValue: letter)!)))
    }

    private func keyboardLayout(_ name: String) throws -> Data {
        let sources = TISCreateInputSourceList(
            [kTISPropertyInputSourceID as String: "com.apple.keylayout.\(name)"] as CFDictionary, true
        ).takeRetainedValue() as NSArray
        let source = (try XCTUnwrap(sources.firstObject)) as! TISInputSource
        let property = try XCTUnwrap(TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData))
        return Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
    }

    private func entry(_ key: Int, _ modifiers: Int, enabled: Bool) -> [String: Any] {
        [kHISymbolicHotKeyCode as String: key,
         kHISymbolicHotKeyModifiers as String: modifiers,
         kHISymbolicHotKeyEnabled as String: enabled]
    }
}
