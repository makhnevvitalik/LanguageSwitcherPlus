// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import Foundation
import LanguageSwitcherApplication
import LanguageSwitcherEdition
import LanguageSwitcherLocalization
import LanguageSwitcherMacOS

@MainActor
final class StatusMenuController: NSObject {
    private static let hideStatusBarIconKey = "hideStatusBarIcon"
    private static let panelContentWidth: CGFloat = 500
    private static let panelShadowInset: CGFloat = 10
    private static var panelWindowWidth: CGFloat {
        panelContentWidth + panelShadowInset * 2
    }

    private let statusItem: NSStatusItem
    private let identity: AppIdentity
    private let userDefaults: UserDefaults
    private let currentLanguage: () -> AppLanguage
    private let onLanguageChange: (AppLanguage) -> Void
    private let textToolsController: TextToolsMenuController
    private let keyboardSwitchingController: KeyboardSwitchingMenuController
    private let activeInputsController: ActiveInputsMenuController
    private let aboutWindowController: AboutWindowController
    private let currentState: () -> StatusMenuState
    private let onResumeKeyboardSwitching: () -> Void
    private let onLaunchAtLoginChange: (Bool) -> Void
    private let onExit: () -> Void

    private let panel = StatusPanel()
    private let contentStack = NSStackView()
    private let resumeCard = NSBox()
    private let launchAtLoginSwitch = NSSwitch()
    private let showInMenuBarSwitch = NSSwitch()
    private let languageButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    init(
        identity: AppIdentity,
        userDefaults: UserDefaults = .standard,
        currentLanguage: @escaping () -> AppLanguage,
        onLanguageChange: @escaping (AppLanguage) -> Void,
        textToolsController: TextToolsMenuController,
        keyboardSwitchingController: KeyboardSwitchingMenuController,
        activeInputsController: ActiveInputsMenuController,
        aboutWindowController: AboutWindowController,
        currentState: @escaping () -> StatusMenuState,
        onResumeKeyboardSwitching: @escaping () -> Void,
        onLaunchAtLoginChange: @escaping (Bool) -> Void,
        onExit: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.identity = identity
        self.userDefaults = userDefaults
        self.currentLanguage = currentLanguage
        self.onLanguageChange = onLanguageChange
        self.textToolsController = textToolsController
        self.keyboardSwitchingController = keyboardSwitchingController
        self.activeInputsController = activeInputsController
        self.aboutWindowController = aboutWindowController
        self.currentState = currentState
        self.onResumeKeyboardSwitching = onResumeKeyboardSwitching
        self.onLaunchAtLoginChange = onLaunchAtLoginChange
        self.onExit = onExit
        super.init()
        configureStatusItem()
        configurePanel()
        textToolsController.onWillPerformAction = { [weak self] in
            self?.closePanel()
        }
    }

    deinit {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
    }

    func showIcon() {
        userDefaults.set(false, forKey: Self.hideStatusBarIconKey)
        statusItem.isVisible = true
        showInMenuBarSwitch.state = .on
    }

    func hideIcon() {
        closePanel()
        statusItem.isVisible = false
        userDefaults.set(true, forKey: Self.hideStatusBarIconKey)
    }

    func dismissPanel() {
        closePanel()
    }

