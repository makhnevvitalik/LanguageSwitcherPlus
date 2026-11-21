// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import LanguageSwitcherDomain
import XCTest
@testable import LanguageSwitcherMacOS

final class TextShortcutGestureRecognizerTests: XCTestCase {
    func testModifiedLetterSupportsAllThreeGestures() {
        let key = TextShortcutKey.alphanumeric(ShortcutAlphanumericKey(rawValue: "A")!)
        let chord = TextShortcutChord(modifiers: .control, key: key)
        var recognizer = makeRecognizer([
            .convertToNextLayout: .once(chord),
            .changeCase(.uppercase): .repeatTwice(chord),
            .changeCase(.lowercase): .holdAndTapTwice(heldModifiers: .control, tapKey: key)
        ])
        func tap(at time: TimeInterval) -> TextShortcutRecognition {
            XCTAssertEqual(recognizer.handle(.keyDown(
                key, activeModifiers: .control, timestamp: time, isRepeat: false
            )), .none)
            return recognizer.handle(.keyUp(key, activeModifiers: .control, timestamp: time + 0.01))
        }

        func completeChord(at time: TimeInterval) -> TextShortcutRecognition {
            _ = recognizer.handle(down(.control, .control, time))
            XCTAssertEqual(tap(at: time + 0.01), .none)
            return recognizer.handle(up(.control, [], time + 0.03))
        }

        XCTAssertEqual(completeChord(at: 1), .wait(chord))
        XCTAssertEqual(recognizer.handleTimeout(chord: chord, at: 1.4, contextGeneration: 0), .convertToNextLayout)
        XCTAssertEqual(completeChord(at: 2), .wait(chord))
        XCTAssertEqual(completeChord(at: 2.1), .trigger(.changeCase(.uppercase)))
        _ = recognizer.handle(down(.control, .control, 3))
        XCTAssertEqual(tap(at: 3.1), .none)
        XCTAssertEqual(tap(at: 3.2), .trigger(.changeCase(.lowercase)))
        XCTAssertEqual(recognizer.handle(up(.control, [], 3.3)), .none)
    }

    func testModifiedLetterUsesModifiersAtLetterPress() {
        let key = TextShortcutKey.alphanumeric(.init(rawValue: "K")!)
        let chord = TextShortcutChord(modifiers: .command, key: key)
        let shiftedChord = TextShortcutChord(modifiers: [.command, .shift], key: key)
        for shiftWasReleasedBeforeLetter in [true, false] {
            var recognizer = makeRecognizer([
                .convertToNextLayout: .once(chord),
                .changeCase(.uppercase): .once(shiftedChord)
            ])
            _ = recognizer.handle(down(.command, .command, 1))
            if shiftWasReleasedBeforeLetter {
                _ = recognizer.handle(down(.shift, [.command, .shift], 1.1))
                _ = recognizer.handle(up(.shift, .command, 1.2))
            }
            _ = recognizer.handle(.keyDown(key, activeModifiers: .command, timestamp: 1.3, isRepeat: false))
            if !shiftWasReleasedBeforeLetter {
                _ = recognizer.handle(down(.shift, [.command, .shift], 1.4))
                _ = recognizer.handle(up(.shift, .command, 1.5))
            }
            _ = recognizer.handle(.keyUp(key, activeModifiers: .command, timestamp: 1.6))
            XCTAssertEqual(recognizer.handle(up(.command, [], 1.7)), .trigger(.convertToNextLayout))
        }
    }

    func testUniqueOnceGestureTriggersOnFullRelease() {
        let chord = TextShortcutChord(modifiers: [.shift, .option], functionKey: nil)
        var recognizer = makeRecognizer([.convertToNextLayout: .once(chord)])

        XCTAssertEqual(recognizer.handle(down(.shift, [.shift], 1.0)), .none)
        XCTAssertEqual(recognizer.handle(down(.option, [.shift, .option], 1.1)), .none)
        XCTAssertEqual(recognizer.handle(up(.option, [.shift], 1.2)), .none)
        XCTAssertEqual(
            recognizer.handle(up(.shift, [], 1.3)),
            .trigger(.convertToNextLayout)
        )
    }

    func testOnceWaitsWhenSameChordHasRepeatAndRepeatTriggersOnSecondRelease() {
        let chord = TextShortcutChord(modifiers: [.shift, .option], functionKey: nil)
        var recognizer = makeRecognizer([
            .convertToNextLayout: .once(chord),
            .changeCase(.uppercase): .repeatTwice(chord)
        ])

        completeChord(&recognizer, startingAt: 1.0)
        XCTAssertEqual(recognizer.lastResult, .wait(chord))
        completeChord(&recognizer, startingAt: 1.2)
        XCTAssertEqual(recognizer.lastResult, .trigger(.changeCase(.uppercase)))
    }

