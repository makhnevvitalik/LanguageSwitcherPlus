// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import Foundation
import LanguageSwitcherDomain

@MainActor
final class TextToolsMenuController: NSObject {
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
    let view = NSBox()

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
        configureView()
    }

    func refresh() {
        refreshCaseMenu()
        scopeButton.selectItem(at: scopeButton.indexOfItem(withRepresentedObject: currentScope().rawValue))
        scopeButton.toolTip = scopeButton.selectedItem?.toolTip
        refreshIntervalMenu()
    }

    private func configureView() {
        view.boxType = .custom
        view.borderWidth = 0
        view.fillColor = .controlBackgroundColor
        view.cornerRadius = MenuCardLayout.cardCornerRadius
        view.contentViewMargins = .zero

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let heading = MenuCardLayout.sectionHeading(
            title: localized("Text actions"),
            symbolName: "wand.and.stars"
        )
        stack.addArrangedSubview(heading)

        MenuCardLayout.configurePopUpControl(changeCaseButton)
        changeCaseButton.toolTip = localized("Change the letter case of selected text.")
        changeCaseButton.target = self
        changeCaseButton.action = #selector(runCaseAction(_:))

        let caseRow = MenuCardLayout.row(
            title: localized("Change case"),
            detail: nil,
            trailing: changeCaseButton
        )
        stack.addArrangedSubview(caseRow)
        MenuCardLayout.addSeparator(to: stack)

        MenuCardLayout.configurePopUpControl(scopeButton)
        scopeButton.setAccessibilityLabel(localized("Apply to"))
        scopeButton.target = self
        scopeButton.action = #selector(selectScope(_:))
        configureScopeOptions()
        let scopeRow = MenuCardLayout.row(
            title: localized("Apply to"),
            detail: nil,
            trailing: scopeButton
        )
        stack.addArrangedSubview(scopeRow)
        MenuCardLayout.addSeparator(to: stack)

        let configureButton = NSButton(
            title: localized("Configure…"),
            target: self,
            action: #selector(showShortcutSettings)
        )
        configureButton.controlSize = .small
        configureButton.bezelStyle = .inline
        configureButton.isBordered = false
        configureButton.contentTintColor = .linkColor
        configureButton.font = AppStyle.Font.controlLabel
        let shortcutRow = MenuCardLayout.row(
            title: localized("Shortcuts"),
            detail: nil,
            trailing: configureButton
        )
        stack.addArrangedSubview(shortcutRow)
        MenuCardLayout.addSeparator(to: stack)

        intervalButton.target = self
        intervalButton.action = #selector(selectMultiPressInterval(_:))
        MenuCardLayout.configurePopUpControl(intervalButton)
        let intervalRow = MenuCardLayout.row(
            title: localized("Double-press interval"),
            detail: localized("Maximum pause between two presses"),
            trailing: intervalButton
        )
        stack.addArrangedSubview(intervalRow)

        guard let contentView = view.contentView else { return }
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
            caseRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scopeRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            shortcutRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            intervalRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
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

    private func refreshCaseMenu() {
        let menu = changeCaseButton.menu ?? NSMenu()
        menu.removeAllItems()
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
            item.isEnabled = !isBusy() && isActionAvailable(action)
            menu.addItem(item)
        }
        changeCaseButton.menu = menu
    }

    private func refreshIntervalMenu() {
        MenuCardLayout.configureTimeIntervalOptions(
            for: intervalButton,
            options: multiPressIntervalOptions,
            selectedValue: currentMultiPressInterval(),
            defaultValue: defaultMultiPressInterval
        )
    }

    @objc private func runCaseAction(_ sender: Any?) {
        let item = sender as? NSMenuItem ?? changeCaseButton.selectedItem
        guard let identifier = item?.representedObject as? String,
              let action = TextAction(identifier: identifier) else {
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
