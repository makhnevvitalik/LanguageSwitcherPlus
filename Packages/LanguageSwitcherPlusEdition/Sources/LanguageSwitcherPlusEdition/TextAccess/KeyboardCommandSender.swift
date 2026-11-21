// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import CoreGraphics
import LanguageSwitcherMacOS

enum KeyboardCommand: Equatable {
    case copy
}

protocol KeyboardCommandSending: AnyObject {
    func send(_ command: KeyboardCommand) -> Bool
}

final class KeyboardCommandSender: KeyboardCommandSending {
    private let makeSource: (CGEventSourceStateID) -> CGEventSource?
    private let post: (CGEventTapLocation, CGEvent) -> Void

    init(
        makeSource: @escaping (CGEventSourceStateID) -> CGEventSource? = {
            CGEventSource(stateID: $0)
        },
        post: @escaping (CGEventTapLocation, CGEvent) -> Void = {
            $1.post(tap: $0)
        }
    ) {
        self.makeSource = makeSource
        self.post = post
    }

    func send(_ command: KeyboardCommand) -> Bool {
        let descriptor = descriptor(for: command)
        guard let source = makeSource(.combinedSessionState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: descriptor.keyCode,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: descriptor.keyCode,
                  keyDown: false
              ) else {
            return false
        }

        keyDown.flags = descriptor.flags
        keyUp.flags = descriptor.flags
        for event in [keyDown, keyUp] {
            event.setIntegerValueField(
                .eventSourceUserData,
                value: KeyboardCommandEventMarker.value
            )
        }
        post(.cgSessionEventTap, keyDown)
        post(.cgSessionEventTap, keyUp)
        return true
    }

    private func descriptor(for command: KeyboardCommand) -> (keyCode: CGKeyCode, flags: CGEventFlags) {
        switch command {
        case .copy:
            (8, .maskCommand)
        }
    }
}
