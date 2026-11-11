// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import XCTest
@testable import LanguageSwitcherMacOS

final class StandaloneModifierTapTrackerTests: XCTestCase {
    func testShortStandaloneCommandTapTriggersOnRelease() {
        var tracker = StandaloneModifierTapTracker(shortcut: .command, maximumTapDuration: 0.2)

        XCTAssertFalse(tracker.handle(.flagsChanged(keyCode: 55, flags: [.command], timestamp: 1.0)))
        XCTAssertTrue(tracker.handle(.flagsChanged(keyCode: 55, flags: [], timestamp: 1.1)))
    }

    func testStandaloneCommandTapStillTriggersAfterOverlappingCommandPresses() {
        for firstReleasedKeyCode: UInt16 in [55, 54] {
            let lastReleasedKeyCode: UInt16 = firstReleasedKeyCode == 55 ? 54 : 55
            for nextTapKeyCode: UInt16 in [55, 54] {
                var tracker = StandaloneModifierTapTracker(shortcut: .command, maximumTapDuration: 0.2)
                let context = "First release: \(firstReleasedKeyCode), next tap: \(nextTapKeyCode)"

                XCTAssertFalse(tracker.handle(.flagsChanged(keyCode: 55, flags: [.command], timestamp: 1.0)), context)
                XCTAssertFalse(tracker.handle(.flagsChanged(keyCode: 54, flags: [.command], timestamp: 1.02)), context)
                XCTAssertFalse(tracker.handle(.flagsChanged(keyCode: firstReleasedKeyCode, flags: [.command], timestamp: 1.04)), context)
                XCTAssertFalse(tracker.handle(.flagsChanged(keyCode: lastReleasedKeyCode, flags: [], timestamp: 1.06)), context)

                XCTAssertFalse(tracker.handle(.flagsChanged(keyCode: nextTapKeyCode, flags: [.command], timestamp: 2.0)), context)
                XCTAssertTrue(tracker.handle(.flagsChanged(keyCode: nextTapKeyCode, flags: [], timestamp: 2.1)), context)
            }
        }
    }

    func testLongCommandPressDoesNotTrigger() {
        var tracker = StandaloneModifierTapTracker(shortcut: .command, maximumTapDuration: 0.2)

        _ = tracker.handle(.flagsChanged(keyCode: 55, flags: [.command], timestamp: 1.0))

        XCTAssertFalse(tracker.handle(.flagsChanged(keyCode: 55, flags: [], timestamp: 1.2)))
    }

    func testCommandUsedWithKeyDoesNotTrigger() {
        var tracker = StandaloneModifierTapTracker(shortcut: .command, maximumTapDuration: 0.2)

        _ = tracker.handle(.flagsChanged(keyCode: 55, flags: [.command], timestamp: 1.0))
        _ = tracker.handle(.keyDown(flags: [.command]))

        XCTAssertFalse(tracker.handle(.flagsChanged(keyCode: 55, flags: [], timestamp: 1.1)))
    }

    func testCommandUsedWithMouseDoesNotTrigger() {
        var tracker = StandaloneModifierTapTracker(shortcut: .command, maximumTapDuration: 0.2)

        _ = tracker.handle(.flagsChanged(keyCode: 55, flags: [.command], timestamp: 1.0))
        _ = tracker.handle(.mouseDown(flags: [.command]))

        XCTAssertFalse(tracker.handle(.flagsChanged(keyCode: 55, flags: [], timestamp: 1.1)))
    }

    func testCapsLockDoesNotInvalidateFunctionGlobeTap() {
        var tracker = StandaloneModifierTapTracker(shortcut: .functionGlobe, maximumTapDuration: 0.2)

        _ = tracker.handle(.flagsChanged(keyCode: 63, flags: [.function, .capsLock], timestamp: 1.0))

        XCTAssertTrue(tracker.handle(.flagsChanged(keyCode: 63, flags: [.capsLock], timestamp: 1.1)))
    }
}
