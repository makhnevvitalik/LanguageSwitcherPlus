// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

struct TrackedKeyInput: Equatable {
    let character: Character
    let keyCode: UInt16
    let eventFlags: UInt64

    var text: String { String(character) }

    static func append(_ input: TrackedKeyInput, to inputs: inout [TrackedKeyInput]) {
        if let last = inputs.last {
            let joined = last.text + input.text
            let first = joined[joined.startIndex]
            if first.utf16.count != last.character.utf16.count {
                // A grapheme can span key events, so replay it as Unicode.
                inputs.removeLast()
                inputs.append(TrackedKeyInput(character: first, keyCode: 0, eventFlags: 0))
                inputs.append(contentsOf: joined.dropFirst().map {
                    TrackedKeyInput(character: $0, keyCode: input.keyCode, eventFlags: input.eventFlags)
                })
                return
            }
        }
        inputs.append(input)
    }
}

struct TrackedTextBufferSnapshot: Equatable {
    let generation: UInt64
    let applicationID: String
    let inputs: [TrackedKeyInput]

    var text: String { String(inputs.map(\.character)) }

    func replacingSuffix(deleting characterCount: Int, with replacement: [TrackedKeyInput]) -> [TrackedKeyInput] {
        var result = Array(inputs.dropLast(characterCount))
        for input in replacement {
            TrackedKeyInput.append(input, to: &result)
        }
        return result
    }
}

public final class TrackedTextBuffer {
    private var generation: UInt64 = 0
    private var applicationID: String?
    private var inputs: [TrackedKeyInput] = []
    private var startsNewSegmentOnNextInput = false
    private var needsFreshInputAfterBackspace = false

    public init() {}

    func snapshot(for applicationID: String) -> TrackedTextBufferSnapshot? {
        guard self.applicationID == applicationID, !inputs.isEmpty else { return nil }
        return TrackedTextBufferSnapshot(generation: generation, applicationID: applicationID, inputs: inputs)
    }

    func recordPrintableText(
        _ text: String,
        keyCode: UInt16 = 0,
        eventFlags: UInt64 = 0,
        applicationID: String
    ) {
        guard !text.isEmpty else { return }
        if self.applicationID != applicationID || startsNewSegmentOnNextInput {
            self.applicationID = applicationID
            inputs.removeAll(keepingCapacity: true)
            startsNewSegmentOnNextInput = false
        }
        for character in text {
            let input = TrackedKeyInput(character: character, keyCode: keyCode, eventFlags: eventFlags)
            TrackedKeyInput.append(input, to: &inputs)
        }
        needsFreshInputAfterBackspace = false
        generation &+= 1
    }

    func recordBackspace(applicationID: String) {
        guard !hasAmbiguousBackspace(for: applicationID) else { return }
        guard self.applicationID == applicationID, let last = inputs.last else {
            invalidate()
            return
        }
        // An editor can delete only part of a multi-scalar grapheme.
        if last.character.unicodeScalars.count > 1 {
            invalidate()
            self.applicationID = applicationID
            needsFreshInputAfterBackspace = true
            return
        }
        inputs.removeLast()
        startsNewSegmentOnNextInput = false
        generation &+= 1
    }

    func hasAmbiguousBackspace(for applicationID: String) -> Bool {
        self.applicationID == applicationID && needsFreshInputAfterBackspace
    }

    func commitReplacement(
        _ replacementInputs: [TrackedKeyInput],
        expected: TrackedTextBufferSnapshot
    ) -> Bool {
        guard isCurrent(expected) else { return false }
        inputs = replacementInputs
        startsNewSegmentOnNextInput = true
        generation &+= 1
        return true
    }

    func isCurrent(_ snapshot: TrackedTextBufferSnapshot) -> Bool {
        self.snapshot(for: snapshot.applicationID) == snapshot
    }

    public func invalidate() {
        generation &+= 1
        applicationID = nil
        inputs.removeAll()
        startsNewSegmentOnNextInput = false
        needsFreshInputAfterBackspace = false
    }
}
