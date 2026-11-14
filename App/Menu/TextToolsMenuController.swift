// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import SwiftUI
import Foundation
import LanguageSwitcherDomain

@MainActor
final class TextToolsMenuController: NSObject, NSMenuDelegate {
    private let isBusy: () -> Bool
    private let isActionAvailable: (TextAction) -> Bool
    private let performAction: (TextAction) -> Void
    private let currentScope: () -> TextConversionScope
    private let setScope: (TextConversionScope) -> Void
    private let configureShortcuts: () -> Void
    private let currentMultiPressInterval: () -> TimeInterval
    private let setMultiPressInterval: (TimeInterval) -> Void
    private let multiPressIntervalOptions: [TimeInterval]
    private let defaultMultiPressInterval: TimeInterval

    private let changeCaseButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let scopeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let intervalButton = NSPopUpButton(frame: .zero, pullsDown: false)

    var onWillPerformAction: (() -> Void)?
    var allowsCaseActions = true
    private lazy var configureButton: NSButton = {
        let button = NSButton(title: localized("Configure…"), target: self, action: #selector(showShortcutSettings))
        button.controlSize = .small
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .linkColor
        button.font = AppStyle.Font.controlLabel
        return button
    }()

    func content(isPanel: Bool) -> some View {
        PanelCard(title: localized("Text actions"), symbol: "wand.and.stars") {
            if isPanel {
                PanelRow(title: localized("Change case")) { PanelNativeControl(view: changeCaseButton) }
            } else {
                PanelRow(title: localized("Change case"),
                    detail: localized("Select text in another app. Use the menu bar icon to choose a case, or press your assigned shortcut.")) {
                    EmptyView()
                }
            }
            Divider()
            PanelRow(title: localized("Apply to")) { PanelNativeControl(view: scopeButton) }
            Divider()
            PanelRow(title: localized("Shortcuts")) { PanelNativeControl(view: configureButton) }
            Divider()
            PanelRow(title: localized("Double-press interval"), detail: localized("Maximum pause between two presses")) {
                PanelNativeControl(view: intervalButton)
            }
        }
    }

    init(
        isBusy: @escaping () -> Bool,
        isActionAvailable: @escaping (TextAction) -> Bool,
        performAction: @escaping (TextAction) -> Void,
        currentScope: @escaping () -> TextConversionScope,
        setScope: @escaping (TextConversionScope) -> Void,
        configureShortcuts: @escaping () -> Void,
        currentMultiPressInterval: @escaping () -> TimeInterval,
        setMultiPressInterval: @escaping (TimeInterval) -> Void,
        multiPressIntervalOptions: [TimeInterval],
        defaultMultiPressInterval: TimeInterval
    ) {
        self.isBusy = isBusy
        self.isActionAvailable = isActionAvailable
        self.performAction = performAction
        self.currentScope = currentScope
        self.setScope = setScope
        self.configureShortcuts = configureShortcuts
        self.currentMultiPressInterval = currentMultiPressInterval
        self.setMultiPressInterval = setMultiPressInterval
        self.multiPressIntervalOptions = multiPressIntervalOptions
        self.defaultMultiPressInterval = defaultMultiPressInterval
        super.init()
        configureControls()
    }

    func refresh() {
        scopeButton.selectItem(at: scopeButton.indexOfItem(withRepresentedObject: currentScope().rawValue))
        scopeButton.toolTip = scopeButton.selectedItem?.toolTip
        intervalButton.selectItem(at: intervalButton.indexOfItem(withRepresentedObject: currentMultiPressInterval()))
    }

    private func configureControls() {
        MenuCardLayout.configurePopUpControl(changeCaseButton)
        changeCaseButton.toolTip = localized("Change the letter case of selected text.")
        changeCaseButton.target = self
        changeCaseButton.action = #selector(runCaseAction(_:))
        configureCaseMenu()

        MenuCardLayout.configurePopUpControl(scopeButton)
        scopeButton.setAccessibilityLabel(localized("Apply to"))
        scopeButton.target = self
        scopeButton.action = #selector(selectScope(_:))
        configureScopeOptions()

        MenuCardLayout.configurePopUpControl(intervalButton)
        intervalButton.target = self
        intervalButton.action = #selector(selectMultiPressInterval(_:))
        MenuCardLayout.configureTimeIntervalOptions(for: intervalButton,
            options: multiPressIntervalOptions, selectedValue: currentMultiPressInterval(),
            defaultValue: defaultMultiPressInterval)
        refresh()
    }

    private func configureScopeOptions() {
        for scope in TextConversionScope.allCases {
            let title: String
            let toolTip: String
            switch scope {
            case .typedText:
                title = localized("Typed text")
                toolTip = localized("If text is selected, the action applies to it; otherwise, to all tracked typed text.")
            case .lastWord:
                title = localized("Last word")
                toolTip = localized("If text is selected, the action applies to it; otherwise, to the most recently tracked word.")
            case .selectionOnly:
                title = localized("Selection")
                toolTip = localized("The action applies only to selected text.")
            }
            scopeButton.addItem(withTitle: title)
            scopeButton.lastItem?.representedObject = scope.rawValue
            scopeButton.lastItem?.toolTip = toolTip
        }
    }

    private func configureCaseMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(
            title: "\u{2002}" + localized("Select case"),
            action: nil,
            keyEquivalent: ""
        ))
        for caseAction in TextCaseAction.allCases {
            let action = TextAction.changeCase(caseAction)
            let item = NSMenuItem(
                title: action.title,
                action: #selector(runCaseAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = action.identifier
            menu.addItem(item)
        }
        changeCaseButton.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        let canPerform = allowsCaseActions && !isBusy()
        for item in menu.items.dropFirst() {
            guard let identifier = item.representedObject as? String,
                  let action = TextAction(identifier: identifier) else { continue }
            item.isEnabled = canPerform && isActionAvailable(action)
        }
    }

    @objc private func runCaseAction(_ sender: Any?) {
        guard allowsCaseActions else { return }
        let item = sender as? NSMenuItem ?? changeCaseButton.selectedItem
        guard let identifier = item?.representedObject as? String,
              let action = TextAction(identifier: identifier),
              !isBusy(), isActionAvailable(action) else {
            return
        }
        onWillPerformAction?()
        performAction(action)
    }

    @objc private func selectScope(_ sender: NSPopUpButton) {
        guard let identifier = sender.selectedItem?.representedObject as? String,
              let scope = TextConversionScope(rawValue: identifier) else { return }
        setScope(scope)
        refresh()
    }

    @objc private func showShortcutSettings() {
        onWillPerformAction?()
        configureShortcuts()
    }

    @objc private func selectMultiPressInterval(_ sender: NSPopUpButton) {
        guard let interval = sender.selectedItem?.representedObject as? TimeInterval else { return }
        setMultiPressInterval(interval)
        refresh()
    }

}
