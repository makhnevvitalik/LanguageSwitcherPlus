// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import LanguageSwitcherApplication
@testable import LanguageSwitcherMacOS
import XCTest

final class SelectedTextClipboardEditorTests: XCTestCase {
    func testReplacesCopiedTextAndRestoresPasteboard() {
        let environment = Environment(copyBehavior: .copied("hello"))
        var result: TextReplacementResult?

        XCTAssertTrue(environment.editor.replaceSelectedText(
            transform: { TextTransformation(text: $0.uppercased()) },
            completion: { result = $0 }
        ))
        environment.scheduler.runUntilIdle()

        XCTAssertEqual(environment.eventReplacer.selectionTexts, ["HELLO"])
        XCTAssertEqual(environment.sender.commands, [.copy])
        XCTAssertTrue(environment.pasteboard.didRestore)
        XCTAssertEqual(result, .replaced(TextTransformation(text: "HELLO")))
    }

    func testCopyingSameTextIsAcceptedWhenChangeCountAdvances() {
        let environment = Environment(copyBehavior: .copied("original"))
        var result: TextReplacementResult?

        environment.editor.replaceSelectedText(
            transform: { TextTransformation(text: $0.uppercased()) },
            completion: { result = $0 }
        )
        environment.scheduler.runUntilIdle()

        XCTAssertEqual(environment.eventReplacer.selectionTexts, ["ORIGINAL"])
        XCTAssertEqual(result, .replaced(TextTransformation(text: "ORIGINAL")))
    }

    func testUnchangedClipboardReturnsNoTextWithoutInvalidatingTrackedBuffer() {
        let environment = Environment(copyBehavior: .unchanged)
        var result: TextReplacementResult?

        environment.editor.replaceSelectedText(
            transform: { TextTransformation(text: $0.uppercased()) },
            completion: { result = $0 }
        )
        environment.scheduler.runUntilIdle()

        XCTAssertEqual(environment.sender.commands, [.copy])
        XCTAssertEqual(result, .noText)
        XCTAssertEqual(environment.buffer.snapshot(for: "editor")?.text, "tracked")
    }

    func testDefaultCopyRetriesAcceptTextAvailableDuringFifthHundredMillisecondWindow() {
        let environment = Environment(
            copyBehavior: .unchanged,
            useProductionDelays: true
        )
        environment.sender.afterSend = { command in
            guard command == .copy else { return }
            environment.scheduler.schedule(after: 0.45) {
                environment.pasteboard.externalChange(string: "hello")
            }
        }
        var result: TextReplacementResult?

        environment.editor.replaceSelectedText(
            transform: { TextTransformation(text: $0.uppercased()) },
            completion: { result = $0 }
        )
        environment.scheduler.runUntilIdle()

        XCTAssertEqual(environment.eventReplacer.selectionTexts, ["HELLO"])
        XCTAssertEqual(result, .replaced(TextTransformation(text: "HELLO")))
    }

    func testChangedClipboardWithoutStringReturnsUnchangedAndRestoresSnapshot() {
        let environment = Environment(copyBehavior: .missingString)
        var result: TextReplacementResult?

        environment.editor.replaceSelectedText(
            transform: { TextTransformation(text: $0.uppercased()) },
            completion: { result = $0 }
        )
        environment.scheduler.runUntilIdle()

        XCTAssertEqual(result, .unchanged)
        XCTAssertTrue(environment.pasteboard.didRestore)
    }

    func testCopiedTextThatTransformationCannotChangeDoesNotLookLikeMissingCopy() {
        let environment = Environment(copyBehavior: .copied("already correct"))
        var result: TextReplacementResult?

        environment.editor.replaceSelectedText(
            transform: { _ in nil },
            completion: { result = $0 }
        )
        environment.scheduler.runUntilIdle()

        XCTAssertEqual(result, .unchanged)
        XCTAssertTrue(environment.pasteboard.didRestore)
        XCTAssertTrue(environment.eventReplacer.selectionTexts.isEmpty)
    }

    func testAcceptsTwoClipboardWritesFromOneCopyCommand() {
        let environment = Environment(copyBehavior: .copied("selected"))
        environment.sender.afterSend = { command in
            guard command == .copy else { return }
            environment.pasteboard.performCopy()
            environment.pasteboard.performCopy()
        }
        var result: TextReplacementResult?

        environment.editor.replaceSelectedText(
            transform: { TextTransformation(text: $0.uppercased()) },
            completion: { result = $0 }
        )
        environment.scheduler.runUntilIdle()

        XCTAssertEqual(result, .replaced(TextTransformation(text: "SELECTED")))
        XCTAssertEqual(environment.pasteboard.string, "original")
        XCTAssertTrue(environment.pasteboard.didRestore)
        XCTAssertEqual(environment.eventReplacer.selectionTexts, ["SELECTED"])
    }