    private func configureStatusItem() {
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.accessibilityDescription = identity.productName
            statusItem.button?.image = image
        }
        statusItem.button?.toolTip = identity.productName
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.isVisible = !userDefaults.bool(forKey: Self.hideStatusBarIconKey)
    }

    private func configurePanel() {
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.allowsToolTipsWhenApplicationIsInactive = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow

        let canvas = NSView()
        let shadowContainer = RoundedPanelShadowView(cornerRadius: 20)
        shadowContainer.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 20
        background.layer?.masksToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false
        shadowContainer.addSubview(background)
        canvas.addSubview(shadowContainer)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.detachesHiddenViews = true
        contentStack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let header = makeHeader()
        configureResumeCard()
        let generalCard = makeGeneralCard()
        let quitCard = makeQuitCard()

        [
            header,
            resumeCard,
            textToolsController.view,
            keyboardSwitchingController.view,
            generalCard,
            quitCard
        ].forEach {
            contentStack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -20).isActive = true
        }

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(scrollView)
        NSLayoutConstraint.activate([
            shadowContainer.leadingAnchor.constraint(
                equalTo: canvas.leadingAnchor,
                constant: Self.panelShadowInset
            ),
            shadowContainer.trailingAnchor.constraint(
                equalTo: canvas.trailingAnchor,
                constant: -Self.panelShadowInset
            ),
            shadowContainer.topAnchor.constraint(
                equalTo: canvas.topAnchor,
                constant: Self.panelShadowInset
            ),
            shadowContainer.bottomAnchor.constraint(
                equalTo: canvas.bottomAnchor,
                constant: -Self.panelShadowInset
            ),
            background.leadingAnchor.constraint(equalTo: shadowContainer.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: shadowContainer.trailingAnchor),
            background.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
            background.bottomAnchor.constraint(equalTo: shadowContainer.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: background.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            background.widthAnchor.constraint(equalToConstant: Self.panelContentWidth)
        ])
        panel.contentView = canvas
    }

    private func makeHeader() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40)
        ])

        let title = NSTextField(labelWithString: identity.brandName)
        title.font = AppStyle.Font.appName

        let edition = NSTextField(labelWithString: identity.editionName)
        edition.font = AppStyle.Font.appEdition
        edition.textColor = .secondaryLabelColor

        let identityStack = NSStackView(views: [title, edition])
        identityStack.orientation = .vertical
        identityStack.alignment = .leading
        identityStack.spacing = 0

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let aboutButton = NSButton(
            title: localized("About"),
            target: self,
            action: #selector(showAbout)
        )
        aboutButton.bezelStyle = .inline
        aboutButton.isBordered = false
        aboutButton.contentTintColor = .linkColor
        aboutButton.font = AppStyle.Font.controlLabel

        let stack = NSStackView(views: [icon, identityStack, spacer, aboutButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 0, right: 4)
        return stack
    }

    private func configureResumeCard() {
        resumeCard.boxType = .custom
        resumeCard.borderWidth = 0
        resumeCard.fillColor = NSColor.systemYellow.withAlphaComponent(0.16)
        resumeCard.cornerRadius = MenuCardLayout.cardCornerRadius
        resumeCard.contentViewMargins = .zero

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "exclamationmark.shield", accessibilityDescription: nil)
        icon.contentTintColor = .systemOrange
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])

        let label = NSTextField(labelWithString: localized("Input Monitoring is paused"))
        label.font = AppStyle.Font.fieldLabel
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let button = NSButton(
            title: localized("Resume…"),
            target: self,
            action: #selector(resumeInputMonitoring)
        )
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = AppStyle.Font.controlLabel

        let stack = NSStackView(views: [icon, label, spacer, button])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        resumeCard.contentView?.addSubview(stack)
        if let contentView = resumeCard.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                stack.topAnchor.constraint(equalTo: contentView.topAnchor),
                stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }

    private func makeGeneralCard() -> NSView {
        let card = NSBox()
        card.boxType = .custom
        card.borderWidth = 0
        card.fillColor = .controlBackgroundColor
        card.cornerRadius = MenuCardLayout.cardCornerRadius
        card.contentViewMargins = .zero

        launchAtLoginSwitch.controlSize = .small
        showInMenuBarSwitch.controlSize = .small
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(toggleLaunchAtLogin(_:))
        launchAtLoginSwitch.setAccessibilityLabel(localized("Open at Login"))
        showInMenuBarSwitch.target = self
        showInMenuBarSwitch.action = #selector(toggleShowInMenuBar(_:))
        showInMenuBarSwitch.setAccessibilityLabel(localized("Show in Menu Bar"))
        showInMenuBarSwitch.state = .on
        languageButton.target = self
        languageButton.action = #selector(selectLanguage(_:))
        languageButton.controlSize = .small
        languageButton.font = AppStyle.Font.controlLabel
        languageButton.widthAnchor.constraint(
            greaterThanOrEqualToConstant: MenuCardLayout.popUpControlMinWidth
        ).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let heading = MenuCardLayout.sectionHeading(
            title: localized("General"),
            symbolName: "gearshape"
        )
        let launchRow = MenuCardLayout.row(
            title: localized("Open at Login"),
            detail: nil,
            trailing: launchAtLoginSwitch
        )
        let menuBarRow = MenuCardLayout.row(
            title: localized("Show in Menu Bar"),
            detail: localized("To restore the icon, reopen the app from Spotlight"),
            trailing: showInMenuBarSwitch
        )
        let languageRow = MenuCardLayout.row(
            title: localized("Language"),
            detail: nil,
            trailing: languageButton
        )
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(activeInputsController.view)
        MenuCardLayout.addSeparator(to: stack)
        stack.addArrangedSubview(languageRow)
        MenuCardLayout.addSeparator(to: stack)
        stack.addArrangedSubview(launchRow)
        MenuCardLayout.addSeparator(to: stack)
        stack.addArrangedSubview(menuBarRow)

        card.contentView?.addSubview(stack)
        if let contentView = card.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                stack.topAnchor.constraint(equalTo: contentView.topAnchor),
                stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
                activeInputsController.view.widthAnchor.constraint(equalTo: stack.widthAnchor),
                languageRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
                launchRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
                menuBarRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }
        return card
    }

    private func makeQuitCard() -> NSView {
        let card = NSBox()
        card.boxType = .custom
        card.borderWidth = 0
        card.fillColor = .controlBackgroundColor
        card.cornerRadius = MenuCardLayout.cardCornerRadius
        card.contentViewMargins = .zero

        let button = NSButton(title: localizedFormat("Quit %@", identity.brandName), target: self, action: #selector(exitAction))
        button.bezelStyle = .inline
        button.isBordered = false
        button.alignment = .left
        button.contentTintColor = .labelColor
        button.font = AppStyle.Font.controlLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        card.contentView?.addSubview(button)
        if let contentView = card.contentView {
            card.heightAnchor.constraint(equalToConstant: MenuCardLayout.simpleRowHeight).isActive = true
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
                button.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
                button.topAnchor.constraint(equalTo: contentView.topAnchor),
                button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
        return card
    }

    private func refresh() {
        let state = currentState()
        resumeCard.isHidden = !state.isInputMonitoringPaused
        launchAtLoginSwitch.isEnabled = state.isLaunchAtLoginAvailable
        launchAtLoginSwitch.state = state.isLaunchAtLoginEnabled ? .on : .off
        showInMenuBarSwitch.state = .on
        refreshLanguageMenu()
        textToolsController.refresh()
        keyboardSwitchingController.refresh()
        activeInputsController.refresh()
    }

    private func refreshLanguageMenu() {
        languageButton.removeAllItems()
        for language in AppLanguage.allCases {
            languageButton.addItem(withTitle: language.displayName)
            languageButton.lastItem?.representedObject = language.rawValue
        }
        if let index = AppLanguage.allCases.firstIndex(of: currentLanguage()) {
            languageButton.selectItem(at: index)
        }
    }

    @objc private func selectLanguage(_ sender: NSPopUpButton) {
        guard let identifier = sender.selectedItem?.representedObject as? String,
              let language = AppLanguage(rawValue: identifier) else { return }
        onLanguageChange(language)
    }

    private func showPanel() {
        refresh()
        updatePanelFrame()
        installEventMonitors()
        // Native controls use the key window’s accent. The panel stays nonactivating.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func closePanel() {
        panel.orderOut(nil)
        removeEventMonitors()
    }

    private func updatePanelFrame() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else {
            return
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        let desiredHeight = contentStack.fittingSize.height
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let screen = buttonWindow.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let contentHeight = min(
            desiredHeight,
            max(420, visibleFrame.height - 20 - Self.panelShadowInset * 2)
        )
        let windowHeight = contentHeight + Self.panelShadowInset * 2
        let x = min(
            max(screenRect.midX - Self.panelWindowWidth / 2, visibleFrame.minX),
            visibleFrame.maxX - Self.panelWindowWidth
        )
        let y = max(
            visibleFrame.minY,
            screenRect.minY - contentHeight - 7 - Self.panelShadowInset
        )
        panel.setFrame(
            NSRect(x: x, y: y, width: Self.panelWindowWidth, height: windowHeight),
            display: true
        )
    }

    private func installEventMonitors() {
        removeEventMonitors()
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.mouseIsOverStatusItem() else { return }
                self.closePanel()
            }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.closePanel()
                return nil
            }
            if event.window !== self.panel, !self.mouseIsOverStatusItem() {
                self.closePanel()
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func mouseIsOverStatusItem() -> Bool {
        guard let button = statusItem.button,
              let window = button.window else {
            return false
        }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
            .contains(NSEvent.mouseLocation)
    }

    @objc private func togglePanel() {
        panel.isVisible ? closePanel() : showPanel()
    }

    @objc private func resumeInputMonitoring() {
        closePanel()
        onResumeKeyboardSwitching()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSSwitch) {
        onLaunchAtLoginChange(sender.state == .on)
        refresh()
    }

    @objc private func toggleShowInMenuBar(_ sender: NSSwitch) {
        guard sender.state == .off else { return }
        closePanel()
        DispatchQueue.main.async { [weak self] in
            self?.hideIcon()
        }
    }

    @objc private func showAbout() {
        closePanel()
        aboutWindowController.showWindow()
    }

    @objc private func exitAction() {
        closePanel()
        onExit()
    }
}

private final class StatusPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class RoundedPanelShadowView: NSView {
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }
}
