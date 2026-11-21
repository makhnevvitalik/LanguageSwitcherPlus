// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

@testable import LanguageSwitcherMacOS
import CoreGraphics
import XCTest

final class KeyboardEventPostingTests: XCTestCase {
    func testTrackedTextReplacementUsesCombinedSessionSourceAndSessionTap() {
        var sourceStates: [CGEventSourceStateID] = []
        var locations: [CGEventTapLocation] = []
        let replacer = CGEventTextReplacer(
            makeSource: { state in
                sourceStates.append(state)
                return CGEventSource(stateID: state)
            },
            post: { location, _ in locations.append(location) },
            schedule: { $0() }
        )

        XCTAssertTrue(replacer.replaceSuffix(
            deleting: 1,
            with: [TrackedKeyInput(character: "a", keyCode: 0, eventFlags: 0)],
            completion: { _ in }
        ))
        XCTAssertEqual(sourceStates, Array(repeating: .combinedSessionState, count: 6))
        XCTAssertEqual(locations, Array(repeating: .cgSessionEventTap, count: 12))
    }
}