    func testContextChangeBeforeReplacementAbortsOperation() {
        let environment = Environment(copyBehavior: .copied("hello"))
        var result: TextReplacementResult?

        environment.editor.replaceSelectedText(transform: { text in
            environment.contextTracker.recordInteraction()
            return TextTransformation(text: text.uppercased())
        }, completion: { result = $0 })
        environment.scheduler.runUntilIdle()

        XCTAssertEqual(result, .contextChanged)
        XCTAssertTrue(environment.eventReplacer.selectionTexts.isEmpty)
    }

    func testExternalClipboardChangeDuringTransformIsPreserved() {
        let environment = Environment(copyBehavior: .copied("hello"))
        var result: TextReplacementResult?

        environment.editor.replaceSelectedText(transform: { text in
            environment.pasteboard.externalChange(string: "external")
            return TextTransformation(text: text.uppercased())
        }, completion: { result = $0 })
        environment.scheduler.runUntilIdle()

        XCTAssertEqual(result, .replaced(TextTransformation(text: "HELLO")))
        XCTAssertEqual(environment.pasteboard.string, "external")
        XCTAssertTrue(environment.pasteboard.didRestore)
        XCTAssertEqual(environment.eventReplacer.selectionTexts, ["HELLO"])
    }

    func testSuccessfulReplacementInvalidatesTrackedBuffer() {
        let environment = Environment(copyBehavior: .copied("hello"))

        environment.editor.replaceSelectedText(
            transform: { TextTransformation(text: $0.uppercased()) },
            completion: { _ in }
        )
        environment.scheduler.runUntilIdle()

        XCTAssertNil(environment.buffer.snapshot(for: "editor"))
    }

    func testRestoresClipboardBeforePostingUnicodeReplacement() {
        let environment = Environment(copyBehavior: .copied("hello"))
        var clipboardWasRestoredBeforeInput = false
        environment.eventReplacer.onReplaceSelection = { _ in
            clipboardWasRestoredBeforeInput = environment.pasteboard.didRestore
        }

        environment.editor.replaceSelectedText(
            transform: { TextTransformation(text: $0.uppercased()) },
            completion: { _ in }
        )
        environment.scheduler.runUntilIdle()

        XCTAssertTrue(clipboardWasRestoredBeforeInput)
    }

    func testContextChangeWhileRestoringClipboardPreventsUnicodeReplacement() {
        let environment = Environment(copyBehavior: .copied("hello"))
        environment.pasteboard.onRestore = {
            environment.contextTracker.recordInteraction()
        }
        var result: TextReplacementResult?

        environment.editor.replaceSelectedText(
            transform: { TextTransformation(text: $0.uppercased()) },
            completion: { result = $0 }
        )
        environment.scheduler.runUntilIdle()

        XCTAssertEqual(result, .contextChanged)
        XCTAssertTrue(environment.eventReplacer.selectionTexts.isEmpty)
    }

    func testEventReplacementFailureIsReportedAfterRestoringSnapshot() {
        let environment = Environment(copyBehavior: .copied("hello"))
        environment.eventReplacer.result = false
        var result: TextReplacementResult?

        environment.editor.replaceSelectedText(
            transform: { TextTransformation(text: $0.uppercased()) },
            completion: { result = $0 }
        )
        environment.scheduler.runUntilIdle()

        XCTAssertEqual(result, .failed)
        XCTAssertTrue(environment.pasteboard.didRestore)
        XCTAssertFalse(environment.editor.isBusy)
    }

    func testRejectsSecondOperationWhileFirstIsRunning() {
        let environment = Environment(copyBehavior: .unchanged)

        XCTAssertTrue(environment.editor.replaceSelectedText(
            transform: { TextTransformation(text: $0) },
            completion: { _ in }
        ))
        XCTAssertFalse(environment.editor.replaceSelectedText(
            transform: { TextTransformation(text: $0) },
            completion: { _ in }
        ))
    }
}

private final class Environment {
    let pasteboard: FakePasteboard
    let sender: FakeKeyboardCommandSender
    let eventReplacer = FakeTextEventReplacer()
    let scheduler = FakeClipboardScheduler()
    let interactionMonitor = FakeClipboardOperationInteractionMonitor()
    let buffer = TrackedTextBuffer()
    let contextTracker = InputContextTracker()
    let editor: SelectedTextClipboardEditor

