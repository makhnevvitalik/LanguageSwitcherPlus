// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import CoreGraphics
import Foundation

public protocol SelectedTextEventReplacing: AnyObject {
    var isBusy: Bool { get }

    @discardableResult
    func replaceSelection(
        with text: String,
        completion: @escaping (Bool) -> Void
    ) -> Bool
}

protocol TrackedTextEventReplacing: AnyObject {
    var isBusy: Bool { get }

    @discardableResult
    func replaceSuffix(
        deleting characterCount: Int,
        with inputs: [TrackedKeyInput],
        completion: @escaping (Bool) -> Void
    ) -> Bool
}

public final class CGEventTextReplacer: SelectedTextEventReplacing {
    private static let compositionCommitKeyCodes: [CGKeyCode] = [49, 123, 124]

    private let makeSource: (CGEventSourceStateID) -> CGEventSource?
    private let post: (CGEventTapLocation, CGEvent) -> Void
    private let schedule: (@escaping () -> Void) -> Void
    public private(set) var isBusy = false

    public convenience init() {
        self.init(
            makeSource: {
                CGEventSource(stateID: $0)
            },
            post: {
                $1.post(tap: $0)
            },
            schedule: {
                DispatchQueue.main.async(execute: $0)
            }
        )
    }

    init(
        makeSource: @escaping (CGEventSourceStateID) -> CGEventSource? = {
            CGEventSource(stateID: $0)
        },
        post: @escaping (CGEventTapLocation, CGEvent) -> Void,
        schedule: @escaping (@escaping () -> Void) -> Void
    ) {
        self.makeSource = makeSource
        self.post = post
        self.schedule = schedule
    }

    func replaceSuffix(
        deleting characterCount: Int,
        with inputs: [TrackedKeyInput],
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        guard !isBusy else { return false }
        guard characterCount >= 0 else {
            completion(false)
            return true
        }

        var eventPairs: [[CGEvent]] = []
        for keyCode in Self.compositionCommitKeyCodes {
            guard let pair = makeKeyPair(keyCode: keyCode, flags: []) else {
                completion(false)
                return true
            }
            eventPairs.append(pair)
        }

        for _ in 0...characterCount {
            guard let pair = makeKeyPair(keyCode: 51, flags: []) else {
                completion(false)
                return true
            }
            eventPairs.append(pair)
        }

        for input in inputs {
            let utf16 = Array(input.text.utf16)
            guard let pair = makeKeyPair(
                keyCode: CGKeyCode(input.keyCode),
                flags: CGEventFlags(rawValue: input.eventFlags),
                unicode: utf16
            ) else {
                completion(false)
                return true
            }
            eventPairs.append(pair)
        }

        return post(eventPairs, completion: completion)
    }

    public func replaceSelection(
        with text: String,
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        guard !isBusy else { return false }
        guard !text.isEmpty else {
            completion(false)
            return true
        }

        var eventPairs: [[CGEvent]] = []
        for character in text {
            guard let pair = makeKeyPair(
                keyCode: 0,
                flags: [],
                unicode: Array(String(character).utf16)
            ) else {
                completion(false)
                return true
            }
            eventPairs.append(pair)
        }

        return post(eventPairs, completion: completion)
    }

    private func post(
        _ eventPairs: [[CGEvent]],
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        isBusy = true
        eventPairs.forEach(schedulePair)
        schedule { [weak self] in
            guard let self else { return }
            self.isBusy = false
            completion(true)
        }
        return true
    }

    private func schedulePair(_ pair: [CGEvent]) {
        schedule { [post] in
            pair.forEach { post(.cgSessionEventTap, $0) }
        }
    }

    private func makeKeyPair(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        unicode: [UniChar]? = nil
    ) -> [CGEvent]? {
        guard let source = makeSource(.combinedSessionState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: false
              ) else {
            return nil
        }

        keyDown.flags = flags
        keyUp.flags = flags
        for event in [keyDown, keyUp] {
            event.setIntegerValueField(
                .eventSourceUserData,
                value: KeyboardCommandEventMarker.value
            )
            if let unicode {
                unicode.withUnsafeBufferPointer { buffer in
                    event.keyboardSetUnicodeString(
                        stringLength: buffer.count,
                        unicodeString: buffer.baseAddress
                    )
                }
            }
        }
        return [keyDown, keyUp]
    }
}

extension CGEventTextReplacer: TrackedTextEventReplacing {}
