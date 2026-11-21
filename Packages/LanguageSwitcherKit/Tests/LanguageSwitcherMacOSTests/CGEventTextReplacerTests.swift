// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

@testable import LanguageSwitcherMacOS
import CoreGraphics
import LanguageSwitcherDomain
import XCTest

final class CGEventTextReplacerTests: XCTestCase {
    func testCommitsInputCompositionBeforeReplacingTrackedSuffix() {
        var postedEvents: [CGEvent] = []
        let replacer = immediateReplacer { postedEvents.append($0) }

        XCTAssertTrue(replacer.replaceSuffix(
            deleting: 1,
            with: [TrackedKeyInput(character: "ы", keyCode: 1, eventFlags: 0)],
            completion: { _ in }
        ))

        XCTAssertEqual(
            stride(from: 0, to: postedEvents.count, by: 2).map {
                postedEvents[$0].getIntegerValueField(.keyboardEventKeycode)
            },
            [49, 123, 124, 51, 51, 1]
        )
    }

    func testReplaysTheOriginalPhysicalKeyAfterCommittedCompositionAndDeletion() {
        var postedEvents: [CGEvent] = []
        var immediate: [() -> Void] = []
        var result: Bool?
        let replacer = CGEventTextReplacer(
            post: { _, event in postedEvents.append(event) },
            schedule: { immediate.append($0) }
        )

        XCTAssertTrue(replacer.replaceSuffix(
            deleting: 1,
            with: [
                TrackedKeyInput(character: "ы", keyCode: 1, eventFlags: 0x20000)
            ],
            completion: { result = $0 }
        ))

        runAll(&immediate)
        XCTAssertEqual(postedEvents.count, 12)
        XCTAssertEqual(
            postedEvents.suffix(2).map { $0.getIntegerValueField(.keyboardEventKeycode) },
            [1, 1]
        )
        XCTAssertEqual(postedEvents[10].flags.rawValue, 0x20000)
        XCTAssertEqual(postedEvents[11].flags.rawValue, 0x20000)
        XCTAssertEqual(unicodeString(from: postedEvents[10]), "ы")
        XCTAssertEqual(result, true)
    }

    func testCreatesMarkedBackspacesFollowedByOneUnicodePairPerCharacter() {
        var postedEvents: [CGEvent] = []
        let replacer = immediateReplacer { postedEvents.append($0) }
        var result: Bool?

        XCTAssertTrue(replacer.replaceSuffix(
            deleting: 2,
            with: Array("привет").map {
                TrackedKeyInput(character: $0, keyCode: 0, eventFlags: 0)
            },
            completion: { result = $0 }
        ))

        XCTAssertEqual(result, true)
        XCTAssertEqual(postedEvents.count, 24)
        XCTAssertEqual(
            postedEvents.map { $0.getIntegerValueField(.keyboardEventKeycode) },
            [49, 49, 123, 123, 124, 124]
                + Array(repeating: 51, count: 6)
                + Array(repeating: 0, count: 12)
        )
        XCTAssertTrue(postedEvents.allSatisfy {
            $0.getIntegerValueField(.eventSourceUserData) == KeyboardCommandEventMarker.value
        })
        XCTAssertEqual(
            stride(from: 12, to: postedEvents.count, by: 2).map {
                unicodeString(from: postedEvents[$0])
            },
            Array("привет").map(String.init)
        )
        XCTAssertEqual(
            stride(from: 13, to: postedEvents.count, by: 2).map {
                unicodeString(from: postedEvents[$0])
            },
            Array("привет").map(String.init)
        )
    }

    func testKeepsExtendedGraphemeInOneEventPair() {
        var postedEvents: [CGEvent] = []
        let replacer = immediateReplacer { postedEvents.append($0) }

        XCTAssertTrue(replacer.replaceSuffix(
            deleting: 0,
            with: [TrackedKeyInput(character: "👨‍👩‍👧", keyCode: 0, eventFlags: 0)],
            completion: { _ in }
        ))

        XCTAssertEqual(postedEvents.count, 10)
        XCTAssertEqual(unicodeString(from: postedEvents[8]), "👨‍👩‍👧")
        XCTAssertEqual(unicodeString(from: postedEvents[9]), "👨‍👩‍👧")
    }

    func testReplacesSelectionWithOnlyUnicodeEventPairs() {
        var postedEvents: [CGEvent] = []
        let replacer = immediateReplacer { postedEvents.append($0) }
        var result: Bool?

        XCTAssertTrue(replacer.replaceSelection(
            with: "привет",
            completion: { result = $0 }
        ))

        XCTAssertEqual(result, true)
        XCTAssertEqual(postedEvents.count, 12)
        XCTAssertEqual(
            postedEvents.map { $0.getIntegerValueField(.keyboardEventKeycode) },
            Array(repeating: 0, count: 12)
        )
        XCTAssertEqual(
            stride(from: 0, to: postedEvents.count, by: 2).map {
                unicodeString(from: postedEvents[$0])
            },
            Array("привет").map(String.init)
        )
    }

    func testEmptyReplacementPostsOnlyBackspaces() {
        var postedEvents: [CGEvent] = []
        let replacer = immediateReplacer { postedEvents.append($0) }

        XCTAssertTrue(replacer.replaceSuffix(
            deleting: 1,
            with: [],
            completion: { _ in }
        ))

        XCTAssertEqual(postedEvents.count, 10)
    }

    private func unicodeString(from event: CGEvent) -> String {
        var length = 0
        event.keyboardGetUnicodeString(
            maxStringLength: 0,
            actualStringLength: &length,
            unicodeString: nil
        )
        var buffer = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count,
            actualStringLength: &length,
            unicodeString: &buffer
        )
        return String(utf16CodeUnits: buffer, count: length)
    }

    private func runAll(_ work: inout [() -> Void]) {
        while !work.isEmpty {
            work.removeFirst()()
        }
    }

    private func immediateReplacer(
        post: @escaping (CGEvent) -> Void
    ) -> CGEventTextReplacer {
        CGEventTextReplacer(
            post: { _, event in post(event) },
            schedule: { $0() }
        )
    }
}
