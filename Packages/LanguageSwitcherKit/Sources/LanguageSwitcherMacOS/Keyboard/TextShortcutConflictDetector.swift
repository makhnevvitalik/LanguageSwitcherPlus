// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Carbon
import LanguageSwitcherDomain

public enum TextShortcutConflict: Equatable {
    case system
    case documentedSystemCommand(String)
    case commonCommand(String)
}

public enum TextShortcutConflictDetector {
    private static let typeToSiri = TextActionShortcut.repeatTwice(
        TextShortcutChord(modifiers: .command, functionKey: nil)
    )

    @MainActor
    public static func conflict(for shortcut: TextActionShortcut) -> TextShortcutConflict? {
        guard shortcut == typeToSiri || shortcut.nonModifierChord != nil else { return nil }
        var result: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&result)
        let entries = result?.takeRetainedValue() as? [[String: Any]]
        let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let fallback = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        return conflict(
            for: shortcut,
            entries: status == noErr ? entries ?? [] : [],
            layoutData: layout?.property(kTISPropertyUnicodeKeyLayoutData) as? Data,
            fallbackLayoutData: fallback?.property(kTISPropertyUnicodeKeyLayoutData) as? Data
        )
    }

    static func conflict(
        for shortcut: TextActionShortcut,
        entries: [[String: Any]],
        layoutData: Data? = nil,
        fallbackLayoutData: Data? = nil
    ) -> TextShortcutConflict? {
        if shortcut == typeToSiri {
            return .documentedSystemCommand("Type to Siri")
        }
        guard let chord = shortcut.nonModifierChord else { return nil }
        let modifierMask = carbonModifierFlags(for: chord.modifiers)
        let matching = entries.filter { entry in
            guard (entry[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.intValue == modifierMask,
                  let value = (entry[kHISymbolicHotKeyCode as String] as? NSNumber)?.intValue,
                  let keyCode = UInt16(exactly: value) else { return false }
            return TextShortcutKey(nonModifierKeyCode: keyCode) == chord.nonModifierKey
        }
        let enabledKey = kHISymbolicHotKeyEnabled as String
        if matching.contains(where: { ($0[enabledKey] as? NSNumber)?.boolValue == true }) {
            return .system
        }

        let keys = commandKeys(for: chord, layoutData: layoutData, fallbackLayoutData: fallbackLayoutData)
        if matching.isEmpty {
            // Screenshots, accessibility, and navigation defaults are physical keys.
            let physicalName = chord.functionKey.map { "f\($0.rawValue)" }
                ?? chord.alphanumericKey?.rawValue.lowercased()
            if let physicalName, let command = systemDefaults[chord.modifiers]?[physicalName] {
                return .documentedSystemCommand(command)
            }
            if let command = keys.lazy.compactMap({ systemCharacterCommands[$0.modifiers]?[$0.symbol] }).first {
                return .documentedSystemCommand(command)
            }
        }
        return keys.lazy.compactMap { applicationCommands[$0.modifiers]?[$0.symbol] }
            .first.map(TextShortcutConflict.commonCommand)
    }

    private static func commandKeys(
        for chord: TextShortcutChord, layoutData: Data?, fallbackLayoutData: Data?
    ) -> [(modifiers: KeyModifiers, symbol: String)] {
        guard let key = chord.alphanumericKey, let keyCode = key.keyCode else { return [] }
        guard let layout = layoutData ?? fallbackLayoutData else {
            return [(chord.modifiers, key.rawValue.lowercased())]
        }
        // Command can switch a layout's key map. Ignore Option and Control glyphs,
        // since these modifiers are represented separately in menu key equivalents.
        let command = chord.modifiers.contains(.command) ? UInt32(cmdKey) : 0
        let base = TISKeyboardLayoutProvider.output(
            layoutData: layout, keyCode: keyCode, modifiers: command
        )
        var keys: [(KeyModifiers, String)] = []
        if chord.modifiers.contains(.shift) {
            let shift = UInt32(shiftKey)
            var shifted = TISKeyboardLayoutProvider.output(
                layoutData: layout, keyCode: keyCode, modifiers: command | shift
            )
            // Some layouts ignore Shift in their Command map for punctuation.
            if command != 0, shifted == base,
               TISKeyboardLayoutProvider.output(layoutData: layout, keyCode: keyCode, modifiers: 0) == base {
                shifted = TISKeyboardLayoutProvider.output(layoutData: layout, keyCode: keyCode, modifiers: shift)
            }
            if let shifted, shifted != base, shifted.utf8.count == 1, let symbol = shifted.first,
               symbol.isPunctuation || symbol.isSymbol || symbol.isNumber {
                // Shift can be implicit in symbols such as '?' or digits on AZERTY.
                keys.append((chord.modifiers.subtracting(.shift), shifted))
            }
        }
        if let base, base.utf8.count == 1 { keys.append((chord.modifiers, base.lowercased())) }
        return keys
    }

    private static func carbonModifierFlags(for modifiers: KeyModifiers) -> Int {
        var result = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.control) { result |= controlKey }
        return result
    }

    // Keyboard combinations listed directly in Apple Support article 102650.
    // Symbols are included because some layouts place them on assignable physical keys.
    private static let applicationCommands: [KeyModifiers: [String: String]] = [
        .command: [
            "1": "Finder Icon View", "2": "Finder List View", "3": "Finder Column View", "4": "Finder Gallery View",
            "a": "Select All", "b": "Bold", "c": "Copy", "d": "Duplicate Files or Go to Desktop",
            "e": "Eject Disk", "f": "Find", "g": "Find Next", "h": "Hide App", "i": "Italic or Show File Info",
            "j": "Show Finder View Options", "k": "Insert Link or Connect to Server", "m": "Minimize Window",
            "n": "New Window or Document", "o": "Open", "p": "Print", "q": "Quit App", "r": "Refresh or Show Original",
            "s": "Save", "t": "New Tab, Fonts or Finder Tab Bar", "u": "Underline", "v": "Paste",
            "w": "Close Window", "x": "Cut", "y": "Quick Look", "z": "Undo",
            ",": "Open App Settings", "/": "Toggle Finder Status Bar", "[": "Previous Finder Folder",
            "]": "Next Finder Folder", ";": "Find Misspelled Words", ":": "Spelling and Grammar",
            "{": "Align Left", "}": "Align Right", "|": "Align Center",
            "=": "Increase Size", "+": "Increase Size", "?": "Open Help"
        ],
        [.command, .shift]: [
            "c": "Open Computer in Finder", "d": "Open Desktop", "f": "Open Recents",
            "g": "Find Previous or Go to Folder", "h": "Open Home Folder", "i": "Open iCloud Drive",
            "k": "Open Network", "n": "New Folder", "o": "Open Documents",
            "p": "Page Setup or Finder Preview", "r": "Open AirDrop", "s": "Save As or Duplicate",
            "t": "Toggle Finder Tab Bar", "u": "Open Utilities", "z": "Redo", "-": "Decrease Size"
        ],
        [.command, .option]: [
            "c": "Copy Style", "f": "Focus Search", "h": "Hide Other Apps", "i": "Toggle Inspector",
            "l": "Open Downloads", "m": "Minimize All Windows", "n": "New Smart Folder",
            "p": "Toggle Finder Path Bar", "s": "Toggle Finder Sidebar", "t": "Toggle Toolbar",
            "v": "Paste Style or Move Files", "w": "Close All Windows", "y": "Quick Look Slideshow"
        ],
        [.command, .option, .shift]: ["v": "Paste and Match Style"],
        [.command, .control]: [
            "a": "Create Finder Alias", "d": "Look Up Word", "f": "Toggle Full Screen",
            "n": "New Folder With Selection", "t": "Add to Finder Sidebar"
        ],
        [.command, .control, .shift]: ["t": "Add Finder Item to Dock"],
        .control: [
            "a": "Move to Beginning of Line or Paragraph", "b": "Move One Character Backward",
            "d": "Delete Forward", "e": "Move to End of Line or Paragraph", "f": "Move One Character Forward",
            "h": "Delete Backward", "k": "Cut Selection or Text to End of Paragraph",
            "l": "Center Cursor or Selection in View", "n": "Move Down One Line", "o": "Insert Line After Cursor",
            "p": "Move Up One Line", "t": "Transpose Characters", "y": "Paste Text Cut With Control-K"
        ]
    ]

    private static let systemDefaults: [KeyModifiers: [String: String]] = [
        []: ["f11": "Show Desktop"],
        [.command, .shift]: [
            "3": "Capture Entire Screen", "4": "Capture Screen Area",
            "5": "Open Screenshot Controls", "6": "Ask Siri About Screen Area"
        ],
        [.command, .option]: ["f5": "Open Accessibility Shortcuts"],
        [.command, .control, .option]: ["8": "Invert Display Colors"],
        .control: [
            "f2": "Focus Menu Bar", "f3": "Focus Dock", "f4": "Focus Window", "f5": "Focus Window Toolbar",
            "f6": "Focus Floating Window", "f7": "Toggle Full Keyboard Focus", "f8": "Focus Status Menus"
        ],
        [.control, .shift]: ["f6": "Focus Previous Panel"]
    ]

    private static let systemCharacterCommands: [KeyModifiers: [String: String]] = [
        .command: ["`": "Next App Window"],
        [.command, .shift]: ["q": "Log Out", "`": "Previous App Window"],
        [.command, .control]: ["q": "Lock Screen"],
        [.command, .option]: ["d": "Toggle Dock", "`": "Focus Window Drawer"],
        [.command, .option, .shift]: ["q": "Log Out Without Confirmation"],
        [.command, .control, .option]: [",": "Reduce Display Contrast", ".": "Increase Display Contrast"]
    ]
}
