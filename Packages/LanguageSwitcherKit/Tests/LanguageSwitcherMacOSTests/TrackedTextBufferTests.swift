// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

@testable import LanguageSwitcherMacOS
import XCTest

final class TrackedTextBufferTests: XCTestCase {
    func testTracksAnEmojiSplitAcrossEventsAsOneCharacter() {
        let buffer = TrackedTextBuffer()
        for input in ["x", "👩", "\u{200D}", "💻"] {
            buffer.recordPrintableText(input, applicationID: "editor")
        }

        XCTAssertEqual(buffer.snapshot(for: "editor")?.inputs.map(\.text), ["x", "👩‍💻"])
    }

    func testRegionalIndicatorsRepartitionAcrossEventBoundary() throws {
        let buffer = TrackedTextBuffer()
        buffer.recordPrintableText("🇦", applicationID: "editor")
        buffer.recordPrintableText("🇧🇨", applicationID: "editor")

        let snapshot = try XCTUnwrap(buffer.snapshot(for: "editor"))
        XCTAssertEqual(snapshot.inputs.map(\.text), ["🇦🇧", "🇨"])
    }

    func testStoresExactTextForCurrentApplication() {
        let buffer = TrackedTextBuffer()

        buffer.recordPrintableText(
            "hello",
            keyCode: 4,
            eventFlags: 0x20000,
            applicationID: "editor"
        )

        XCTAssertEqual(buffer.snapshot(for: "editor")?.text, "hello")
        XCTAssertEqual(
            buffer.snapshot(for: "editor")?.inputs,
            Array("hello").map {
                TrackedKeyInput(character: $0, keyCode: 4, eventFlags: 0x20000)
            }
        )
        XCTAssertNil(buffer.snapshot(for: "other"))
    }

    func testApplicationChangeStartsIndependentBuffer() {
        let buffer = TrackedTextBuffer()
        buffer.recordPrintableText("first", applicationID: "first-editor")

        buffer.recordPrintableText("second", applicationID: "second-editor")

        XCTAssertNil(buffer.snapshot(for: "first-editor"))
        XCTAssertEqual(buffer.snapshot(for: "second-editor")?.text, "second")
    }

    func testInputAfterReplacementStartsNewPhysicalSequence() throws {
        let buffer = TrackedTextBuffer()
        buffer.recordPrintableText("abc", keyCode: 0, applicationID: "editor")
        let snapshot = try XCTUnwrap(buffer.snapshot(for: "editor"))
        let replacement = Array("xyz").map {
            TrackedKeyInput(character: $0, keyCode: 7, eventFlags: 0)
        }
        XCTAssertTrue(buffer.commitReplacement(replacement, expected: snapshot))

        buffer.recordPrintableText("s", keyCode: 1, applicationID: "editor")

        XCTAssertEqual(buffer.snapshot(for: "editor")?.text, "s")
        XCTAssertEqual(buffer.snapshot(for: "editor")?.inputs.map(\.keyCode), [1])
    }

    func testCommitRequiresExactSnapshot() throws {
        let buffer = TrackedTextBuffer()
        buffer.recordPrintableText("abc", applicationID: "editor")
        let stale = try XCTUnwrap(buffer.snapshot(for: "editor"))
        buffer.recordPrintableText("d", applicationID: "editor")

        XCTAssertFalse(buffer.commitReplacement(
            Array("xyz").map { TrackedKeyInput(character: $0, keyCode: 0, eventFlags: 0) },
            expected: stale
        ))
        XCTAssertEqual(buffer.snapshot(for: "editor")?.text, "abcd")
    }

    func testInvalidateDiscardsSnapshot() {
        let buffer = TrackedTextBuffer()
        buffer.recordPrintableText("text", applicationID: "editor")

        buffer.invalidate()

        XCTAssertNil(buffer.snapshot(for: "editor"))
        buffer.recordPrintableText("new", applicationID: "editor")
        XCTAssertEqual(buffer.snapshot(for: "editor")?.text, "new")
    }

    func testRepeatedReplacementAndBackspaceUseConvertedText() throws {
        let buffer = TrackedTextBuffer()
        buffer.recordPrintableText("ghbdtn", applicationID: "editor")
        for text in ["привет", "HELLO"] {
            let snapshot = try XCTUnwrap(buffer.snapshot(for: "editor"))
            let replacement = text.map { TrackedKeyInput(character: $0, keyCode: 0, eventFlags: 0) }
            XCTAssertTrue(buffer.commitReplacement(replacement, expected: snapshot))
            XCTAssertEqual(buffer.snapshot(for: "editor")?.text, text)
        }

        buffer.recordBackspace(applicationID: "editor")
        XCTAssertEqual(buffer.snapshot(for: "editor")?.text, "HELL")
        buffer.recordPrintableText("s", applicationID: "editor")
        XCTAssertEqual(buffer.snapshot(for: "editor")?.text, "HELLs")
    }

    func testBackspacePastKnownBoundaryDiscardsEarlierSnapshot() throws {
        let buffer = TrackedTextBuffer()
        buffer.recordPrintableText("a", applicationID: "editor")
        let snapshot = try XCTUnwrap(buffer.snapshot(for: "editor"))
        buffer.recordBackspace(applicationID: "editor")
        buffer.recordBackspace(applicationID: "editor")
        buffer.recordPrintableText("a", applicationID: "editor")

        XCTAssertFalse(buffer.isCurrent(snapshot))
        XCTAssertEqual(buffer.snapshot(for: "editor")?.text, "a")
    }
}
