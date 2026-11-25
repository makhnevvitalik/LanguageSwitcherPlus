// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import LanguageSwitcherDomain

public enum TextShortcutConflict: Equatable, Sendable {
    public enum TypingEffect: Equatable, Sendable {
        case insertsText(String)
        case startsComposition
    }

    case system
    case documentedSystemCommand(String)
    case commonCommand(String)
    case typing(layout: String, effect: TypingEffect)
}

public enum ConfigureTextActionShortcutResult: Equatable, Sendable {
    case updated
    case conflict(TextAction)
    case conflictWithReservedShortcut
    case requiresConflictReview(TextShortcutConflict?)
    case invalid
}

public enum TextActionShortcutValidationResult: Equatable, Sendable {
    case valid
    case conflict(TextAction)
    case conflictWithReservedShortcut
    case externalConflict(TextShortcutConflict)
    case invalid
}

public final class ConfigureTextActionShortcut {
    private let store: any TextActionShortcutStore
    private let checkConflict: (TextActionShortcut) -> TextShortcutConflict?

    public init(
        store: any TextActionShortcutStore,
        checkConflict: @escaping (TextActionShortcut) -> TextShortcutConflict? = { _ in nil }
    ) {
        self.store = store
        self.checkConflict = checkConflict
    }

    public func setShortcut(
        _ shortcut: TextActionShortcut?,
        for action: TextAction,
        reservedShortcuts: [TextActionShortcut] = [],
        reviewedConflict: TextShortcutConflict? = nil
    ) -> ConfigureTextActionShortcutResult {
        guard let shortcut else {
            store.setShortcut(nil, for: action)
            return .updated
        }
        let conflict: TextShortcutConflict?
        switch validateShortcut(
            shortcut,
            for: action,
            reservedShortcuts: reservedShortcuts
        ) {
        case .valid:
            conflict = nil
        case let .externalConflict(current):
            conflict = current
        case let .conflict(action):
            return .conflict(action)
        case .conflictWithReservedShortcut:
            return .conflictWithReservedShortcut
        case .invalid:
            return .invalid
        }
        guard conflict != .system, conflict == reviewedConflict else {
            return .requiresConflictReview(conflict)
        }
        store.setShortcut(shortcut, for: action)
        return .updated
    }

    public func validateShortcut(
        _ shortcut: TextActionShortcut,
        for action: TextAction,
        reservedShortcuts: [TextActionShortcut] = []
    ) -> TextActionShortcutValidationResult {
        guard shortcut.isValidGlobalShortcut else { return .invalid }
        if let chord = shortcut.classicChord,
           reservedShortcuts.contains(where: { $0.classicChord == chord }) {
            return .conflictWithReservedShortcut
        }
        if let conflict = TextAction.allCases.first(where: {
            $0 != action && store.shortcut(for: $0) == shortcut
        }) {
            return .conflict(conflict)
        }
        if let conflict = checkConflict(shortcut) {
            return .externalConflict(conflict)
        }
        return .valid
    }
}
