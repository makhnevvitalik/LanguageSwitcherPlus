// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import LanguageSwitcherApplication
import LanguageSwitcherDomain
import XCTest

final class ConfigureTextActionShortcutTests: XCTestCase {
    func testValidationReportsExactConflictWithoutChangingStoredShortcut() {
        let store = TextActionShortcutStoreMock()
        let existing = TextActionShortcut.repeatTwice(TextShortcutChord(
            modifiers: [.command, .option],
            functionKey: nil
        ))
        let original = TextActionShortcut.once(TextShortcutChord(
            modifiers: .shift,
            functionKey: nil
        ))
        store.setShortcut(existing, for: .changeCase(.uppercase))
        store.setShortcut(original, for: .changeCase(.lowercase))
        let useCase = ConfigureTextActionShortcut(store: store)

        XCTAssertEqual(
            useCase.validateShortcut(existing, for: .changeCase(.lowercase)),
            .conflict(.changeCase(.uppercase))
        )
        XCTAssertEqual(store.shortcut(for: .changeCase(.lowercase)), original)
    }

    func testValidationAllowsReversedHoldAndTapRolesOnSamePhysicalKeys() {
        let store = TextActionShortcutStoreMock()
        store.setShortcut(
            .holdAndTapTwice(heldModifiers: .shift, tapKey: .modifier(.option)),
            for: .convertToNextLayout
        )
        let useCase = ConfigureTextActionShortcut(store: store)

        XCTAssertEqual(
            useCase.validateShortcut(
                .holdAndTapTwice(heldModifiers: .option, tapKey: .modifier(.shift)),
                for: .changeCase(.uppercase)
            ),
            .valid
        )
    }

    func testValidationReportsReservedShortcutConflict() {
        let store = TextActionShortcutStoreMock()
        let useCase = ConfigureTextActionShortcut(store: store)
        let commandChord = TextShortcutChord(modifiers: .command, functionKey: nil)

        XCTAssertEqual(
            useCase.validateShortcut(
                .repeatTwice(commandChord),
                for: .changeCase(.uppercase),
                reservedShortcuts: [.once(commandChord)]
            ),
            .conflictWithReservedShortcut
        )
    }

    func testSavesUniqueShortcutAndClearsIt() {
        let store = TextActionShortcutStoreMock()
        let useCase = ConfigureTextActionShortcut(store: store)
        let shortcut = TextActionShortcut.once(TextShortcutChord(
            modifiers: [.command, .option],
            functionKey: nil
        ))

        XCTAssertEqual(
            useCase.setShortcut(shortcut, for: .convertToNextLayout),
            .updated
        )
        XCTAssertEqual(store.shortcut(for: .convertToNextLayout), shortcut)
        XCTAssertEqual(useCase.setShortcut(nil, for: .convertToNextLayout), .updated)
        XCTAssertNil(store.shortcut(for: .convertToNextLayout))
    }

    func testRejectsExactGestureUsedByAnotherAction() {
        let store = TextActionShortcutStoreMock()
        let shortcut = TextActionShortcut.repeatTwice(TextShortcutChord(
            modifiers: [.command, .option],
            functionKey: nil
        ))
        store.setShortcut(shortcut, for: .changeCase(.uppercase))
        let useCase = ConfigureTextActionShortcut(store: store)

        XCTAssertEqual(
            useCase.setShortcut(shortcut, for: .changeCase(.lowercase)),
            .conflict(.changeCase(.uppercase))
        )
    }

    func testSystemConflictBlocksSavingEvenWhenPreviouslyReviewed() {
        let store = TextActionShortcutStoreMock()
        let action = TextAction.convertToNextLayout
        let original = TextActionShortcut.once(TextShortcutChord(modifiers: .shift, functionKey: nil))
        let proposed = TextActionShortcut.once(TextShortcutChord(
            modifiers: .control, key: .alphanumeric(.init(rawValue: "C")!)
        ))
        store.setShortcut(original, for: action)
        let useCase = ConfigureTextActionShortcut(store: store, checkConflict: { _ in .system })

        XCTAssertEqual(useCase.validateShortcut(proposed, for: action), .externalConflict(.system))
        XCTAssertEqual(useCase.setShortcut(proposed, for: action), .requiresConflictReview(.system))
        XCTAssertEqual(useCase.setShortcut(proposed, for: action, reviewedConflict: .system), .requiresConflictReview(.system))
        XCTAssertEqual(store.shortcut(for: action), original)
        XCTAssertEqual(useCase.setShortcut(nil, for: action), .updated)
        XCTAssertNil(store.shortcut(for: action))
    }

