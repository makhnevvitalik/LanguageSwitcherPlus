// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit

enum ModifierTapEvent {
    case flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags, timestamp: TimeInterval)
    case keyDown(flags: NSEvent.ModifierFlags)
    case mouseDown(flags: NSEvent.ModifierFlags)
}

struct StandaloneModifierTapTracker {
    private let keyCodes: Set<UInt16>
    private let modifierFlag: NSEvent.ModifierFlags
    private let maximumTapDuration: TimeInterval
    private var pressedKeyCodes: Set<UInt16> = []
    private var pressStartedAt: TimeInterval?
    private var wasUsedInCombination = false

    static func functionGlobe(maximumTapDuration: TimeInterval) -> Self {
        Self(shortcut: .functionGlobe, maximumTapDuration: maximumTapDuration)
    }

    static func command(maximumTapDuration: TimeInterval) -> Self {
        Self(shortcut: .command, maximumTapDuration: maximumTapDuration)
    }

    init(shortcut: ModifierShortcut, maximumTapDuration: TimeInterval) {
        self.init(
            keyCodes: shortcut.keyCodes,
            modifierFlag: shortcut.modifierFlag,
            maximumTapDuration: maximumTapDuration
        )
    }

    init(
        keyCodes: Set<UInt16>,
        modifierFlag: NSEvent.ModifierFlags,
        maximumTapDuration: TimeInterval
    ) {
        self.keyCodes = keyCodes
        self.modifierFlag = modifierFlag
        self.maximumTapDuration = maximumTapDuration
    }

    mutating func handle(_ event: ModifierTapEvent) -> Bool {
        switch event {
        case let .flagsChanged(keyCode, flags, timestamp):
            return handleFlagsChanged(keyCode: keyCode, flags: flags, timestamp: timestamp)
        case let .keyDown(flags):
            markCombinationIfNeeded(flags: flags)
        case let .mouseDown(flags):
            if modifierFlag == .command {
                markCombinationIfNeeded(flags: flags)
            }
        }
        return false
    }

    private mutating func handleFlagsChanged(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) -> Bool {
        let flags = flags.intersection(.deviceIndependentFlagsMask)

        guard keyCodes.contains(keyCode) else {
            if !pressedKeyCodes.isEmpty, containsDisallowedFlags(flags) {
                wasUsedInCombination = true
            }
            return false
        }

        if flags.contains(modifierFlag) {
            if pressedKeyCodes.isEmpty {
                pressStartedAt = timestamp
                wasUsedInCombination = false
            } else if !pressedKeyCodes.contains(keyCode) {
                wasUsedInCombination = true
            }
            pressedKeyCodes.insert(keyCode)
            if containsDisallowedFlags(flags) {
                wasUsedInCombination = true
            }
            return false
        }

        // The aggregate flag clears only after every key for this modifier is released.
        pressedKeyCodes.removeAll()

        defer {
            pressStartedAt = nil
            wasUsedInCombination = false
        }
        guard let pressStartedAt else {
            return false
        }

        return !wasUsedInCombination
            && !containsDisallowedFlags(flags)
            && timestamp - pressStartedAt < maximumTapDuration - 1e-9
    }

    private mutating func markCombinationIfNeeded(flags: NSEvent.ModifierFlags) {
        guard !pressedKeyCodes.isEmpty,
              flags.intersection(.deviceIndependentFlagsMask).contains(modifierFlag) else {
            return
        }
        wasUsedInCombination = true
    }

    private func containsDisallowedFlags(_ flags: NSEvent.ModifierFlags) -> Bool {
        !flags.subtracting([modifierFlag, .capsLock]).isEmpty
    }
}
