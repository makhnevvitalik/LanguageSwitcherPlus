// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation
import LanguageSwitcherDomain
import XCTest

final class TextActionShortcutTests: XCTestCase {
    func testAlphanumericKeysRequireControlOptionOrCommandInEveryGesture() {
        for rawValue in ["A", "Z", "0", "9"] {
            let key = TextShortcutKey.alphanumeric(ShortcutAlphanumericKey(rawValue: rawValue)!)
            for rawModifiers in UInt64(0)...15 {
                let modifiers = KeyModifiers(rawValue: rawModifiers)
                let allowed = modifiers != [] && modifiers != .shift
                let chord = TextShortcutChord(modifiers: modifiers, key: key)
                XCTAssertEqual(TextActionShortcut.once(chord).isValidGlobalShortcut, allowed)
                XCTAssertEqual(TextActionShortcut.repeatTwice(chord).isValidGlobalShortcut, allowed)
                XCTAssertEqual(TextActionShortcut.holdAndTapTwice(
                    heldModifiers: modifiers,
                    tapKey: key
                ).isValidGlobalShortcut, allowed)
            }
        }
        for unsupported in ["", "a", "Ж", "!", "10"] {
            XCTAssertNil(ShortcutAlphanumericKey(rawValue: unsupported))
        }
    }

    func testDecodesExistingShortcutWithoutAlphanumericKey() throws {
        let stored = Data(#"{"once":{"_0":{"modifiers":4,"functionKey":13}}}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(TextActionShortcut.self, from: stored),
            .once(TextShortcutChord(modifiers: .control, functionKey: ShortcutFunctionKey(rawValue: 13)))
        )
    }

    func testSupportsFunctionKeysOneThroughTwenty() {
        XCTAssertEqual(ShortcutFunctionKey(rawValue: 1)?.rawValue, 1)
        XCTAssertEqual(ShortcutFunctionKey(rawValue: 20)?.rawValue, 20)
        XCTAssertNil(ShortcutFunctionKey(rawValue: 0))
        XCTAssertNil(ShortcutFunctionKey(rawValue: 21))
    }

    func testClassicChordRequiresSupportedModifierOrFunctionKey() {
        XCTAssertFalse(TextShortcutChord(modifiers: [], functionKey: nil).isValid)
        XCTAssertTrue(TextShortcutChord(modifiers: .shift, functionKey: nil).isValid)
        XCTAssertTrue(TextShortcutChord(
            modifiers: [],
            functionKey: ShortcutFunctionKey(rawValue: 20)
        ).isValid)
        XCTAssertFalse(TextShortcutChord(
            modifiers: .function,
            functionKey: nil
        ).isValid)
    }

    func testHoldAndTapRequiresHeldModifierAndDifferentTapModifier() {
        XCTAssertFalse(TextActionShortcut.holdAndTapTwice(
            heldModifiers: [],
            tapKey: .modifier(.option)
        ).isValidGlobalShortcut)
        XCTAssertFalse(TextActionShortcut.holdAndTapTwice(
            heldModifiers: .option,
            tapKey: .modifier(.option)
        ).isValidGlobalShortcut)
        XCTAssertTrue(TextActionShortcut.holdAndTapTwice(
            heldModifiers: .shift,
            tapKey: .modifier(.option)
        ).isValidGlobalShortcut)
    }

    func testGestureTypesUsingSameKeysRemainDistinct() {
        let chord = TextShortcutChord(modifiers: [.shift, .option], functionKey: nil)

        XCTAssertNotEqual(
            TextActionShortcut.once(chord),
            TextActionShortcut.repeatTwice(chord)
        )
        XCTAssertNotEqual(
            TextActionShortcut.holdAndTapTwice(
                heldModifiers: .shift,
                tapKey: .modifier(.option)
            ),
            TextActionShortcut.holdAndTapTwice(
                heldModifiers: .option,
                tapKey: .modifier(.shift)
            )
        )
    }

    func testClassicChordIsAvailableOnlyForClassicGestures() {
        let chord = TextShortcutChord(
            modifiers: .control,
            functionKey: ShortcutFunctionKey(rawValue: 13)
        )

        XCTAssertEqual(TextActionShortcut.once(chord).classicChord, chord)
        XCTAssertEqual(TextActionShortcut.repeatTwice(chord).classicChord, chord)
        XCTAssertNil(TextActionShortcut.holdAndTapTwice(
            heldModifiers: .control,
            tapKey: .function(ShortcutFunctionKey(rawValue: 13)!)
        ).classicChord)
    }
}
