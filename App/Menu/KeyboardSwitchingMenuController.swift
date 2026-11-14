// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import SwiftUI
import Foundation
import LanguageSwitcherDomain
import LanguageSwitcherMacOS

@MainActor
final class KeyboardSwitchingMenuController: NSObject {
    private let activeInputsController: ActiveInputsMenuController
    private let isShortcutEnabled: (ModifierShortcut) -> Bool
    private let setShortcutEnabled: (ModifierShortcut, Bool) -> Void
    private let currentTapDuration: () -> TimeInterval
    private let setTapDuration: (TimeInterval) -> Void
    private let durationOptions: [TimeInterval]
    private let defaultDuration: TimeInterval

    private var shortcutButtons: [ModifierShortcut: CompactSelectionButton] = [:]
    private let durationButton = NSPopUpButton(frame: .zero, pullsDown: false)

    private let buttons = NSStackView()

    var content: some View {
        PanelCard(title: localized("Keyboard switching"), symbol: "keyboard") {
            PanelRow(title: localized("Switch language with")) { PanelNativeControl(view: buttons) }
            Divider()
            PanelRow(title: localized("Shortcut tap duration"), detail: localized("Maximum time for a switching-key tap")) {
                PanelNativeControl(view: durationButton)
            }
            Divider()
            PanelRow(title: localized("Active inputs"), detail: localized("At least two active")) {
                PanelNativeControl(view: activeInputsController.view)
            }
        }
    }

    init(
        activeInputsController: ActiveInputsMenuController,
        isShortcutEnabled: @escaping (ModifierShortcut) -> Bool,
        setShortcutEnabled: @escaping (ModifierShortcut, Bool) -> Void,
        currentTapDuration: @escaping () -> TimeInterval,
        setTapDuration: @escaping (TimeInterval) -> Void,
        durationOptions: [TimeInterval],
        defaultDuration: TimeInterval
    ) {
        self.activeInputsController = activeInputsController
        self.isShortcutEnabled = isShortcutEnabled
        self.setShortcutEnabled = setShortcutEnabled
        self.currentTapDuration = currentTapDuration
        self.setTapDuration = setTapDuration
        self.durationOptions = durationOptions
        self.defaultDuration = defaultDuration
        super.init()
        configureControls()
    }

    func refresh() {
        activeInputsController.refresh()
        for shortcut in ModifierShortcut.allCases {
            guard let button = shortcutButtons[shortcut] else { continue }
            let isEnabled = isShortcutEnabled(shortcut)
            button.state = isEnabled ? .on : .off
            button.updateSelection(
                title: shortcut == .functionGlobe ? "fn" : "⌘",
                isSelected: isEnabled
            )
        }

        durationButton.selectItem(at: durationButton.indexOfItem(withRepresentedObject: currentTapDuration()))
    }

    private func configureControls() {
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = MenuCardLayout.compactControlSpacing
        for shortcut in ModifierShortcut.allCases {
            let button = CompactSelectionButton(
                title: shortcut == .functionGlobe ? "fn" : "⌘",
                target: self,
                action: #selector(toggleShortcut(_:))
            )
            button.setButtonType(.toggle)
            MenuCardLayout.configureCompactControl(button)
            button.tag = ModifierShortcut.allCases.firstIndex(of: shortcut) ?? 0
            button.toolTip = toolTip(for: shortcut)
            shortcutButtons[shortcut] = button
            buttons.addArrangedSubview(button)
        }

        durationButton.target = self
        durationButton.action = #selector(selectDuration(_:))
        MenuCardLayout.configurePopUpControl(durationButton)
        MenuCardLayout.configureTimeIntervalOptions(for: durationButton, options: durationOptions,
            selectedValue: currentTapDuration(), defaultValue: defaultDuration)
        refresh()
    }

    private func toolTip(for shortcut: ModifierShortcut) -> String {
        switch shortcut {
        case .functionGlobe:
            localized("Press and release Fn/Globe to switch to the next active input source. Set the macOS Fn/Globe action to Do Nothing.")
        case .command:
            localized("Press and release Command to switch to the next active input source.")
        }
    }

    @objc private func toggleShortcut(_ sender: NSButton) {
        guard ModifierShortcut.allCases.indices.contains(sender.tag) else { return }
        let shortcut = ModifierShortcut.allCases[sender.tag]
        setShortcutEnabled(shortcut, sender.state == .on)
        refresh()
    }

    @objc private func selectDuration(_ sender: NSPopUpButton) {
        guard let duration = sender.selectedItem?.representedObject as? TimeInterval else { return }
        setTapDuration(duration)
        refresh()
    }

}