    init(
        copyBehavior: FakePasteboard.CopyBehavior,
        useProductionDelays: Bool = false
    ) {
        let pasteboard = FakePasteboard(copyBehavior: copyBehavior)
        let sender = FakeKeyboardCommandSender()
        sender.afterSend = { command in
            if command == .copy {
                pasteboard.performCopy()
            }
        }
        buffer.recordPrintableText("tracked", applicationID: "editor")
        self.pasteboard = pasteboard
        self.sender = sender
        if useProductionDelays {
            editor = SelectedTextClipboardEditor(
                permission: FakeAccessibilityPermission(isAllowed: true),
                pasteboard: pasteboard,
                commandSender: sender,
                trackedTextBuffer: buffer,
                contextTracker: contextTracker,
                applicationProvider: FakeFrontmostApplicationProvider(applicationID: "editor"),
                scheduler: scheduler,
                interactionMonitor: interactionMonitor,
                eventReplacer: eventReplacer
            )
        } else {
            editor = SelectedTextClipboardEditor(
                permission: FakeAccessibilityPermission(isAllowed: true),
                pasteboard: pasteboard,
                commandSender: sender,
                trackedTextBuffer: buffer,
                contextTracker: contextTracker,
                applicationProvider: FakeFrontmostApplicationProvider(applicationID: "editor"),
                scheduler: scheduler,
                interactionMonitor: interactionMonitor,
                eventReplacer: eventReplacer,
                copyRetryInterval: 0.01,
                maximumCopyAttempts: 2,
                copySettleDelay: 0.005
            )
        }
    }
}

private final class FakeClipboardOperationInteractionMonitor: ClipboardOperationInteractionMonitoring {
    private var onInteraction: (() -> Void)?

    func start(onInteraction: @escaping () -> Void) {
        self.onInteraction = onInteraction
    }

    func stop() {
        onInteraction = nil
    }
}

private final class FakeAccessibilityPermission: AccessibilityPermissionChecking {
    let isAllowed: Bool
    init(isAllowed: Bool) { self.isAllowed = isAllowed }
}

private final class FakeFrontmostApplicationProvider: FrontmostApplicationProviding {
    var applicationID: String?
    init(applicationID: String?) { self.applicationID = applicationID }
}

private final class FakePasteboard: PasteboardClient {
    enum CopyBehavior {
        case unchanged
        case copied(String)
        case missingString
    }

    var changeCount = 1
    var string: String? = "original"
    var didRestore = false
    var onRestore: (() -> Void)?
    private var copyBehavior: CopyBehavior

    init(copyBehavior: CopyBehavior) {
        self.copyBehavior = copyBehavior
    }

    func captureSnapshot() -> PasteboardSnapshot {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        return PasteboardSnapshot.capture(from: pasteboard)
    }
    func readString() -> String? { string }

    func restore(_ snapshot: PasteboardSnapshot) -> Bool {
        changeCount += 1
        string = "original"
        didRestore = true
        onRestore?()
        return true
    }

    func performCopy() {
        switch copyBehavior {
        case .unchanged:
            break
        case let .copied(value):
            changeCount += 1
            string = value
        case .missingString:
            changeCount += 1
            string = nil
        }
    }

    func externalChange(string: String) {
        changeCount += 1
        self.string = string
    }
}

private final class FakeTextEventReplacer: SelectedTextEventReplacing {
    var selectionTexts: [String] = []
    var result = true
    var isBusy = false
    var onReplaceSelection: ((String) -> Void)?

    func replaceSelection(
        with text: String,
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        guard !isBusy else { return false }
        onReplaceSelection?(text)
        selectionTexts.append(text)
        completion(result)
        return true
    }
}

private final class FakeKeyboardCommandSender: KeyboardCommandSending {
    var commands: [KeyboardCommand] = []
    var afterSend: ((KeyboardCommand) -> Void)?

    func send(_ command: KeyboardCommand) -> Bool {
        commands.append(command)
        afterSend?(command)
        return true
    }
}

private final class FakeClipboardScheduler: ClipboardOperationScheduling {
    private struct Scheduled {
        let time: TimeInterval
        let operation: () -> Void
    }

    var now: TimeInterval = 0
    private var scheduled: [Scheduled] = []

    func schedule(after delay: TimeInterval, operation: @escaping () -> Void) {
        scheduled.append(Scheduled(time: now + delay, operation: operation))
    }

    func runUntilIdle() {
        var iterationCount = 0
        while !scheduled.isEmpty {
            iterationCount += 1
            precondition(iterationCount < 100)
            scheduled.sort { $0.time < $1.time }
            let next = scheduled.removeFirst()
            now = next.time
            next.operation()
        }
    }

}