    func testOnceTriggersWhenRepeatWindowExpires() {
        let chord = TextShortcutChord(modifiers: [.shift, .option], functionKey: nil)
        var recognizer = makeRecognizer([
            .convertToNextLayout: .once(chord),
            .changeCase(.uppercase): .repeatTwice(chord)
        ])
        completeChord(&recognizer, startingAt: 1.0)

        XCTAssertEqual(
            recognizer.handleTimeout(chord: chord, at: 1.5, contextGeneration: 0),
            .convertToNextLayout
        )
    }

    func testDifferentClassicGestureBreaksRepeatSequence() {
        let repeatedChord = TextShortcutChord(
            modifiers: [.shift, .option],
            functionKey: nil
        )
        let otherChord = TextShortcutChord(
            modifiers: .control,
            functionKey: nil
        )
        var recognizer = makeRecognizer([
            .convertToNextLayout: .repeatTwice(repeatedChord),
            .changeCase(.uppercase): .once(otherChord)
        ])

        completeChord(&recognizer, startingAt: 1.0)
        XCTAssertEqual(recognizer.lastResult, .wait(repeatedChord))
        XCTAssertEqual(recognizer.handle(down(.control, .control, 1.1)), .none)
        XCTAssertEqual(
            recognizer.handle(up(.control, [], 1.11)),
            .trigger(.changeCase(.uppercase))
        )
        completeChord(&recognizer, startingAt: 1.2)

        XCTAssertEqual(recognizer.lastResult, .wait(repeatedChord))
    }

    func testBothHoldDirectionsAreDistinct() {
        var shiftHeld = makeRecognizer([
            .convertToNextLayout: .holdAndTapTwice(
                heldModifiers: .shift,
                tapKey: .modifier(.option)
            )
        ])
        XCTAssertEqual(performShiftHeldOptionTap(&shiftHeld, at: 1.0), .none)
        XCTAssertEqual(
            performShiftHeldOptionTap(&shiftHeld, at: 1.2),
            .trigger(.convertToNextLayout)
        )

        var optionHeld = makeRecognizer([
            .changeCase(.uppercase): .holdAndTapTwice(
                heldModifiers: .option,
                tapKey: .modifier(.shift)
            )
        ])
        XCTAssertEqual(performOptionHeldShiftTap(&optionHeld, at: 2.0), .none)
        XCTAssertEqual(
            performOptionHeldShiftTap(&optionHeld, at: 2.2),
            .trigger(.changeCase(.uppercase))
        )
    }

    func testFunctionKeyCanBeTappedWhileModifierIsHeld() {
        let f13 = ShortcutFunctionKey(rawValue: 13)!
        var recognizer = makeRecognizer([
            .convertToNextLayout: .holdAndTapTwice(
                heldModifiers: .control,
                tapKey: .function(f13)
            )
        ])

        XCTAssertEqual(recognizer.handle(down(.control, [.control], 1.0)), .none)
        XCTAssertEqual(recognizer.handle(.keyDown(
            .function(f13), activeModifiers: .control, timestamp: 1.1, isRepeat: false
        )), .none)
        XCTAssertEqual(recognizer.handle(.keyUp(
            .function(f13), activeModifiers: .control, timestamp: 1.11
        )), .none)
        XCTAssertEqual(recognizer.handle(.keyDown(
            .function(f13), activeModifiers: .control, timestamp: 1.2, isRepeat: false
        )), .none)
        XCTAssertEqual(
            recognizer.handle(.keyUp(
                .function(f13), activeModifiers: .control, timestamp: 1.21
            )),
            .trigger(.convertToNextLayout)
        )
    }

    func testHardwareRepeatDoesNotCountAsSecondTap() {
        let f13 = ShortcutFunctionKey(rawValue: 13)!
        var recognizer = makeRecognizer([
            .convertToNextLayout: .holdAndTapTwice(
                heldModifiers: .control,
                tapKey: .function(f13)
            )
        ])
        _ = recognizer.handle(down(.control, [.control], 1.0))
        _ = recognizer.handle(.keyDown(
            .function(f13), activeModifiers: .control, timestamp: 1.1, isRepeat: false
        ))

        XCTAssertEqual(recognizer.handle(.keyDown(
            .function(f13), activeModifiers: .control, timestamp: 1.2, isRepeat: true
        )), .none)
    }

    func testHoldGestureIsCancelledByHeldModifierReleaseUnrelatedInputAndTimeout() {
        let shortcut = TextActionShortcut.holdAndTapTwice(
            heldModifiers: .shift,
            tapKey: .modifier(.option)
        )

        var released = makeRecognizer([.convertToNextLayout: shortcut])
        _ = performShiftHeldOptionTap(&released, at: 1.0)
        _ = released.handle(up(.shift, [], 1.1))
        XCTAssertEqual(performShiftHeldOptionTap(&released, at: 1.2), .none)

        var interrupted = makeRecognizer([.convertToNextLayout: shortcut])
        _ = performShiftHeldOptionTap(&interrupted, at: 2.0)
        _ = interrupted.handle(.unrelatedInput)
        XCTAssertEqual(performShiftHeldOptionTap(&interrupted, at: 2.2), .none)

        var expired = makeRecognizer([.convertToNextLayout: shortcut])
        _ = performShiftHeldOptionTap(&expired, at: 3.0)
        XCTAssertEqual(performShiftHeldOptionTap(&expired, at: 3.5), .none)
    }

