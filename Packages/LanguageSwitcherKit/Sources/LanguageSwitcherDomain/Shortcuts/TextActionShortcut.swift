// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

public enum TextActionShortcut: Codable, Equatable, Hashable, Sendable {
    case once(TextShortcutChord)
    case repeatTwice(TextShortcutChord)
    case holdAndTapTwice(heldModifiers: KeyModifiers, tapKey: TextShortcutKey)

    public var classicChord: TextShortcutChord? {
        switch self {
        case let .once(chord), let .repeatTwice(chord): chord
        case .holdAndTapTwice: nil
        }
    }

    public var physicalKeys: Set<TextShortcutKey> {
        switch self {
        case let .once(chord), let .repeatTwice(chord):
            return chord.keys
        case let .holdAndTapTwice(heldModifiers, tapKey):
            var keys = Set(
                ShortcutModifier.allCases.compactMap {
                    heldModifiers.contains($0.mask)
                        ? TextShortcutKey.modifier($0)
                        : nil
                }
            )
            keys.insert(tapKey)
            return keys
        }
    }

    public var isValidGlobalShortcut: Bool {
        switch self {
        case let .once(chord), let .repeatTwice(chord):
            return chord.isValid
        case let .holdAndTapTwice(heldModifiers, tapKey):
            guard !heldModifiers.isEmpty,
                  heldModifiers.subtracting(.textShortcutModifiers).isEmpty else {
                return false
            }
            return tapKey.accepts(heldModifiers)
        }
    }

}
