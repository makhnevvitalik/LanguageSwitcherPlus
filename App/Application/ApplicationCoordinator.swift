// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import Foundation
import LanguageSwitcherApplication
import LanguageSwitcherDomain
import LanguageSwitcherEdition
import LanguageSwitcherLocalization
import LanguageSwitcherMacOS
import ServiceManagement

@MainActor
final class ApplicationCoordinator: NSObject {
    private static let launchAtLoginPromptShownKey = "launchAtLogin.promptShown"
    private static let textShortcutPermissionSetupPendingKey =
        "textShortcutPermissions.setupPending"

    private let identity: AppIdentity
    private let appController: AppController
    private let languageStore: AppLanguageStore
    private let inputMonitoringPermission = LanguageSwitcherMacOS.InputMonitoringPermissionController()
    private var statusMenuController: StatusMenuController?
    private var shortcutSettingsWindowController: TextShortcutSettingsWindowController?
    private var isShowingInputMonitoringWarning = false
    private var isShowingAccessibilityWarning = false
    private var isRestarting = false
    private var isRecordingShortcut = false
    private var hasStarted = false
    private var hasRequestedInputMonitoring = false
    private var hasPresentedPendingAccessibilityGuidance = false

    init(
        identity: AppIdentity,
        appController: AppController,
        languageStore: AppLanguageStore
    ) {
        self.identity = identity
        self.appController = appController
        self.languageStore = languageStore
    }