    func testHoldTriggerConsumesEnclosingClassicChordUntilRelease() {
        let chord = TextShortcutChord(modifiers: [.shift, .option], functionKey: nil)
        var recognizer = makeRecognizer([
            .changeCase(.uppercase): .once(chord),
            .convertToNextLayout: .holdAndTapTwice(
                heldModifiers: .shift,
                tapKey: .modifier(.option)
            )
        ])
        _ = recognizer.handle(down(.shift, [.shift], 1.0))
        _ = recognizer.handle(down(.option, [.shift, .option], 1.1))
        _ = recognizer.handle(up(.option, [.shift], 1.11))
        _ = recognizer.handle(down(.option, [.shift, .option], 1.2))
        XCTAssertEqual(
            recognizer.handle(up(.option, [.shift], 1.21)),
            .trigger(.convertToNextLayout)
        )

        XCTAssertEqual(recognizer.handle(up(.shift, [], 1.3)), .none)
    }

    func testContextChangeResetsPendingRecognition() {
        let chord = TextShortcutChord(modifiers: [.shift, .option], functionKey: nil)
        var recognizer = TextShortcutGestureRecognizer(
            shortcuts: [.convertToNextLayout: .once(chord)],
            maximumInterval: 0.3
        )
        _ = recognizer.handle(down(.shift, [.shift], 1.0), contextGeneration: 1)
        _ = recognizer.handle(down(.option, [.shift, .option], 1.1), contextGeneration: 1)
        _ = recognizer.handle(up(.option, [.shift], 1.2), contextGeneration: 2)

        XCTAssertEqual(
            recognizer.handle(up(.shift, [], 1.3), contextGeneration: 2),
            .none
        )
    }

    private func makeRecognizer(
        _ shortcuts: [TextAction: TextActionShortcut]
    ) -> RecordingRecognizer {
        RecordingRecognizer(recognizer: TextShortcutGestureRecognizer(
            shortcuts: shortcuts,
            maximumInterval: 0.3
        ))
    }

    private func completeChord(
        _ recognizer: inout RecordingRecognizer,
        startingAt timestamp: TimeInterval
    ) {
        _ = recognizer.handle(down(.shift, [.shift], timestamp))
        _ = recognizer.handle(down(.option, [.shift, .option], timestamp + 0.01))
        _ = recognizer.handle(up(.option, [.shift], timestamp + 0.02))
        _ = recognizer.handle(up(.shift, [], timestamp + 0.03))
    }

    private func performShiftHeldOptionTap(
        _ recognizer: inout RecordingRecognizer,
        at timestamp: TimeInterval
    ) -> TextShortcutRecognition {
        if recognizer.activeModifiers.isEmpty {
            _ = recognizer.handle(down(.shift, [.shift], timestamp - 0.01))
        }
        _ = recognizer.handle(down(.option, [.shift, .option], timestamp))
        return recognizer.handle(up(.option, [.shift], timestamp + 0.01))
    }

    private func performOptionHeldShiftTap(
        _ recognizer: inout RecordingRecognizer,
        at timestamp: TimeInterval
    ) -> TextShortcutRecognition {
        if recognizer.activeModifiers.isEmpty {
            _ = recognizer.handle(down(.option, [.option], timestamp - 0.01))
        }
        _ = recognizer.handle(down(.shift, [.shift, .option], timestamp))
        return recognizer.handle(up(.shift, [.option], timestamp + 0.01))
    }

    private func down(
        _ modifier: ShortcutModifier,
        _ active: KeyModifiers,
        _ timestamp: TimeInterval
    ) -> TextShortcutInputEvent {
        .keyDown(
            .modifier(modifier),
            activeModifiers: active,
            timestamp: timestamp,
            isRepeat: false
        )
    }

    private func up(
        _ modifier: ShortcutModifier,
        _ active: KeyModifiers,
        _ timestamp: TimeInterval
    ) -> TextShortcutInputEvent {
        .keyUp(.modifier(modifier), activeModifiers: active, timestamp: timestamp)
    }
}

private struct RecordingRecognizer {
    var recognizer: TextShortcutGestureRecognizer
    var lastResult: TextShortcutRecognition = .none
    var activeModifiers: KeyModifiers = []

    mutating func handle(
        _ event: TextShortcutInputEvent,
        contextGeneration: UInt64 = 0
    ) -> TextShortcutRecognition {
        switch event {
        case let .keyDown(_, modifiers, _, _), let .keyUp(_, modifiers, _):
            activeModifiers = modifiers
        case .unrelatedInput:
            break
        }
        lastResult = recognizer.handle(event, contextGeneration: contextGeneration)
        return lastResult
    }

    mutating func handleTimeout(
        chord: TextShortcutChord,
        at timestamp: TimeInterval,
        contextGeneration: UInt64
    ) -> TextAction? {
        recognizer.handleTimeout(
            chord: chord,
            at: timestamp,
            contextGeneration: contextGeneration
        )
    }
}
