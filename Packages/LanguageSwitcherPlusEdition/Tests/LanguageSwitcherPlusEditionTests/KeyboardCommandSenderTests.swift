// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

@testable import LanguageSwitcherPlusEdition
import CoreGraphics
import XCTest

final class KeyboardCommandSenderTests: XCTestCase {
    func testKeyboardCommandUsesCombinedSessionSourceAndSessionTap() {
        var sourceStates: [CGEventSourceStateID] = []
        var locations: [CGEventTapLocation] = []
        var flags: [CGEventFlags] = []
        let sender = KeyboardCommandSender(
            makeSource: { state in
                sourceStates.append(state)
                return CGEventSource(stateID: state)
            },
            post: { location, event in
                locations.append(location)
                flags.append(event.flags)
            }
        )

        XCTAssertTrue(sender.send(.copy))
        XCTAssertEqual(sourceStates, [.combinedSessionState])
        XCTAssertEqual(locations, [.cgSessionEventTap, .cgSessionEventTap])
        XCTAssertEqual(flags, [.maskCommand, .maskCommand])
    }
}
