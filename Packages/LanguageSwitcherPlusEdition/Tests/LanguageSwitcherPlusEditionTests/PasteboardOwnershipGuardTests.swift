// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

@testable import LanguageSwitcherPlusEdition
import XCTest

final class PasteboardOwnershipGuardTests: XCTestCase {
    func testOwnsOnlyClaimedChangeCount() {
        var guardState = PasteboardOwnershipGuard()

        guardState.claim(changeCount: 10)

        XCTAssertTrue(guardState.owns(changeCount: 10))
        XCTAssertFalse(guardState.owns(changeCount: 11))
    }

    func testResetRemovesOwnership() {
        var guardState = PasteboardOwnershipGuard()
        guardState.claim(changeCount: 4)

        guardState.reset()

        XCTAssertFalse(guardState.owns(changeCount: 4))
    }
}
