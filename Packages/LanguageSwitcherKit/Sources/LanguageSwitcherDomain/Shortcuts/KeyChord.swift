// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
    public static let function = KeyModifiers(rawValue: 1 << 4)
}

public enum ShortcutModifier: String, Codable, CaseIterable, Hashable, Sendable {
    case shift
    case control
    case option
    case command

    public var mask: KeyModifiers {
        switch self {
        case .shift: .shift
        case .control: .control
        case .option: .option
        case .command: .command
        }
    }
}

public struct ShortcutFunctionKey: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init?(rawValue: Int) {
        guard (1...20).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }
}

/// An A–Z or 0–9 key named by its position on a US keyboard.
public struct ShortcutAlphanumericKey: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.utf8.count == 1, let byte = rawValue.utf8.first,
              (65...90).contains(byte) || (48...57).contains(byte) else { return nil }
        self.rawValue = rawValue
    }
}

public enum TextShortcutKey: Codable, Hashable, Sendable {
    case modifier(ShortcutModifier)
    case function(ShortcutFunctionKey)
    case alphanumeric(ShortcutAlphanumericKey)

    public var modifierMask: KeyModifiers? {
        guard case let .modifier(modifier) = self else { return nil }
        return modifier.mask
    }

    public func accepts(_ modifiers: KeyModifiers) -> Bool {
        switch self {
        case let .modifier(modifier): !modifiers.contains(modifier.mask)
        case .function: true
        case .alphanumeric: !modifiers.intersection([.control, .option, .command]).isEmpty
        }
    }
}

public struct TextShortcutChord: Codable, Hashable, Sendable {
    public let modifiers: KeyModifiers
    public let functionKey: ShortcutFunctionKey?
    public let alphanumericKey: ShortcutAlphanumericKey?

    public init(
        modifiers: KeyModifiers,
        functionKey: ShortcutFunctionKey?,
        alphanumericKey: ShortcutAlphanumericKey? = nil
    ) {
        self.modifiers = modifiers
        self.functionKey = functionKey
        self.alphanumericKey = alphanumericKey
    }

    public init(modifiers: KeyModifiers, key: TextShortcutKey) {
        switch key {
        case let .modifier(modifier):
            self.init(modifiers: modifiers.union(modifier.mask), functionKey: nil)
        case let .function(functionKey):
            self.init(modifiers: modifiers, functionKey: functionKey)
        case let .alphanumeric(alphanumericKey):
            self.init(modifiers: modifiers, functionKey: nil, alphanumericKey: alphanumericKey)
        }
    }

    public var nonModifierKey: TextShortcutKey? {
        functionKey.map(TextShortcutKey.function) ?? alphanumericKey.map(TextShortcutKey.alphanumeric)
    }

    public var isValid: Bool {
        guard modifiers.subtracting(.textShortcutModifiers).isEmpty,
              functionKey == nil || alphanumericKey == nil else { return false }
        return nonModifierKey?.accepts(modifiers) ?? !modifiers.isEmpty
    }

    public var keys: Set<TextShortcutKey> {
        var result = Set(
            ShortcutModifier.allCases.compactMap {
                modifiers.contains($0.mask) ? TextShortcutKey.modifier($0) : nil
            }
        )
        if let nonModifierKey {
            result.insert(nonModifierKey)
        }
        return result
    }
}

public extension KeyModifiers {
    static let textShortcutModifiers: KeyModifiers = [
        .shift, .control, .option, .command
    ]
}
