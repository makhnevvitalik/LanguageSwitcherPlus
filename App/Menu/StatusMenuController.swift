// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import Foundation
import SwiftUI
import LanguageSwitcherEdition
import LanguageSwitcherLocalization

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private static let hideStatusBarIconKey = "hideStatusBarIcon"
    private static let panelContentWidth: CGFloat = 500
    private static let panelShadowInset: CGFloat = 10
    private static var panelWindowWidth: CGFloat {
        panelContentWidth + panelShadowInset * 2
    }

    private let statusItem: NSStatusItem
    private let statusBadge = StatusBadge()
    private let identity: AppIdentity
    private let userDefaults: UserDefaults
    private let currentLanguage: () -> AppLanguage
    private let onLanguageChange: (AppLanguage) -> Void
    private let textToolsController: TextToolsMenuController
    private let keyboardSwitchingController: KeyboardSwitchingMenuController
    private let aboutWindowController: AboutWindowController
    private let updateAvailability: UpdateAvailability
    private let currentState: () -> StatusMenuState
    private let onResumeKeyboardSwitching: () -> Void
    private let onLaunchAtLoginChange: (Bool) -> Void
    private let onExit: () -> Void

    private let panel = StatusPanel()
    private let panelBackground = makeCardBackground()
    private let scrollView = NSScrollView()
    private let presentation = PanelPresentation()
    private var hosting: NSHostingController<PanelContent>!
    private let documentView = StatusScrollDocumentView()
    private let loginItem = NSMenuItem()
    private let menuBarItem = NSMenuItem()
    private let languageMenu = NSMenu()
    private var settingsWindow: NSWindow?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    init(
        identity: AppIdentity,
        userDefaults: UserDefaults = .standard,
        currentLanguage: @escaping () -> AppLanguage,
        onLanguageChange: @escaping (AppLanguage) -> Void,
        textToolsController: TextToolsMenuController,
        keyboardSwitchingController: KeyboardSwitchingMenuController,
        aboutWindowController: AboutWindowController,
        updateAvailability: UpdateAvailability,
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
        self.aboutWindowController = aboutWindowController
        self.updateAvailability = updateAvailability
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

    private func showIcon() {
        userDefaults.set(false, forKey: Self.hideStatusBarIconKey)
        statusItem.isVisible = true
        menuBarItem.state = .on
    }

    private func hideIcon() {
        closePanel()
        statusItem.isVisible = false
        userDefaults.set(true, forKey: Self.hideStatusBarIconKey)
    }

    func dismissPanel() {
        closePanel()
    }

    func leaveForShortcutSettings(from trigger: NSButton) -> (() -> Void)? {
        guard let source = trigger.window else { return nil }
        return leaveForAuxiliaryWindow(from: source, restoringFocusTo: source.firstResponder === trigger ? trigger : nil)
    }

    private func leaveForAuxiliaryWindow(from source: NSWindow, restoringFocusTo trigger: NSControl?) -> (() -> Void)? {
        guard source === panel || source === settingsWindow else { return nil }
        let isPanel = source === panel
        let scrollOrigin = scrollView.contentView.bounds.origin
        if isPanel {
            closePanel()
        }
        return { [weak self, weak source, weak trigger] in
            guard let self, let source else { return }
            if isPanel {
                guard self.settingsWindow?.isVisible != true, self.statusItem.isVisible else { return }
                self.showPanel()
                let clip = self.scrollView.contentView
                let bounds = NSRect(origin: scrollOrigin, size: clip.bounds.size)
                clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
                self.scrollView.reflectScrolledClipView(clip)
            } else if source.isVisible {
                source.makeKeyAndOrderFront(nil)
            }
            if let trigger, trigger.window === source, trigger.isEnabled, source.isVisible {
                source.makeFirstResponder(trigger)
            }
        }
    }

    func refreshUpdateAvailability() {
        updateStatusBadge()
        resizeVisibleSurface()
    }

    func refreshMonitoringState() {
        guard updateMonitoringPresentation() else { return }
        resizeVisibleSurface()
    }

    private func resizeVisibleSurface() {
        if panel.isVisible {
            updatePanelFrame()
        } else if let window = settingsWindow, window.isVisible {
            resizeSettingsWindow(window)
        }
        updateScrollViewport()
    }

    func showSettings() {
        closePanel()
        let isFirstPresentation = settingsWindow == nil
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        guard let controller = window.contentViewController else { return }
        moveContent(to: controller, host: controller.view)
        refresh(isPanel: false)
        resizeSettingsWindow(window)
        updateScrollViewport()
        if isFirstPresentation {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        AppStyle.showWithoutInitialControlFocus(window)
    }

    private func resizeSettingsWindow(_ window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
        let availableHeight = visibleFrame?.height ?? 740
        let titleBarHeight = window.frame.height - contentView.frame.height
        let size = NSSize(
            width: Self.panelContentWidth,
            height: min(measureContent(), availableHeight - titleBarHeight - 20)
        )
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let bottom = window.frame.maxY - frame.height
        window.setFrame(
            NSRect(x: window.frame.minX, y: max(bottom, visibleFrame?.minY ?? bottom),
                   width: frame.width, height: frame.height),
            display: window.isVisible
        )
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = AppStyle.SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelContentWidth, height: 1),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = localizedFormat("%@ Settings", identity.productName)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        let controller = NSViewController()
        controller.view = Self.makeCardBackground()
        window.contentViewController = controller
        return window
    }

    private static func makeCardBackground() -> NSVisualEffectView {
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        return background
    }

    private func moveContent(to controller: NSViewController, host: NSView) {
        guard hosting.parent !== controller else { return }
        hosting.removeFromParent()
        controller.addChild(hosting)
        embedScrollView(in: host)
    }

    private func embedScrollView(in host: NSView) {
        guard scrollView.superview !== host else { return }
        scrollView.removeFromSuperview()
        scrollView.frame = host.bounds
        scrollView.autoresizingMask = [.width, .height]
        host.addSubview(scrollView)
    }

    private func configureStatusItem() {
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            image.size = AppStyle.Icon.menuBarSize
            image.accessibilityDescription = identity.productName
            statusItem.button?.image = image
        }
        if let button = statusItem.button {
            statusBadge.translatesAutoresizingMaskIntoConstraints = false
            statusBadge.setAccessibilityElement(false)
            button.addSubview(statusBadge)
            NSLayoutConstraint.activate([
                statusBadge.widthAnchor.constraint(equalToConstant: 6),
                statusBadge.heightAnchor.constraint(equalToConstant: 6),
                statusBadge.topAnchor.constraint(equalTo: button.topAnchor, constant: 3),
                statusBadge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3)
            ])
        }
        updateStatusBadge()
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

        let background = panelBackground
        background.wantsLayer = true
        background.layer?.cornerRadius = 20
        background.layer?.masksToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false
        shadowContainer.addSubview(background)
        canvas.addSubview(shadowContainer)

        hosting = NSHostingController(rootView: PanelContent(
            presentation: presentation, updateAvailability: updateAvailability, name: identity.productName,
            width: Self.panelContentWidth, settingsButton: makeSettingsButton(),
            textTools: textToolsController, keyboardSwitching: keyboardSwitchingController,
            resume: { [weak self] in self?.resumeInputMonitoring() },
            openRelease: { [weak self] in self?.openAvailableRelease() }
        ))
        hosting.sizingOptions = []
        documentView.addSubview(hosting.view)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentView
        embedScrollView(in: background)
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
            background.widthAnchor.constraint(equalToConstant: Self.panelContentWidth)
        ])
        let controller = NSViewController()
        controller.view = canvas
        controller.addChild(hosting)
        panel.contentViewController = controller
    }

    private func measureContent() -> CGFloat {
        let height = hosting.sizeThatFits(in: NSSize(width: Self.panelContentWidth, height: 10_000)).height
        documentView.frame.size = NSSize(width: Self.panelContentWidth, height: ceil(height))
        hosting.view.frame = documentView.bounds
        return documentView.frame.height
    }

    private func updateScrollViewport() {
        scrollView.hasVerticalScroller = documentView.frame.height > scrollView.bounds.height + 0.5
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func makeSettingsButton() -> NSPopUpButton {
        let button = AppStyle.SettingsMenuButton(frame: .zero, pullsDown: true)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.font = AppStyle.Font.body
        languageMenu.font = menu.font

        let iconItem = NSMenuItem()
        iconItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: AppStyle.Icon.settingsPointSize, weight: .regular))
        let languageItem = NSMenuItem(title: localized("Language"), action: nil, keyEquivalent: "")
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.displayName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        loginItem.title = localized("Open at Login")
        loginItem.action = #selector(toggleLaunchAtLogin)
        menuBarItem.title = localized("Show in Menu Bar")
        menuBarItem.action = #selector(toggleShowInMenuBar)
        let aboutItem = NSMenuItem(title: localized("About…"), action: #selector(showAbout), keyEquivalent: "")
        let quitItem = NSMenuItem(title: localizedFormat("Quit %@", identity.productName),
                                  action: #selector(exitAction), keyEquivalent: "")
        for item in [loginItem, menuBarItem, aboutItem, quitItem] { item.target = self }
        for item in [iconItem, languageItem, loginItem, menuBarItem, .separator(), aboutItem, quitItem] {
            menu.addItem(item)
        }
        button.menu = menu
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.controlSize = .small
        button.font = AppStyle.Font.body
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = localized("Settings")
        button.setAccessibilityLabel(localized("Settings"))
        button.widthAnchor.constraint(equalToConstant: AppStyle.Layout.settingsButtonSize.width).isActive = true
        button.heightAnchor.constraint(equalToConstant: AppStyle.Layout.settingsButtonSize.height).isActive = true
        return button
    }

    private func refresh(isPanel: Bool) {
        updateMonitoringPresentation()
        if presentation.isPanel != isPanel { presentation.isPanel = isPanel }
        textToolsController.allowsCaseActions = isPanel
        textToolsController.refresh()
        keyboardSwitchingController.refresh()
    }

    @discardableResult
    private func updateMonitoringPresentation() -> Bool {
        let warning = currentState().monitoringWarning
        guard presentation.monitoringWarning != warning else { return false }
        presentation.monitoringWarning = warning
        updateStatusBadge()
        return true
    }

    private func updateStatusBadge() {
        let detail: String?
        if let warning = presentation.monitoringWarning {
            statusBadge.color = .systemOrange
            detail = warning.title
        } else if updateAvailability.release != nil {
            statusBadge.color = .systemBlue
            detail = localized("Update available")
        } else {
            detail = nil
        }
        statusBadge.isHidden = detail == nil
        let label = detail.map { "\(identity.productName) — \($0)" } ?? identity.productName
        statusItem.button?.toolTip = label
        statusItem.button?.setAccessibilityLabel(label)
    }

    func menuWillOpen(_ menu: NSMenu) {
        let state = currentState()
        loginItem.state = state.isLaunchAtLoginEnabled ? .on : .off
        menuBarItem.state = userDefaults.bool(forKey: Self.hideStatusBarIconKey) ? .off : .on
        for item in languageMenu.items {
            item.state = item.representedObject as? String == currentLanguage().rawValue ? .on : .off
        }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let language = AppLanguage(rawValue: identifier) else { return }
        onLanguageChange(language)
    }

    private func showPanel() {
        settingsWindow?.close()
        guard let controller = panel.contentViewController else { return }
        moveContent(to: controller, host: panelBackground)
        refresh(isPanel: true)
        updatePanelFrame()
        updateScrollViewport()
        installEventMonitors()
        // Native controls use the key window’s accent. The panel stays nonactivating.
        AppStyle.showWithoutInitialControlFocus(panel)
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
        let desiredHeight = measureContent()
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
            if let window = event.window, window.level.rawValue >= NSWindow.Level.popUpMenu.rawValue { return event }
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

    @objc private func toggleLaunchAtLogin() {
        onLaunchAtLoginChange(!currentState().isLaunchAtLoginEnabled)
    }

    @objc private func toggleShowInMenuBar() {
        if userDefaults.bool(forKey: Self.hideStatusBarIconKey) {
            showIcon()
        } else {
            let wasPanelVisible = panel.isVisible
            hideIcon()
            if wasPanelVisible { showSettings() }
        }
    }

    @objc private func showAbout() {
        let source = panel.isVisible ? panel : settingsWindow.flatMap { $0.isVisible ? $0 : nil }
        let returnToSource = source.flatMap {
            leaveForAuxiliaryWindow(from: $0, restoringFocusTo: AppStyle.restorableControl(in: $0))
        }
        aboutWindowController.showWindow(returningTo: returnToSource)
    }

    @objc private func openAvailableRelease() {
        guard let release = updateAvailability.release else { return }
        closePanel()
        NSWorkspace.shared.open(release.url)
    }

    @objc private func exitAction() {
        closePanel()
        onExit()
    }
}

private final class StatusBadge: NSView {
    var color: NSColor = .systemOrange {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

private final class StatusScrollDocumentView: NSView {
    override var isFlipped: Bool { true }
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

    override func sendEvent(_ event: NSEvent) {
        let previous = firstResponder
        super.sendEvent(event)
        AppStyle.clearUnchangedFocus(in: self, after: event, previous: previous)
    }
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