    func start() {
        hasStarted = true
        configureMenu()
        appController.onInputMonitoringUnavailable = { [weak self] in
            self?.showInputMonitoringRecovery()
        }
        appController.onAccessibilityUnavailable = { [weak self] in
            self?.showAccessibilityRecovery()
        }
#if INTERNAL_BUILD
        appController.onTextActionResult = { result in
            TextActionDebugJournal.recordResult(String(describing: result))
        }
#endif

        NSApp.setActivationPolicy(.accessory)
        NSApp.hide(nil)

        validateFunctionGlobeSetting()
        promptForLaunchAtLoginIfNeeded()
        startKeyboardMonitoringIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.continuePendingTextShortcutPermissionSetup()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        statusMenuController?.showIcon()
        if flag {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.filter(\.isVisible).forEach { $0.orderFront(nil) }
            return false
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.hide(nil)
        return false
    }

    func applicationDidBecomeActive() {
        guard hasStarted,
              !isRestarting,
              !isRecordingShortcut,
              !isShowingInputMonitoringWarning,
              !isShowingAccessibilityWarning else {
            return
        }
        startKeyboardMonitoringIfNeeded()
        continuePendingTextShortcutPermissionSetup()
    }

    func stop() {
        appController.stopKeyboardMonitoring()
    }

    private func configureMenu() {
        let appController = self.appController
        let defaultMultiPressInterval = appController.defaultTextShortcutMultiPressInterval
        let defaultTapDuration = appController.defaultModifierTapDuration
        let shortcutWindow = TextShortcutSettingsWindowController(
            shortcut: { [weak appController] action in
                appController?.textShortcut(for: action)
            },
            validateShortcut: { [weak appController] shortcut, action in
                appController?.validateTextShortcut(shortcut, for: action) ?? .invalid
            },
            setShortcut: { [weak self] shortcut, action in
                self?.setTextShortcut(shortcut, for: action) ?? .invalid
            },
            onRecordingChanged: { [weak self] isRecording in
                guard let self else { return }
                self.isRecordingShortcut = isRecording
                self.appController.setTextShortcutRecording(isRecording)
                if !isRecording {
                    self.continuePendingTextShortcutPermissionSetup()
                }
            }
        )
        shortcutSettingsWindowController = shortcutWindow

        let textTools = TextToolsMenuController(
            isBusy: { [weak appController] in
                appController?.isTextActionBusy ?? false
            },
            isActionAvailable: { [weak appController] action in
                appController?.isTextActionAvailable(action) ?? false
            },
            performAction: { [weak appController] action in
                appController?.performMenuTextAction(action)
            },
            currentScope: { [weak appController] in
                appController?.textConversionScope ?? .typedText
            },
            setScope: { [weak appController] scope in
                appController?.textConversionScope = scope
            },
            configureShortcuts: { [weak shortcutWindow] in
                shortcutWindow?.showWindow()
            },
            currentMultiPressInterval: { [weak appController] in
                appController?.maximumTextShortcutMultiPressInterval
                    ?? defaultMultiPressInterval
            },
            setMultiPressInterval: { [weak appController] interval in
                appController?.setMaximumTextShortcutMultiPressInterval(interval)
            },
            multiPressIntervalOptions: appController.textShortcutMultiPressIntervalOptions,
            defaultMultiPressInterval: defaultMultiPressInterval
        )
        let keyboardSwitching = KeyboardSwitchingMenuController(
            isShortcutEnabled: { [weak appController] shortcut in
                appController?.isModifierShortcutEnabled(shortcut) ?? false
            },
            setShortcutEnabled: { [weak self] shortcut, enabled in
                guard let self else { return }
                let result = self.appController.setModifierShortcut(shortcut, enabled: enabled)
                if case let .unavailable(issue) = result {
                    switch issue {
                    case .functionGlobe:
                        self.showFunctionGlobeUnavailableWarning(issue: issue)
                    case .commandShortcutConflict:
                        self.showKeyboardShortcutConflictWarning(issue: issue)
                    }
                }
            },
            currentTapDuration: { [weak appController] in
                appController?.maximumModifierTapDuration
                    ?? defaultTapDuration
            },
            setTapDuration: { [weak appController] duration in
                appController?.setMaximumModifierTapDuration(duration)
            },
            durationOptions: appController.modifierTapDurationOptions,
            defaultDuration: defaultTapDuration
        )
        let activeInputs = ActiveInputsMenuController(
            inputSources: { [weak appController] in
                appController?.availableInputSources ?? []
            },
            isSelected: { [weak appController] inputSource in
                appController?.isInputSourceSelected(inputSource) ?? true
            },
            setSelected: { [weak appController] inputSource, selected in
                appController?.setInputSource(inputSource, selected: selected) ?? .notFound
            }
        )

        statusMenuController = StatusMenuController(
            identity: identity,
            currentLanguage: { [weak languageStore] in
                languageStore?.selectedLanguage ?? .english
            },
            onLanguageChange: { [weak self] language in
                guard let self,
                      self.languageStore.selectedLanguage != language else { return }
                let previousLanguage = self.languageStore.selectedLanguage
                self.languageStore.select(language)
                self.restartApplication { [weak self] in
                    self?.languageStore.select(previousLanguage)
                }
            },
            textToolsController: textTools,
            keyboardSwitchingController: keyboardSwitching,
            activeInputsController: activeInputs,
            aboutWindowController: AboutWindowController(identity: identity),
            currentState: { [weak self, weak appController] in
                let isRecordingShortcut = self?.isRecordingShortcut ?? false
                return StatusMenuState(
                    isInputMonitoringPaused: !isRecordingShortcut
                        && (appController?.isInputMonitoringPaused ?? false),
                    isLaunchAtLoginAvailable: Self.isLaunchAtLoginAvailable,
                    isLaunchAtLoginEnabled: Self.isLaunchAtLoginEnabled
                )
            },
            onResumeKeyboardSwitching: { [weak self] in
                self?.resumeKeyboardSwitching()
            },
            onLaunchAtLoginChange: { [weak self] enabled in
                self?.setLaunchAtLoginEnabled(enabled)
            },
            onExit: { [weak self] in
                self?.terminate()
            }
        )
    }

    private func setTextShortcut(
        _ shortcut: TextActionShortcut?,
        for action: TextAction
    ) -> ConfigureTextActionShortcutResult {
        let setupWasPending = isTextShortcutPermissionSetupPending
        if shortcut != nil,
           TextShortcutPermissionSetup.nextStep(
               inputMonitoringAllowed: inputMonitoringPermission.isAllowed,
               accessibilityAllowed: appController.isAccessibilityAllowed
           ) != .complete {
            isTextShortcutPermissionSetupPending = true
        }

        let result = appController.setTextShortcut(shortcut, for: action)
        guard result == .updated else {
            isTextShortcutPermissionSetupPending = setupWasPending
            return result
        }
        if shortcut == nil, !appController.hasConfiguredTextShortcuts {
            isTextShortcutPermissionSetupPending = false
        }
        return result
    }

    private func validateFunctionGlobeSetting() {
        guard appController.isModifierShortcutEnabled(.functionGlobe) else { return }
        let result = appController.setModifierShortcut(.functionGlobe, enabled: true)
        if case let .unavailable(issue) = result {
            showFunctionGlobeUnavailableWarning(issue: issue)
        }
    }

    private func resumeKeyboardSwitching() {
        startKeyboardMonitoringIfNeeded()
        if appController.isInputMonitoringPaused {
            showInputMonitoringRecovery(allowSettingsFallback: true)
        }
    }

    private func startKeyboardMonitoringIfNeeded() {
        if !appController.isKeyboardMonitoringRunning {
            appController.startKeyboardMonitoring()
        }
        if appController.isKeyboardMonitoringRunning {
            hasRequestedInputMonitoring = false
        }
    }

    private func showInputMonitoringRecovery(allowSettingsFallback: Bool = false) {
        guard !isShowingInputMonitoringWarning,
              !isShowingAccessibilityWarning,
              !isRestarting,
              allowSettingsFallback
                || !hasRequestedInputMonitoring
                || inputMonitoringPermission.isAllowed else {
            return
        }
        isShowingInputMonitoringWarning = true
        statusMenuController?.showIcon()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.isShowingInputMonitoringWarning = false }
            guard self.appController.isInputMonitoringPaused else { return }

            self.prepareForModalPresentation()
            let isAllowed = self.inputMonitoringPermission.isAllowed
            let shouldRequest = !isAllowed && !self.hasRequestedInputMonitoring
            let alert = NSAlert()
            if self.isTextShortcutPermissionSetupPending {
                alert.messageText = localized("Step 1 of 2: Allow Input Monitoring")
                alert.informativeText = localizedFormat(
                    "%1$@ needs Input Monitoring to detect your global text shortcut. The shortcut is saved. Allow %1$@ in %2$@. If macOS asks, choose Quit & Reopen; the app will reopen and continue with Accessibility.",
                    self.identity.productName,
                    self.inputMonitoringSettingsPath
                )
            } else {
                alert.messageText = localized("Input Monitoring is unavailable.")
                alert.informativeText = localizedFormat(
                    "Allow %1$@ in %2$@, then return to the app. If macOS asks, choose Quit & Reopen.",
                    self.identity.productName,
                    self.inputMonitoringSettingsPath
                )
            }
            if shouldRequest {
                alert.addButton(withTitle: localized("Grant Access"))
            } else if isAllowed {
                alert.addButton(
                    withTitle: localizedFormat("Restart %@", self.identity.productName)
                )
            } else {
                alert.addButton(withTitle: self.inputMonitoringSettingsButtonTitle)
            }
            alert.addButton(withTitle: localized("Later"))

            let response = alert.runModal()
            alert.window.orderOut(nil)
            if response == .alertFirstButtonReturn {
                if shouldRequest {
                    self.hasRequestedInputMonitoring = true
                    _ = self.inputMonitoringPermission.requestAccess()
                } else if isAllowed {
                    self.restartApplication()
                } else {
                    _ = self.inputMonitoringPermission.openSettings()
                }
            } else if self.isTextShortcutPermissionSetupPending {
                self.cancelPendingTextShortcutPermissionSetup()
            }
        }
    }

    private func showAccessibilityRecovery() {
        guard !isShowingAccessibilityWarning,
              !isShowingInputMonitoringWarning,
              !isRestarting else {
            return
        }
        isShowingAccessibilityWarning = true
        statusMenuController?.showIcon()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.isShowingAccessibilityWarning = false }
            guard !self.appController.isAccessibilityAllowed else { return }

            self.prepareForModalPresentation()
            let alert = NSAlert()
            alert.messageText = self.isTextShortcutPermissionSetupPending
                ? localized("Step 2 of 2: Allow Accessibility")
                : localized("Accessibility access is required.")
            let nextAction = self.isTextShortcutPermissionSetupPending
                ? localized("Your shortcut is saved and will work after access is allowed.")
                : localized("After allowing access, run the text action again.")
            alert.informativeText = localizedFormat(
                "Add %1$@ manually in %2$@:\n\n1. Click +.\n2. Select /Applications/%1$@.app.\n3. Turn the app on.\n\n%3$@",
                self.identity.productName,
                self.accessibilitySettingsPath,
                nextAction
            )
            alert.addButton(withTitle: localized("Open Accessibility Settings"))
            alert.addButton(withTitle: localized("Later"))

            if alert.runModal() == .alertFirstButtonReturn {
                self.appController.openAccessibilitySettings()
            } else if self.isTextShortcutPermissionSetupPending {
                self.cancelPendingTextShortcutPermissionSetup()
            }
        }
    }

    private func continuePendingTextShortcutPermissionSetup() {
        guard isTextShortcutPermissionSetupPending,
              !isRecordingShortcut,
              !isShowingInputMonitoringWarning,
              !isShowingAccessibilityWarning,
              !isRestarting else {
            return
        }
        switch TextShortcutPermissionSetup.nextStep(
            inputMonitoringAllowed: inputMonitoringPermission.isAllowed,
            accessibilityAllowed: appController.isAccessibilityAllowed
        ) {
        case .inputMonitoring:
            showInputMonitoringRecovery()
        case .accessibility:
            guard !hasPresentedPendingAccessibilityGuidance else { return }
            hasPresentedPendingAccessibilityGuidance = true
            showAccessibilityRecovery()
        case .complete:
            isTextShortcutPermissionSetupPending = false
            hasPresentedPendingAccessibilityGuidance = false
        }
    }

    private func cancelPendingTextShortcutPermissionSetup() {
        isTextShortcutPermissionSetupPending = false
        hasPresentedPendingAccessibilityGuidance = false
    }

    private var isTextShortcutPermissionSetupPending: Bool {
        get {
            UserDefaults.standard.bool(
                forKey: Self.textShortcutPermissionSetupPendingKey
            )
        }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey: Self.textShortcutPermissionSetupPendingKey
            )
        }
    }

    private func terminate() {
        hasRequestedInputMonitoring = false
        NSApp.terminate(nil)
    }

    private func restartApplication(onFailure: (() -> Void)? = nil) {
        guard !isRestarting else { return }
        isRestarting = true
        let wasKeyboardMonitoringRunning = appController.isKeyboardMonitoringRunning
        appController.stopKeyboardMonitoring()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] application, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if application != nil {
                    NSApp.terminate(nil)
                } else {
                    self.isRestarting = false
                    onFailure?()
                    if wasKeyboardMonitoringRunning {
                        self.appController.startKeyboardMonitoring()
                    }
                    let alert = NSAlert()
                    alert.messageText = localizedFormat(
                        "Could not restart %@.",
                        self.identity.productName
                    )
                    alert.informativeText = error?.localizedDescription
                        ?? localizedFormat(
                            "Quit %@ from its menu, then open it again from Applications.",
                            self.identity.productName
                        )
                    alert.addButton(withTitle: localized("OK"))
                    self.prepareForModalPresentation()
                    alert.runModal()
                }
            }
        }
    }

    private func showFunctionGlobeUnavailableWarning(issue: ModifierShortcutIssue) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.prepareForModalPresentation()
            let alert = NSAlert()
            alert.messageText = localized("Fn/Globe switching was turned off.")
            alert.informativeText = self.message(for: issue)
            alert.addButton(withTitle: localized("Open Keyboard Settings"))
            alert.addButton(withTitle: localized("Later"))
            if alert.runModal() == .alertFirstButtonReturn {
                self.appController.openFunctionGlobeSettings()
            }
        }
    }

    private func showKeyboardShortcutConflictWarning(issue: ModifierShortcutIssue) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.prepareForModalPresentation()
            let alert = NSAlert()
            alert.messageText = localized("Command switching was turned off.")
            alert.informativeText = self.message(for: issue)
            alert.addButton(withTitle: localized("OK"))
            alert.runModal()
        }
    }

    private func promptForLaunchAtLoginIfNeeded() {
        guard Self.isLaunchAtLoginAvailable else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.launchAtLoginPromptShownKey) else { return }
        if Self.isLaunchAtLoginEnabled {
            defaults.set(true, forKey: Self.launchAtLoginPromptShownKey)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.prepareForModalPresentation()
            let alert = NSAlert()
            alert.messageText = localizedFormat(
                "Start %@ at login?",
                self.identity.productName
            )
            alert.informativeText = localizedFormat(
                "%@ can start automatically when you sign in, so keyboard switching is available right away.",
                self.identity.productName
            )
            alert.addButton(withTitle: localized("Start at Login"))
            alert.addButton(withTitle: localized("Not Now"))
            defaults.set(true, forKey: Self.launchAtLoginPromptShownKey)
            if alert.runModal() == .alertFirstButtonReturn {
                self.setLaunchAtLoginEnabled(true)
            }
        }
    }

    private static var isLaunchAtLoginAvailable: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    private static var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    private func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard Self.isLaunchAtLoginAvailable else { return }
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.mainApp
                if enabled {
                    if service.status != .enabled && service.status != .requiresApproval {
                        try service.register()
                    }
                    if service.status == .requiresApproval {
                        showLaunchAtLoginApproval()
                    }
                } else if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                }
            } catch {
                showLaunchAtLoginError(error)
            }
        }
    }

    @available(macOS 13.0, *)
    private func showLaunchAtLoginApproval() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.prepareForModalPresentation()
            let alert = NSAlert()
            alert.messageText = localizedFormat(
                "Allow %@ to start at login",
                self.identity.productName
            )
            alert.informativeText = localizedFormat(
                "macOS needs your approval. Open Login Items in System Settings and enable %@.",
                self.identity.productName
            )
            alert.addButton(withTitle: localized("Open Login Items Settings"))
            alert.addButton(withTitle: localized("Later"))
            if alert.runModal() == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }

    private func showLaunchAtLoginError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.prepareForModalPresentation()
            let alert = NSAlert()
            alert.messageText = localized("Could not update Open at Login.")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: localized("OK"))
            alert.runModal()
        }
    }

    private func prepareForModalPresentation() {
        statusMenuController?.dismissPanel()
        NSApp.activate(ignoringOtherApps: true)
    }

    private var inputMonitoringSettingsPath: String {
        if #available(macOS 13.0, *) {
            return localized("System Settings > Privacy & Security > Input Monitoring")
        }
        return localized("System Preferences > Security & Privacy > Privacy > Input Monitoring")
    }

    private var inputMonitoringSettingsButtonTitle: String {
        if #available(macOS 13.0, *) {
            return localized("Open System Settings")
        }
        return localized("Open System Preferences")
    }

    private var accessibilitySettingsPath: String {
        if #available(macOS 13.0, *) {
            return localized("System Settings > Privacy & Security > Accessibility")
        }
        return localized("System Preferences > Security & Privacy > Privacy > Accessibility")
    }

    private func message(for issue: ModifierShortcutIssue) -> String {
        switch issue {
        case let .functionGlobe(functionIssue):
            switch functionIssue {
            case .cannotReadSystemSetting:
                return localizedFormat(
                    "The app could not read the current Fn/Globe system setting. In %@, set the Fn/Globe key action to Do Nothing, then enable Fn/Globe in the app again.",
                    keyboardSettingsPath
                )
            case .systemActionEnabled:
                return localizedFormat(
                    "macOS is using the Fn/Globe key for a system action. In %@, set the Fn/Globe key action to Do Nothing, then enable Fn/Globe in the app again.",
                    keyboardSettingsPath
                )
            }
        case .commandShortcutConflict:
            return localized("Command switching conflicts with a text action that uses Command alone. Clear or change that text shortcut first.")
        }
    }

    private var keyboardSettingsPath: String {
        if #available(macOS 13.0, *) {
            return localized("System Settings > Keyboard")
        }
        return localized("System Preferences > Keyboard")
    }
}
