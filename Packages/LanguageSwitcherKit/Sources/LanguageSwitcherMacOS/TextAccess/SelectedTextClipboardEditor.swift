// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation
import LanguageSwitcherApplication

public final class SelectedTextClipboardEditor: SelectedTextReplacing {
    private final class Operation {
        let id = UUID().uuidString.prefix(8)
        let startedAt: TimeInterval
        let originalSnapshot: PasteboardSnapshot
        let applicationID: String
        let inputContextGeneration: UInt64
        let transform: (String) -> TextTransformation?
        let completion: (TextReplacementResult) -> Void
        var ownership = PasteboardOwnershipGuard()
        var restoreResult = "notAttempted"

        init(
            startedAt: TimeInterval,
            originalSnapshot: PasteboardSnapshot,
            applicationID: String,
            inputContextGeneration: UInt64,
            transform: @escaping (String) -> TextTransformation?,
            completion: @escaping (TextReplacementResult) -> Void
        ) {
            self.startedAt = startedAt
            self.originalSnapshot = originalSnapshot
            self.applicationID = applicationID
            self.inputContextGeneration = inputContextGeneration
            self.transform = transform
            self.completion = completion
        }
    }

    private let permission: any AccessibilityPermissionChecking
    private let pasteboard: any PasteboardClient
    private let commandSender: any KeyboardCommandSending
    private let trackedTextBuffer: TrackedTextBuffer
    private let contextTracker: InputContextTracker
    private let applicationProvider: any FrontmostApplicationProviding
    private let scheduler: any ClipboardOperationScheduling
    private let interactionMonitor: any ClipboardOperationInteractionMonitoring
    private let eventReplacer: any SelectedTextEventReplacing
    private let diagnostics: ((String) -> Void)?
    private let copyRetryInterval: TimeInterval
    private let maximumCopyAttempts: Int
    private let copySettleDelay: TimeInterval
    private var activeOperation: Operation?

    public var isBusy: Bool {
        activeOperation != nil || eventReplacer.isBusy
    }

    public convenience init(
        permissionController: AccessibilityPermissionController,
        trackedTextBuffer: TrackedTextBuffer,
        contextTracker: InputContextTracker,
        diagnostics: ((String) -> Void)? = nil
    ) {
        self.init(
            permission: permissionController,
            pasteboard: SystemPasteboardClient(),
            commandSender: KeyboardCommandSender(),
            trackedTextBuffer: trackedTextBuffer,
            contextTracker: contextTracker,
            applicationProvider: FrontmostApplicationProvider(),
            scheduler: ClipboardOperationScheduler(),
            interactionMonitor: ClipboardOperationInteractionMonitor(),
            eventReplacer: CGEventTextReplacer(),
            diagnostics: diagnostics
        )
    }

    init(
        permission: any AccessibilityPermissionChecking,
        pasteboard: any PasteboardClient,
        commandSender: any KeyboardCommandSending,
        trackedTextBuffer: TrackedTextBuffer,
        contextTracker: InputContextTracker,
        applicationProvider: any FrontmostApplicationProviding,
        scheduler: any ClipboardOperationScheduling,
        interactionMonitor: any ClipboardOperationInteractionMonitoring,
        eventReplacer: any SelectedTextEventReplacing,
        diagnostics: ((String) -> Void)? = nil,
        copyRetryInterval: TimeInterval = 0.10,
        maximumCopyAttempts: Int = 5,
        copySettleDelay: TimeInterval = 0.02
    ) {
        self.permission = permission
        self.pasteboard = pasteboard
        self.commandSender = commandSender
        self.trackedTextBuffer = trackedTextBuffer
        self.contextTracker = contextTracker
        self.applicationProvider = applicationProvider
        self.scheduler = scheduler
        self.interactionMonitor = interactionMonitor
        self.eventReplacer = eventReplacer
        self.diagnostics = diagnostics
        self.copyRetryInterval = copyRetryInterval
        self.maximumCopyAttempts = maximumCopyAttempts
        self.copySettleDelay = copySettleDelay
    }

