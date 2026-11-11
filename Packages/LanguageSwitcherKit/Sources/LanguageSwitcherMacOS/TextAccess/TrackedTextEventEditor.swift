// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation
import LanguageSwitcherApplication
import LanguageSwitcherDomain

public final class TrackedTextEventEditor: TrackedTextReplacing {
    private let permission: any AccessibilityPermissionChecking
    private let buffer: TrackedTextBuffer
    private let contextTracker: InputContextTracker
    private let applicationProvider: any FrontmostApplicationProviding
    private let eventReplacer: any TrackedTextEventReplacing
    private let diagnostics: ((String) -> Void)?

    public convenience init(
        permissionController: AccessibilityPermissionController,
        buffer: TrackedTextBuffer,
        contextTracker: InputContextTracker,
        diagnostics: ((String) -> Void)? = nil
    ) {
        self.init(
            permission: permissionController,
            buffer: buffer,
            contextTracker: contextTracker,
            applicationProvider: FrontmostApplicationProvider(),
            eventReplacer: CGEventTextReplacer(),
            diagnostics: diagnostics
        )
    }

    init(
        permission: any AccessibilityPermissionChecking,
        buffer: TrackedTextBuffer,
        contextTracker: InputContextTracker,
        applicationProvider: any FrontmostApplicationProviding,
        eventReplacer: any TrackedTextEventReplacing,
        diagnostics: ((String) -> Void)? = nil
    ) {
        self.permission = permission
        self.buffer = buffer
        self.contextTracker = contextTracker
        self.applicationProvider = applicationProvider
        self.eventReplacer = eventReplacer
        self.diagnostics = diagnostics
    }

    public var isBusy: Bool { eventReplacer.isBusy }

    @discardableResult
    public func replaceTrackedText(
        scope: TextConversionScope,
        transform: @escaping (String) -> TextTransformation?,
        completion: @escaping (TextReplacementResult) -> Void
    ) -> Bool {
        guard !isBusy else { return false }
        return performReplacement(
            scope: scope,
            transform: transform,
            completion: completion
        )
    }

    private func performReplacement(
        scope: TextConversionScope,
        transform: (String) -> TextTransformation?,
        completion: @escaping (TextReplacementResult) -> Void
    ) -> Bool {
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard permission.isAllowed,
              let applicationID = applicationProvider.applicationID else {
            record("request.unavailable")
            completion(.unavailable)
            return true
        }
        let contextGeneration = contextTracker.generation
        guard let snapshot = buffer.snapshot(for: applicationID) else {
            record("snapshot.missing app=\(applicationID) scope=\(scope)")
            completion(.noText)
            return true
        }
        record(
            "snapshot.ready app=\(applicationID) generation=\(snapshot.generation) "
                + "scope=\(scope) characters=\(snapshot.text.count) "
                + "text=\(String(reflecting: snapshot.text)) "
                + "elapsedMs=\(elapsedMilliseconds(since: startedAt))"
        )
        guard let slice = TrackedTextScopeResolver.resolve(
            text: snapshot.text,
            scope: scope
        ) else {
            record("scope.empty scope=\(scope)")
            completion(.noText)
            return true
        }
        guard let transformation = transform(slice.textToTransform) else {
            record("transform.noChange input=\(String(reflecting: slice.textToTransform))")
            completion(.unchanged)
            return true
        }
        let transformed = transformation.text
        let replacement = transformed + slice.trailingText
        let deletedInputs = Array(snapshot.inputs.suffix(slice.deletedCharacterCount))
        let replacementInputs = makeReplacementInputs(
            text: replacement,
            replacing: deletedInputs
        )
        let completeInputs = Array(snapshot.inputs.dropLast(slice.deletedCharacterCount))
            + replacementInputs
        record(
            "replace.ready deleteCharacters=\(slice.deletedCharacterCount) "
                + "input=\(String(reflecting: slice.textToTransform + slice.trailingText)) "
                + "output=\(String(reflecting: replacement)) "
                + "elapsedMs=\(elapsedMilliseconds(since: startedAt))"
        )

        guard applicationProvider.applicationID == applicationID,
              contextTracker.isCurrent(contextGeneration),
              buffer.isCurrent(snapshot) else {
            record("context.changed stage=beforeReplacement")
            completion(.contextChanged)
            return true
        }

        return eventReplacer.replaceSuffix(
            deleting: slice.deletedCharacterCount,
            with: replacementInputs
        ) { [weak self] succeeded in
            guard let self else { return }
            guard succeeded else {
                self.record("replace.send.failed")
                completion(.failed)
                return
            }
            guard self.buffer.commitReplacement(
                slice.complete(with: transformed),
                inputs: completeInputs,
                expected: snapshot
            ) else {
                self.record("buffer.commit.failed")
                completion(.failed)
                return
            }
            self.record(
                "replace.posted buffer.commit.succeeded "
                    + "elapsedMs=\(self.elapsedMilliseconds(since: startedAt))"
            )
            completion(.replaced(transformation))
        }
    }

    private func makeReplacementInputs(
        text: String,
        replacing original: [TrackedKeyInput]
    ) -> [TrackedKeyInput] {
        let characters = text.map(String.init)
        guard characters.count == original.count else {
            return characters.map {
                TrackedKeyInput(text: $0, keyCode: 0, eventFlags: 0)
            }
        }
        return zip(characters, original).map { character, input in
            TrackedKeyInput(
                text: character,
                keyCode: input.keyCode,
                eventFlags: input.eventFlags
            )
        }
    }

    private func record(_ message: @autoclosure () -> String) {
        guard let diagnostics else { return }
        diagnostics(message())
    }

    private func elapsedMilliseconds(since startedAt: TimeInterval) -> Int {
        Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
    }
}
