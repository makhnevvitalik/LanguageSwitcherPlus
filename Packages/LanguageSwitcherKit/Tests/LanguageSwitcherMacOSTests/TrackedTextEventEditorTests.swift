// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

@testable import LanguageSwitcherMacOS
import LanguageSwitcherApplication
import LanguageSwitcherDomain
import XCTest

final class TrackedTextEventEditorTests: XCTestCase {
    func testTypedTextReplacesWholeTrackedBuffer() {
        let fixture = Fixture(text: "hello ghbdtn")
        var result: TextReplacementResult?

        XCTAssertTrue(fixture.editor.replaceTrackedText(
            scope: .typedText,
            transform: {
                $0 == "hello ghbdtn" ? TextTransformation(text: "hello привет") : nil
            },
            completion: { result = $0 }
        ))

        XCTAssertEqual(result, .replaced(TextTransformation(text: "hello привет")))
        XCTAssertEqual(fixture.eventReplacer.calls, [.init(deleteCount: 12, text: "hello привет")])
        XCTAssertEqual(fixture.buffer.snapshot(for: "editor")?.text, "hello привет")
    }

    func testLastWordReplacesWordAndPreservesTrailingWhitespace() {
        let fixture = Fixture(text: "hello ghbdtn./  ")
        var result: TextReplacementResult?

        XCTAssertTrue(fixture.editor.replaceTrackedText(
            scope: .lastWord,
            transform: {
                $0 == "ghbdtn./" ? TextTransformation(text: "приветю.") : nil
            },
            completion: { result = $0 }
        ))

        XCTAssertEqual(result, .replaced(TextTransformation(text: "приветю.")))
        XCTAssertEqual(fixture.eventReplacer.calls, [.init(deleteCount: 10, text: "приветю.  ")])
        XCTAssertEqual(fixture.buffer.snapshot(for: "editor")?.text, "hello приветю.  ")
    }

    func testSelectionOnlyDoesNotUseTrackedText() {
        let fixture = Fixture(text: "text")
        var result: TextReplacementResult?

        XCTAssertTrue(fixture.editor.replaceTrackedText(
            scope: .selectionOnly,
            transform: { _ in TextTransformation(text: "other") },
            completion: { result = $0 }
        ))

        XCTAssertEqual(result, .noText)
        XCTAssertTrue(fixture.eventReplacer.calls.isEmpty)
    }

    func testMissingPermissionReturnsUnavailable() {
        let fixture = Fixture(text: "text", isAllowed: false)
        var result: TextReplacementResult?

        XCTAssertTrue(fixture.editor.replaceTrackedText(
            scope: .typedText,
            transform: { _ in TextTransformation(text: "other") },
            completion: { result = $0 }
        ))

        XCTAssertEqual(result, .unavailable)
        XCTAssertTrue(fixture.eventReplacer.calls.isEmpty)
    }

    func testContextChangedByTransformPreventsReplacement() {
        let fixture = Fixture(text: "text")
        var result: TextReplacementResult?

        XCTAssertTrue(fixture.editor.replaceTrackedText(
            scope: .typedText,
            transform: { text in
                fixture.contextTracker.recordInteraction()
                return TextTransformation(text: text.uppercased())
            },
            completion: { result = $0 }
        ))

        XCTAssertEqual(result, .contextChanged)
        XCTAssertTrue(fixture.eventReplacer.calls.isEmpty)
        XCTAssertEqual(fixture.buffer.snapshot(for: "editor")?.text, "text")
    }

    func testApplicationChangedByTransformPreventsReplacement() {
        let fixture = Fixture(text: "text")
        var result: TextReplacementResult?

        XCTAssertTrue(fixture.editor.replaceTrackedText(
            scope: .typedText,
            transform: { text in
                fixture.applicationProvider.applicationID = "other"
                return TextTransformation(text: text.uppercased())
            },
            completion: { result = $0 }
        ))

        XCTAssertEqual(result, .contextChanged)
        XCTAssertTrue(fixture.eventReplacer.calls.isEmpty)
    }

    func testSenderFailureDoesNotCommitBuffer() {
        let fixture = Fixture(text: "text")
        fixture.eventReplacer.result = false
        var result: TextReplacementResult?

        XCTAssertTrue(fixture.editor.replaceTrackedText(
            scope: .typedText,
            transform: { _ in TextTransformation(text: "TEXT") },
            completion: { result = $0 }
        ))

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(fixture.buffer.snapshot(for: "editor")?.text, "text")
    }
}

private final class Fixture {
    let permission: FakeAccessibilityPermission
    let buffer = TrackedTextBuffer()
    let contextTracker = InputContextTracker()
    let applicationProvider = FakeFrontmostApplicationProvider(applicationID: "editor")
    let eventReplacer = FakeTextEventReplacer()
    let editor: TrackedTextEventEditor

    init(text: String, isAllowed: Bool = true) {
        permission = FakeAccessibilityPermission(isAllowed: isAllowed)
        buffer.recordPrintableText(text, applicationID: "editor")
        editor = TrackedTextEventEditor(
            permission: permission,
            buffer: buffer,
            contextTracker: contextTracker,
            applicationProvider: applicationProvider,
            eventReplacer: eventReplacer
        )
    }
}

private final class FakeAccessibilityPermission: AccessibilityPermissionChecking {
    var isAllowed: Bool

    init(isAllowed: Bool) {
        self.isAllowed = isAllowed
    }
}

private final class FakeFrontmostApplicationProvider: FrontmostApplicationProviding {
    var applicationID: String?

    init(applicationID: String?) {
        self.applicationID = applicationID
    }
}

private final class FakeTextEventReplacer: TrackedTextEventReplacing {
    struct Call: Equatable {
        let deleteCount: Int
        let text: String
    }

    var calls: [Call] = []
    var result = true
    var isBusy = false

    func replaceSuffix(
        deleting characterCount: Int,
        with inputs: [TrackedKeyInput],
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        guard !isBusy else { return false }
        calls.append(Call(
            deleteCount: characterCount,
            text: inputs.map(\.text).joined()
        ))
        completion(result)
        return true
    }
}