    func testSavingRequiresReviewOfTheCurrentWarning() {
        let store = TextActionShortcutStoreMock()
        let action = TextAction.convertToNextLayout
        let proposed = TextActionShortcut.once(TextShortcutChord(
            modifiers: .option, key: .alphanumeric(.init(rawValue: "E")!)
        ))
        let originalWarning = TextShortcutConflict.typing(layout: "ABC", effect: .startsComposition)
        let currentWarning = TextShortcutConflict.typing(layout: "Other Layout", effect: .insertsText("é"))
        var conflict: TextShortcutConflict? = originalWarning
        let useCase = ConfigureTextActionShortcut(store: store, checkConflict: { _ in conflict })

        XCTAssertEqual(useCase.setShortcut(proposed, for: action), .requiresConflictReview(originalWarning))
        conflict = nil
        XCTAssertEqual(useCase.setShortcut(proposed, for: action, reviewedConflict: originalWarning), .requiresConflictReview(nil))
        conflict = currentWarning
        XCTAssertEqual(useCase.setShortcut(proposed, for: action, reviewedConflict: originalWarning),
                       .requiresConflictReview(currentWarning))
        XCTAssertNil(store.shortcut(for: action))
        XCTAssertEqual(useCase.setShortcut(proposed, for: action, reviewedConflict: currentWarning), .updated)
        XCTAssertEqual(store.shortcut(for: action), proposed)
    }

    func testAllowsOnceAndRepeatOnSameChord() {
        let store = TextActionShortcutStoreMock()
        let chord = TextShortcutChord(modifiers: [.control, .shift], functionKey: nil)
        store.setShortcut(.once(chord), for: .convertToNextLayout)
        let useCase = ConfigureTextActionShortcut(store: store)

        XCTAssertEqual(
            useCase.setShortcut(.repeatTwice(chord), for: .changeCase(.uppercase)),
            .updated
        )
    }

    func testAllowsBothHoldDirectionsOnSamePhysicalKeys() {
        let store = TextActionShortcutStoreMock()
        store.setShortcut(
            .holdAndTapTwice(heldModifiers: .shift, tapKey: .modifier(.option)),
            for: .convertToNextLayout
        )
        let useCase = ConfigureTextActionShortcut(store: store)

        XCTAssertEqual(
            useCase.setShortcut(
                .holdAndTapTwice(
                    heldModifiers: .option,
                    tapKey: .modifier(.shift)
                ),
                for: .changeCase(.uppercase)
            ),
            .updated
        )
    }

    func testRejectsInvalidHoldGesture() {
        let store = TextActionShortcutStoreMock()
        let useCase = ConfigureTextActionShortcut(store: store)

        XCTAssertEqual(
            useCase.setShortcut(
                .holdAndTapTwice(
                    heldModifiers: [],
                    tapKey: .modifier(.option)
                ),
                for: .convertToNextLayout
            ),
            .invalid
        )
    }

    func testClassicCommandAloneConflictsWithReservedSwitching() {
        let store = TextActionShortcutStoreMock()
        let useCase = ConfigureTextActionShortcut(store: store)
        let commandChord = TextShortcutChord(modifiers: .command, functionKey: nil)

        XCTAssertEqual(
            useCase.setShortcut(
                .repeatTwice(commandChord),
                for: .changeCase(.uppercase),
                reservedShortcuts: [.once(commandChord)]
            ),
            .conflictWithReservedShortcut
        )
    }

    func testHoldGestureUsingCommandWithAnotherModifierIsNotReserved() {
        let store = TextActionShortcutStoreMock()
        let useCase = ConfigureTextActionShortcut(store: store)
        let commandChord = TextShortcutChord(modifiers: .command, functionKey: nil)

        XCTAssertEqual(
            useCase.setShortcut(
                .holdAndTapTwice(
                    heldModifiers: .shift,
                    tapKey: .modifier(.command)
                ),
                for: .changeCase(.uppercase),
                reservedShortcuts: [.once(commandChord)]
            ),
            .updated
        )
    }

    func testAllTextActionsContainsFiveDistinctActions() {
        XCTAssertEqual(Set(TextAction.allCases).count, 5)
    }
}

private final class TextActionShortcutStoreMock: TextActionShortcutStore {
    private var shortcuts: [TextAction: TextActionShortcut] = [:]

    func shortcut(for action: TextAction) -> TextActionShortcut? {
        shortcuts[action]
    }

    func setShortcut(_ shortcut: TextActionShortcut?, for action: TextAction) {
        shortcuts[action] = shortcut
    }
}
