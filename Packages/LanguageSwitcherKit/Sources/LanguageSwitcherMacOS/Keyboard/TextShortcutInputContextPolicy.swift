// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import LanguageSwitcherDomain

struct TextShortcutInputContextPolicy {
    private let chords: Set<TextShortcutChord>

    init(shortcuts: [TextAction: TextActionShortcut]) {
        chords = Set(shortcuts.values.compactMap(\.nonModifierChord))
    }

    var hasAlphanumericShortcuts: Bool { chords.contains { $0.alphanumericKey != nil } }

    func shouldPreserveContext(for event: TextShortcutInputEvent) -> Bool {
        guard case let .keyDown(
            key,
            activeModifiers,
            _,
            isRepeat
        ) = event,
              key.modifierMask == nil, !isRepeat else {
            return false
        }
        return matches(key, modifiers: activeModifiers)
    }

    private func matches(_ key: TextShortcutKey, modifiers: KeyModifiers) -> Bool {
        chords.contains(TextShortcutChord(modifiers: modifiers, key: key))
    }
}

extension TextShortcutKey {
    var isAlphanumeric: Bool {
        if case .alphanumeric = self { return true }
        return false
    }
}

extension TextActionShortcut {
    var nonModifierChord: TextShortcutChord? {
        guard isValidGlobalShortcut else { return nil }
        switch self {
        case let .once(chord), let .repeatTwice(chord):
            return chord.nonModifierKey == nil ? nil : chord
        case let .holdAndTapTwice(heldModifiers, tapKey):
            guard tapKey.modifierMask == nil else { return nil }
            return TextShortcutChord(modifiers: heldModifiers, key: tapKey)
        }
    }
}
