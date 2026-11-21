// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import LanguageSwitcherDomain

/// Decodes a macOS key event for both shortcut recording and recognition.
public struct TextShortcutKeyInput {
    public let key: TextShortcutKey?
    public let modifiers: KeyModifiers
    public let hasFn: Bool

    public var rejectsFn: Bool { hasFn && key?.isAlphanumeric == true }

    public init(event: NSEvent) {
        modifiers = KeyModifiers(eventModifierFlags: event.modifierFlags).intersection(.textShortcutModifiers)
        hasFn = event.modifierFlags.contains(.function)
        switch event.type {
        case .flagsChanged:
            key = ShortcutModifier(keyCode: event.keyCode).map(TextShortcutKey.modifier)
        case .keyDown, .keyUp:
            key = TextShortcutKey(nonModifierKeyCode: event.keyCode)
        default:
            key = nil
        }
    }
}

public extension ShortcutModifier {
    init?(keyCode: UInt16) {
        switch keyCode {
        case 56, 60: self = .shift
        case 59, 62: self = .control
        case 58, 61: self = .option
        case 54, 55: self = .command
        default: return nil
        }
    }
}

public extension ShortcutFunctionKey {
    init?(keyCode: UInt16) {
        guard let number = Self.numberByKeyCode[keyCode] else { return nil }
        self.init(rawValue: number)
    }

    private static let numberByKeyCode: [UInt16: Int] = [
        122: 1, 120: 2, 99: 3, 118: 4, 96: 5,
        97: 6, 98: 7, 100: 8, 101: 9, 109: 10,
        103: 11, 111: 12, 105: 13, 107: 14, 113: 15,
        106: 16, 64: 17, 79: 18, 80: 19, 90: 20
    ]
}

public extension TextShortcutKey {
    init?(nonModifierKeyCode keyCode: UInt16) {
        if let functionKey = ShortcutFunctionKey(keyCode: keyCode) {
            self = .function(functionKey)
        } else if let name = Self.alphanumericNameByKeyCode[keyCode],
                  let key = ShortcutAlphanumericKey(rawValue: name) {
            self = .alphanumeric(key)
        } else {
            return nil
        }
    }

    fileprivate static let alphanumericNameByKeyCode: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R",
        1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9"
    ]
}

extension ShortcutAlphanumericKey {
    var keyCode: UInt16? {
        TextShortcutKey.alphanumericNameByKeyCode.first { $0.value == rawValue }?.key
    }
}
