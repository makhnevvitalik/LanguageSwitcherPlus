// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit

public enum ModifierShortcut: String, CaseIterable, Sendable {
    case functionGlobe
    case command

    var keyCodes: Set<UInt16> {
        switch self {
        case .functionGlobe: [63]
        case .command: [54, 55]
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .functionGlobe: .function
        case .command: .command
        }
    }

    var userDefaultsKey: String {
        switch self {
        case .functionGlobe: "keyboardShortcut.functionGlobe.enabled"
        case .command: "keyboardShortcut.command.enabled"
        }
    }
}
