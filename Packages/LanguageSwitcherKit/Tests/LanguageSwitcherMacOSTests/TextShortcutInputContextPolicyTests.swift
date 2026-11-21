// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import LanguageSwitcherDomain
import XCTest
@testable import LanguageSwitcherMacOS

final class TextShortcutInputContextPolicyTests: XCTestCase {
    func testAlphanumericKeyDownRequiresExactConfiguredModifiers() {
        let key = TextShortcutKey.alphanumeric(ShortcutAlphanumericKey(rawValue: "A")!)
        let policy = TextShortcutInputContextPolicy(shortcuts: [
            .convertToNextLayout: .once(TextShortcutChord(modifiers: .control, key: key))
        ])
        for modifiers: KeyModifiers in [[], .shift, .option, .control, [.control, .shift]] {
            let event = TextShortcutInputEvent.keyDown(
                key, activeModifiers: modifiers, timestamp: 1, isRepeat: false
            )
            XCTAssertEqual(policy.shouldPreserveContext(for: event), modifiers == .control)
        }
    }

    func testClassicFunctionKeyPreservesContextOnlyForExactConfiguredKeyDown() {
        let f13 = ShortcutFunctionKey(rawValue: 13)!
        let f14 = ShortcutFunctionKey(rawValue: 14)!
        let policy = TextShortcutInputContextPolicy(shortcuts: [
            .convertToNextLayout: .once(TextShortcutChord(
                modifiers: .control,
                functionKey: f13
            ))
        ])

        XCTAssertTrue(policy.shouldPreserveContext(for: .keyDown(
            .function(f13), activeModifiers: .control, timestamp: 1, isRepeat: false
        )))
        XCTAssertFalse(policy.shouldPreserveContext(for: .keyDown(
            .function(f13), activeModifiers: .shift, timestamp: 1, isRepeat: false
        )))
        XCTAssertFalse(policy.shouldPreserveContext(for: .keyDown(
            .function(f13), activeModifiers: .control, timestamp: 1, isRepeat: true
        )))
        XCTAssertFalse(policy.shouldPreserveContext(for: .keyDown(
            .function(f14), activeModifiers: .control, timestamp: 1, isRepeat: false
        )))
    }

    func testHoldFunctionKeyPreservesContextOnlyWithExactHeldModifiers() {
        let f13 = ShortcutFunctionKey(rawValue: 13)!
        let policy = TextShortcutInputContextPolicy(shortcuts: [
            .convertToNextLayout: .holdAndTapTwice(
                heldModifiers: [.control, .shift],
                tapKey: .function(f13)
            )
        ])

        XCTAssertTrue(policy.shouldPreserveContext(for: .keyDown(
            .function(f13),
            activeModifiers: [.control, .shift],
            timestamp: 1,
            isRepeat: false
        )))
        XCTAssertFalse(policy.shouldPreserveContext(for: .keyDown(
            .function(f13), activeModifiers: .control, timestamp: 1, isRepeat: false
        )))
    }
}
