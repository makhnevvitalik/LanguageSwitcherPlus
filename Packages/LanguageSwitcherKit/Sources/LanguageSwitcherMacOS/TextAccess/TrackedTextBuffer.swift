// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import LanguageSwitcherDomain

struct TrackedKeyInput: Equatable {
    let text: String
    let keyCode: UInt16
    let eventFlags: UInt64
}

struct TrackedTextBufferSnapshot: Equatable {
    let state: TrackedTextSnapshot
    let inputs: [TrackedKeyInput]

    var generation: UInt64 { state.generation }
    var text: String { state.text }
}

public final class TrackedTextBuffer {
    private var state = TrackedTextState()
    private var inputs: [TrackedKeyInput] = []

    public init() {}

    func snapshot(for applicationID: String) -> TrackedTextBufferSnapshot? {
        guard let snapshot = state.snapshot,
              snapshot.applicationID == applicationID,
              inputs.map(\.text).joined() == snapshot.text else {
            return nil
        }
        return TrackedTextBufferSnapshot(state: snapshot, inputs: inputs)
    }

    func recordPrintableText(
        _ text: String,
        keyCode: UInt16 = 0,
        eventFlags: UInt64 = 0,
        applicationID: String
    ) {
        guard let result = state.recordPrintableText(text, applicationID: applicationID) else {
            return
        }
        let newInputs = text.map {
            TrackedKeyInput(text: String($0), keyCode: keyCode, eventFlags: eventFlags)
        }
        switch result {
        case .appended:
            inputs.append(contentsOf: newInputs)
        case .startedNewSegment:
            inputs = newInputs
        }
    }

    func recordBackspace(applicationID: String) {
        state.recordBackspace(applicationID: applicationID)
        if state.snapshot == nil {
            inputs.removeAll()
        } else if !inputs.isEmpty {
            inputs.removeLast()
        }
    }

    func commitReplacement(
        _ text: String,
        inputs replacementInputs: [TrackedKeyInput],
        expected: TrackedTextBufferSnapshot
    ) -> Bool {
        guard replacementInputs.map(\.text).joined() == text,
              isCurrent(expected),
              state.commitReplacement(text, expected: expected.state) else {
            return false
        }
        inputs = replacementInputs
        return true
    }

    func isCurrent(_ snapshot: TrackedTextBufferSnapshot) -> Bool {
        state.snapshot == snapshot.state && inputs == snapshot.inputs
    }

    public func invalidate() {
        state.invalidate()
        inputs.removeAll()
    }
}
