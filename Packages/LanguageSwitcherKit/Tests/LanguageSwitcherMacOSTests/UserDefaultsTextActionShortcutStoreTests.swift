// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation
import LanguageSwitcherDomain
import LanguageSwitcherMacOS
import XCTest

final class UserDefaultsTextActionShortcutStoreTests: XCTestCase {
    func testPersistsAlphanumericChordAndHoldGesture() {
        let defaults = makeDefaults()
        let store = UserDefaultsTextActionShortcutStore(userDefaults: defaults)
        let key = TextShortcutKey.alphanumeric(ShortcutAlphanumericKey(rawValue: "3")!)
        let shortcuts: [TextAction: TextActionShortcut] = [
            .convertToNextLayout: .once(TextShortcutChord(modifiers: [.option, .shift], key: key)),
            .changeCase(.uppercase): .holdAndTapTwice(heldModifiers: .control, tapKey: key)
        ]
        for (action, shortcut) in shortcuts {
            store.setShortcut(shortcut, for: action)
        }
        let reopened = UserDefaultsTextActionShortcutStore(userDefaults: defaults)
        for (action, shortcut) in shortcuts {
            XCTAssertEqual(reopened.shortcut(for: action), shortcut)
        }
    }

    func testPersistsClassicFunctionShortcut() {
        let defaults = makeDefaults()
        let store = UserDefaultsTextActionShortcutStore(userDefaults: defaults)
        let shortcut = TextActionShortcut.repeatTwice(TextShortcutChord(
            modifiers: [.command, .control],
            functionKey: ShortcutFunctionKey(rawValue: 20)
        ))

        store.setShortcut(shortcut, for: .changeCase(.invertCase))

        XCTAssertEqual(
            UserDefaultsTextActionShortcutStore(userDefaults: defaults)
                .shortcut(for: .changeCase(.invertCase)),
            shortcut
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "UserDefaultsTextActionShortcutStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
