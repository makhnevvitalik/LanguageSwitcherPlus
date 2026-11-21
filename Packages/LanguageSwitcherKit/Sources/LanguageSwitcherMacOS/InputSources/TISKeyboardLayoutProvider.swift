// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Carbon
import LanguageSwitcherApplication
import LanguageSwitcherDomain

public final class TISKeyboardLayoutProvider: KeyboardLayoutProvider {
    static let conversionModifierStates: [UInt32] = [
        0,
        UInt32(shiftKey)
    ]

    public init() {}

    public func characters(inputSourceID: String) -> Set<Character>? {
        guard let source = inputSource(id: inputSourceID),
              let sourceData = source.property(kTISPropertyUnicodeKeyLayoutData) as? Data else {
            return nil
        }

        var characters: Set<Character> = []
        for keyCode in UInt16(0)..<128 {
            for modifiers in Self.conversionModifierStates {
                guard let text = Self.output(
                    layoutData: sourceData,
                    keyCode: keyCode,
                    modifiers: modifiers
                ), text.count == 1, let character = text.first else {
                    continue
                }
                characters.insert(character)
            }
        }
        return characters.isEmpty ? nil : characters
    }

    public func map(
        from sourceInputSourceID: String,
        to targetInputSourceID: String
    ) -> KeyboardLayoutMap? {
        guard let source = inputSource(id: sourceInputSourceID),
              let target = inputSource(id: targetInputSourceID),
              let sourceData = source.property(kTISPropertyUnicodeKeyLayoutData) as? Data,
              let targetData = target.property(kTISPropertyUnicodeKeyLayoutData) as? Data else {
            return nil
        }

        let mainKeyCodes = (UInt16(0)..<128).filter { !KeyboardLayoutKeyGroup.isKeypad($0) }
        let keypadKeyCodes = (UInt16(0)..<128).filter(KeyboardLayoutKeyGroup.isKeypad)
        let map = KeyboardLayoutMap(pairTiers: [
            pairs(
                sourceData: sourceData,
                targetData: targetData,
                keyCodes: mainKeyCodes,
                modifierStates: Self.conversionModifierStates
            ),
            pairs(
                sourceData: sourceData,
                targetData: targetData,
                keyCodes: keypadKeyCodes,
                modifierStates: Self.conversionModifierStates
            )
        ])
        return map.isEmpty ? nil : map
    }

    private func pairs(
        sourceData: Data,
        targetData: Data,
        keyCodes: [UInt16],
        modifierStates: [UInt32]
    ) -> [KeyboardLayoutPair] {
        var pairs: [KeyboardLayoutPair] = []
        for keyCode in keyCodes {
            for modifiers in modifierStates {
                guard let sourceText = Self.output(
                    layoutData: sourceData,
                    keyCode: keyCode,
                    modifiers: modifiers
                ), let targetText = Self.output(
                    layoutData: targetData,
                    keyCode: keyCode,
                    modifiers: modifiers
                ) else {
                    continue
                }
                pairs.append(KeyboardLayoutPair(source: sourceText, target: targetText))
            }
        }
        return pairs
    }

    private func inputSource(id: String) -> TISInputSource? {
        TISInputSourceCatalog.selectableInputSource(id: id)
    }

    static func output(
        layoutData: Data,
        keyCode: UInt16,
        modifiers: UInt32
    ) -> String? {
        layoutData.withUnsafeBytes { rawBuffer -> String? in
            guard let baseAddress = rawBuffer.baseAddress else {
                return nil
            }

            let layout = UnsafePointer<UCKeyboardLayout>(
                OpaquePointer(baseAddress)
            )
            var deadKeyState: UInt32 = 0
            var actualLength = 0
            var characters = [UniChar](repeating: 0, count: 8)
            let modifierState = (modifiers >> 8) & 0xFF

            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierState,
                UInt32(LMGetKbdType()),
                0,
                &deadKeyState,
                characters.count,
                &actualLength,
                &characters
            )

            guard status == noErr, deadKeyState == 0, actualLength > 0 else {
                return nil
            }
            return String(utf16CodeUnits: characters, count: Int(actualLength))
        }
    }
}

enum KeyboardLayoutKeyGroup {
    private static let keypadKeyCodes: Set<UInt16> = [
        65, 67, 69, 71, 75, 76, 78, 81,
        82, 83, 84, 85, 86, 87, 88, 89, 91, 92
    ]

    static func isKeypad(_ keyCode: UInt16) -> Bool {
        keypadKeyCodes.contains(keyCode)
    }
}
