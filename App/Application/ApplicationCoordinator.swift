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
    private lazy var updateChecker = GitHubReleaseChecker(
        apiURL: identity.latestReleaseAPIURL,
        releaseURL: identity.latestReleaseURL
    )
    private let inputMonitoringPermission = LanguageSwitcherMacOS.InputMonitoringPermissionController()
    private var statusMenuController: StatusMenuController?
    private var shortcutSettingsWindowController: TextShortcutSettingsWindowController?
    private enum Warning: Hashable {
        case inputMonitoring, accessibility, restartError, functionGlobe, commandConflict
        case launchAtLogin, launchAtLoginApproval, launchAtLoginError
    }

    private let warnings = ModelessAlertPresenter<Warning>()
    private var displayedInputMonitoringAction: InputMonitoringRecoveryAction?
    private var isRestarting = false
    private var isRecordingShortcut = false
    private var hasStarted = false
    private var isStartingInBackground = false
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

    func start(inBackground: Bool) {
        isStartingInBackground = inBackground
        defer { isStartingInBackground = false }
        configureMenu()
        appController.onInputMonitoringStateChanged = { [weak self] in
            guard let self else { return }
            self.statusMenuController?.refreshMonitoringState()
            if !self.appController.isInputMonitoringPaused {
                self.dismissInputMonitoringWarning()
            }
        }
        appController.onInputMonitoringUnavailable = { [weak self] in
            guard let self, !self.isStartingInBackground else { return }
            self.showInputMonitoringRecovery()
        }
        appController.onAccessibilityUnavailable = { [weak self] in
            self?.showAccessibilityRecovery()
        }
#if INTERNAL_BUILD
        appController.onTextActionResult = { result in
            TextActionDebugJournal.recordResult(String(describing: result))
        }
#endif

        validateFunctionGlobeSetting()
        startKeyboardMonitoringIfNeeded()
        hasStarted = true
        checkForUpdates()
        guard !inBackground else { return }

        showSettings()
        promptForLaunchAtLoginIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.continuePendingTextShortcutPermissionSetup()
        }
    }

    func showSettings() {
        guard !isRestarting, NSApp.modalWindow == nil else { return }
        statusMenuController?.showSettings()
    }

    func applicationDidBecomeActive() {
        guard hasStarted,
              !isStartingInBackground,
              !isRestarting,
              !isRecordingShortcut else {
            return
        }
        startKeyboardMonitoringIfNeeded()
        if appController.isAccessibilityAllowed { warnings.dismiss(.accessibility) }
        if SMAppService.mainApp.status != .requiresApproval { warnings.dismiss(.launchAtLoginApproval) }
        continuePendingTextShortcutPermissionSetup()
    }

    func stop() {
        appController.stopKeyboardMonitoring()
    }

    private func checkForUpdates(completion: ((ReleaseUpdateResult) -> Void)? = nil) {
        updateChecker.check(joinInProgress: true) { [weak self] result in
            switch result {
            case let .updateAvailable(_, url):
                self?.statusMenuController?.setAvailableReleaseURL(url)
            case .upToDate:
                self?.statusMenuController?.setAvailableReleaseURL(nil)
            case .failure:
                break
            }
            completion?(result)
        }
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
        let keyboardSwitching = KeyboardSwitchingMenuController(
            activeInputsController: activeInputs,
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
                } else if enabled {
                    self.warnings.dismiss(shortcut == .functionGlobe ? .functionGlobe : .commandConflict)
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
            aboutWindowController: AboutWindowController(identity: identity) { [weak self] completion in
                self?.checkForUpdates(completion: completion)
            },
            currentState: { [weak self, weak appController] in
                let isRecordingShortcut = self?.isRecordingShortcut ?? false
                return StatusMenuState(
                    isInputMonitoringPaused: !isRecordingShortcut
                        && (appController?.isInputMonitoringPaused ?? false),
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
        if case let .unavailable(issue) = result, !isStartingInBackground {
            showFunctionGlobeUnavailableWarning(issue: issue)
        }
    }

    private func resumeKeyboardSwitching() {
        startKeyboardMonitoringIfNeeded()
        if appController.isInputMonitoringPaused {
            showInputMonitoringRecovery(userInitiated: true)
        } else {
            continuePendingTextShortcutPermissionSetup()
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

    private var inputMonitoringRecoveryAction: InputMonitoringRecoveryAction {
        InputMonitoringRecoveryAction(
            accessAllowed: inputMonitoringPermission.isAllowed,
            hasRequestedAccess: hasRequestedInputMonitoring
        )
    }

    private func dismissInputMonitoringWarning() {
        displayedInputMonitoringAction = nil
        warnings.dismiss(.inputMonitoring)
    }

    private func showInputMonitoringRecovery(userInitiated: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isRestarting, !self.isRecordingShortcut,
                  self.appController.isInputMonitoringPaused else { return }

            let action = self.inputMonitoringRecoveryAction
            let wasOpen = self.displayedInputMonitoringAction != nil
            if action == self.displayedInputMonitoringAction {
                if userInitiated { self.warnings.raise(.inputMonitoring) }
                return
            }
            guard userInitiated || wasOpen || action != .openSettings else { return }
            self.dismissInputMonitoringWarning()

            let setupWasPending = self.isTextShortcutPermissionSetupPending
            let alert = self.makeInputMonitoringAlert(action: action, setupWasPending: setupWasPending)
            self.displayedInputMonitoringAction = action
            self.showWarning(.inputMonitoring, alert: alert) { [weak self] accepted in
                guard let self else { return }
                self.displayedInputMonitoringAction = nil
                guard self.appController.isInputMonitoringPaused else { return }
                if accepted {
                    self.performInputMonitoringRecovery(action)
                } else if setupWasPending && self.isTextShortcutPermissionSetupPending {
                    self.cancelPendingTextShortcutPermissionSetup()
                }
            }
        }
    }

    private func makeInputMonitoringAlert(action: InputMonitoringRecoveryAction, setupWasPending: Bool) -> NSAlert {
        let alert = NSAlert()
        if setupWasPending {
            alert.messageText = localized("Step 1 of 2: Allow Input Monitoring")
            alert.informativeText = localizedFormat(
                "%1$@ needs Input Monitoring to detect your global text shortcut. The shortcut is saved. Allow %1$@ in %2$@. If macOS asks, choose Quit & Reopen; the app will reopen and continue with Accessibility.",
                identity.productName,
                inputMonitoringSettingsPath
            )
        } else {
            alert.messageText = localized("Input Monitoring is unavailable.")
            alert.informativeText = localizedFormat(
                "Allow %1$@ in %2$@, then return to the app. If macOS asks, choose Quit & Reopen.",
                identity.productName,
                inputMonitoringSettingsPath
            )
        }
        let title: String
        switch action {
        case .requestAccess: title = localized("Grant Access")
        case .openSettings: title = localized("Open System Settings")
        case .restart: title = localizedFormat("Restart %@", identity.productName)
        }
        alert.addButton(withTitle: title)
        alert.addButton(withTitle: localized("Later"))
        return alert
    }

    private func performInputMonitoringRecovery(_ action: InputMonitoringRecoveryAction) {
        guard !isRestarting else { return }
        guard action == inputMonitoringRecoveryAction else {
            resumeKeyboardSwitching()
            return
        }
        switch action {
        case .requestAccess:
            hasRequestedInputMonitoring = true
            if inputMonitoringPermission.requestAccess() { resumeKeyboardSwitching() }
        case .openSettings:
            _ = inputMonitoringPermission.openSettings()
        case .restart:
            restartApplication()
        }
    }

    private func showAccessibilityRecovery() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isRestarting, !self.appController.isAccessibilityAllowed else { return }

            let setupWasPending = self.isTextShortcutPermissionSetupPending
            let alert = NSAlert()
            alert.messageText = setupWasPending
                ? localized("Step 2 of 2: Allow Accessibility")
                : localized("Accessibility access is required.")
            let nextAction = setupWasPending
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

            self.showWarning(.accessibility, alert: alert) { [weak self] accepted in
                guard let self else { return }
                if accepted {
                    if !self.appController.isAccessibilityAllowed {
                        self.appController.openAccessibilitySettings()
                    }
                } else if setupWasPending && self.isTextShortcutPermissionSetupPending {
                    self.cancelPendingTextShortcutPermissionSetup()
                }
            }
        }
    }

    private func continuePendingTextShortcutPermissionSetup() {
        guard isTextShortcutPermissionSetupPending,
              !isRecordingShortcut,
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
            guard appController.isKeyboardMonitoringRunning,
                  !hasPresentedPendingAccessibilityGuidance else { return }
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
        dismissInputMonitoringWarning()
        warnings.dismiss(.restartError)
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
                    self.showWarning(.restartError, alert: alert)
                }
            }
        }
    }

    private func showFunctionGlobeUnavailableWarning(issue: ModifierShortcutIssue) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = localized("Fn/Globe switching was turned off.")
            alert.informativeText = self.message(for: issue)
            alert.addButton(withTitle: localized("Open Keyboard Settings"))
            alert.addButton(withTitle: localized("Later"))
            self.showWarning(.functionGlobe, alert: alert) { [weak self] accepted in
                if accepted { self?.appController.openFunctionGlobeSettings() }
            }
        }
    }

    private func showKeyboardShortcutConflictWarning(issue: ModifierShortcutIssue) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = localized("Command switching was turned off.")
            alert.informativeText = self.message(for: issue)
            alert.addButton(withTitle: localized("OK"))
            self.showWarning(.commandConflict, alert: alert)
        }
    }

    private func promptForLaunchAtLoginIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.launchAtLoginPromptShownKey) else { return }
        if Self.isLaunchAtLoginEnabled {
            defaults.set(true, forKey: Self.launchAtLoginPromptShownKey)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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
            self.showWarning(.launchAtLogin, alert: alert) { [weak self] accepted in
                if accepted { self?.setLaunchAtLoginEnabled(true) }
            }
        }
    }

    private static var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLoginEnabled(_ enabled: Bool) {
        warnings.dismiss(.launchAtLogin)
        warnings.dismiss(.launchAtLoginError)
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
                warnings.dismiss(.launchAtLoginApproval)
            }
        } catch {
            showLaunchAtLoginError(error)
        }
    }

    private func showLaunchAtLoginApproval() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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
            self.showWarning(.launchAtLoginApproval, alert: alert) { accepted in
                if accepted, SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        }
    }

    private func showLaunchAtLoginError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = localized("Could not update Open at Login.")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: localized("OK"))
            self.showWarning(.launchAtLoginError, alert: alert)
        }
    }

    private func showWarning(
        _ warning: Warning,
        alert: NSAlert,
        onResponse: @escaping (Bool) -> Void = { _ in }
    ) {
        statusMenuController?.dismissPanel()
        warnings.show(warning, alert: alert, onResponse: onResponse)
    }

    private var inputMonitoringSettingsPath: String {
        localized("System Settings > Privacy & Security > Input Monitoring")
    }

    private var accessibilitySettingsPath: String {
        localized("System Settings > Privacy & Security > Accessibility")
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
        localized("System Settings > Keyboard")
    }
}