    @discardableResult
    public func replaceSelectedText(
        transform: @escaping (String) -> TextTransformation?,
        completion: @escaping (TextReplacementResult) -> Void
    ) -> Bool {
        guard !isBusy else {
            record("request.rejected reason=busy")
            return false
        }
        guard permission.isAllowed,
              let applicationID = applicationProvider.applicationID else {
            record(
                "request.unavailable accessibility=\(permission.isAllowed) "
                    + "frontmostApp=\(applicationProvider.applicationID ?? "none")"
            )
            completion(.unavailable)
            return true
        }

        let operation = Operation(
            startedAt: scheduler.now,
            originalSnapshot: pasteboard.captureSnapshot(),
            applicationID: applicationID,
            inputContextGeneration: contextTracker.generation,
            transform: transform,
            completion: completion
        )
        activeOperation = operation
        let baselineChangeCount = pasteboard.changeCount
        record(
            "begin app=\(applicationID) generation=\(operation.inputContextGeneration) "
                + "clipboard=\(baselineChangeCount) "
                + "snapshot={\(operation.originalSnapshot.debugSummary)}",
            operation: operation
        )
        interactionMonitor.start { [weak contextTracker] in
            contextTracker?.recordInteraction()
        }

        guard commandSender.send(.copy) else {
            record("copy.send.failed", operation: operation)
            finish(operation, result: .failed)
            return true
        }
        record(
            "copy.sent retryIntervalMs=\(milliseconds(copyRetryInterval)) "
                + "maxAttempts=\(maximumCopyAttempts)",
            operation: operation
        )
        scheduler.schedule(after: copyRetryInterval) { [weak self, weak operation] in
            guard let self, let operation else { return }
            self.waitForCopy(
                operation,
                baselineChangeCount: baselineChangeCount,
                attempt: 1
            )
        }
        return true
    }

    private func waitForCopy(
        _ operation: Operation,
        baselineChangeCount: Int,
        attempt: Int
    ) {
        guard activeOperation === operation else { return }
        guard isInputContextCurrent(operation) else {
            recordContextChange(stage: "copy.wait", operation: operation)
            finish(operation, result: .contextChanged)
            return
        }

        let currentChangeCount = pasteboard.changeCount
        if currentChangeCount != baselineChangeCount {
            record(
                "copy.changed baseline=\(baselineChangeCount) current=\(currentChangeCount)",
                operation: operation
            )
            scheduler.schedule(after: copySettleDelay) { [weak self, weak operation] in
                guard let self, let operation else { return }
                self.acceptStableCopy(operation, candidateChangeCount: currentChangeCount)
            }
            return
        }

        guard attempt < maximumCopyAttempts else {
            record(
                "copy.timeout clipboard=\(currentChangeCount) attempts=\(attempt)",
                operation: operation
            )
            finish(operation, result: .noText)
            return
        }
        scheduler.schedule(after: copyRetryInterval) { [weak self, weak operation] in
            guard let self, let operation else { return }
            self.waitForCopy(
                operation,
                baselineChangeCount: baselineChangeCount,
                attempt: attempt + 1
            )
        }
    }

    private func acceptStableCopy(
        _ operation: Operation,
        candidateChangeCount: Int
    ) {
        guard activeOperation === operation else { return }
        guard isInputContextCurrent(operation) else {
            recordContextChange(stage: "copy.settle", operation: operation)
            finish(operation, result: .contextChanged)
            return
        }
        guard pasteboard.changeCount == candidateChangeCount else {
            record(
                "copy.unstable expected=\(candidateChangeCount) "
                    + "current=\(pasteboard.changeCount)",
                operation: operation
            )
            finish(operation, result: .clipboardChanged)
            return
        }

        operation.ownership.claim(changeCount: candidateChangeCount)
        guard let copiedText = pasteboard.readString(), !copiedText.isEmpty else {
            record("copy.read.empty", operation: operation)
            finish(operation, result: .unchanged)
            return
        }
        record(
            "copy.read characters=\(copiedText.count) text=\(String(reflecting: copiedText))",
            operation: operation
        )
        guard restoreClipboardOwnedByOperation(operation) else {
            finish(operation, result: .failed)
            return
        }
        replace(copiedText, operation: operation)
    }

    private func replace(_ copiedText: String, operation: Operation) {
        guard let transformation = operation.transform(copiedText) else {
            record("transform.noChange", operation: operation)
            finish(operation, result: .unchanged)
            return
        }
        let replacement = transformation.text
        record(
            "transform.ready inputCharacters=\(copiedText.count) "
                + "outputCharacters=\(replacement.count) "
                + "input=\(String(reflecting: copiedText)) "
                + "output=\(String(reflecting: replacement))",
            operation: operation
        )
        guard isInputContextCurrent(operation) else {
            recordContextChange(stage: "event.write", operation: operation)
            finish(operation, result: .contextChanged)
            return
        }

        record(
            "event.write.begin characters=\(replacement.count) "
                + contextSummary(for: operation),
            operation: operation
        )
        guard eventReplacer.replaceSelection(
            with: replacement,
            completion: { [weak self, weak operation] succeeded in
                guard let self, let operation,
                      self.activeOperation === operation else { return }
                guard succeeded else {
                    self.record("event.write.failed", operation: operation)
                    self.finish(operation, result: .failed)
                    return
                }
                self.record("event.write.completed", operation: operation)
                self.trackedTextBuffer.invalidate()
                self.finish(operation, result: .replaced(transformation))
            }
        ) else {
            record("event.write.rejected", operation: operation)
            finish(operation, result: .failed)
            return
        }
    }

    private func finish(_ operation: Operation, result: TextReplacementResult) {
        guard activeOperation === operation else { return }
        let clipboardBeforeRestore = pasteboard.changeCount
        let ownsPasteboard = operation.ownership.owns(changeCount: clipboardBeforeRestore)
        record(
            "finish.prepare result=\(String(describing: result)) "
                + "clipboard=\(clipboardBeforeRestore) owns=\(ownsPasteboard) "
                + contextSummary(for: operation),
            operation: operation
        )
        if ownsPasteboard {
            _ = restoreClipboardOwnedByOperation(operation)
        }
        record(
            "finish result=\(String(describing: result)) "
                + "elapsedMs=\(milliseconds(scheduler.now - operation.startedAt)) "
                + "restore=\(operation.restoreResult)",
            operation: operation
        )
        operation.ownership.reset()
        activeOperation = nil
        interactionMonitor.stop()
        operation.completion(result)
    }

    private func restoreClipboardOwnedByOperation(_ operation: Operation) -> Bool {
        let before = pasteboard.changeCount
        guard operation.ownership.owns(changeCount: before) else {
            record(
                "clipboard.restore attempted=false before=\(before)",
                operation: operation
            )
            return false
        }
        let restored = pasteboard.restore(operation.originalSnapshot)
        operation.restoreResult = restored ? "succeeded" : "failed"
        operation.ownership.reset()
        record(
            "clipboard.restore attempted=true result=\(operation.restoreResult) "
                + "before=\(before) after=\(pasteboard.changeCount)",
            operation: operation
        )
        return restored
    }

    private func isInputContextCurrent(_ operation: Operation) -> Bool {
        applicationProvider.applicationID == operation.applicationID
            && contextTracker.isCurrent(operation.inputContextGeneration)
    }

    private func recordContextChange(stage: String, operation: Operation) {
        record(
            "context.changed stage=\(stage) expectedApp=\(operation.applicationID) "
                + "currentApp=\(applicationProvider.applicationID ?? "none") "
                + "expectedGeneration=\(operation.inputContextGeneration) "
                + "currentGeneration=\(contextTracker.generation)",
            operation: operation
        )
    }

    private func contextSummary(for operation: Operation) -> String {
        "currentApp=\(applicationProvider.applicationID ?? "none") "
            + "currentGeneration=\(contextTracker.generation) "
            + "contextCurrent=\(isInputContextCurrent(operation))"
    }

    private func record(
        _ message: @autoclosure () -> String,
        operation: Operation? = nil
    ) {
        guard let diagnostics else { return }
        let message = message()
        if let operation {
            diagnostics("[\(operation.id)] +\(milliseconds(scheduler.now - operation.startedAt))ms \(message)")
        } else {
            diagnostics(message)
        }
    }

    private func milliseconds(_ interval: TimeInterval) -> Int {
        Int((interval * 1_000).rounded())
    }
}
