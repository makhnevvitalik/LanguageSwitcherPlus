// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation
import LanguageSwitcherApplication
import LanguageSwitcherDomain
import LanguageSwitcherMacOS

@MainActor
final class AppController {
    private static let standaloneCommand = TextShortcutChord(modifiers: .command, functionKey: nil)

    private let inputSourceRepository: TISInputSourceRepository
    private let inputSourceSelectionStore: UserDefaultsInputSourceSelectionStore
    private let updateInputSourceSelection: UpdateInputSourceSelection
    private let switchInputSource: SwitchToNextInputSource
    private let keyboardPreferences: UserDefaultsKeyboardSwitchingPreferences
    private let modifierTapPreferences: UserDefaultsModifierTapPreferences
    private let textShortcutTimingPreferences: UserDefaultsTextShortcutTimingPreferences
    private let textScopeStore: UserDefaultsTextConversionScopeStore
    private let textShortcutStore: UserDefaultsTextActionShortcutStore
    private let configureTextShortcut: ConfigureTextActionShortcut
    private let performTextActionUseCase: PerformTextAction
    private let accessibilityPermission: AccessibilityPermissionController
    let inputMonitoringPermission: InputMonitoringPermissionController
    private let functionGlobeBehavior: LanguageSwitcherMacOS.FunctionGlobeSystemBehaviorController
    private let trackedTextBuffer: TrackedTextBuffer
    private let inputContextTracker: InputContextTracker
    private var keyboardMonitor: CGEventKeyboardMonitor?
    private(set) var isRecordingTextShortcut = false

    var onInputMonitoringUnavailable: (() -> Void)?
    var onInputMonitoringStateChanged: (() -> Void)?
    var onAccessibilityUnavailable: (() -> Void)?
    var onTextActionResult: ((PerformTextActionResult) -> Void)?

    init(
        inputSourceRepository: TISInputSourceRepository,
        inputSourceSelectionStore: UserDefaultsInputSourceSelectionStore,
        updateInputSourceSelection: UpdateInputSourceSelection,
        switchInputSource: SwitchToNextInputSource,
        keyboardPreferences: UserDefaultsKeyboardSwitchingPreferences,
        modifierTapPreferences: UserDefaultsModifierTapPreferences,
        textShortcutTimingPreferences: UserDefaultsTextShortcutTimingPreferences,
        textScopeStore: UserDefaultsTextConversionScopeStore,
        textShortcutStore: UserDefaultsTextActionShortcutStore,
        configureTextShortcut: ConfigureTextActionShortcut,
        performTextAction: PerformTextAction,
        accessibilityPermission: AccessibilityPermissionController,
        functionGlobeBehavior: LanguageSwitcherMacOS.FunctionGlobeSystemBehaviorController,
        trackedTextBuffer: TrackedTextBuffer,
        inputContextTracker: InputContextTracker,
        inputMonitoringPermission: InputMonitoringPermissionController
    ) {
        self.inputSourceRepository = inputSourceRepository
        self.inputSourceSelectionStore = inputSourceSelectionStore
        self.updateInputSourceSelection = updateInputSourceSelection
        self.switchInputSource = switchInputSource
        self.keyboardPreferences = keyboardPreferences
        self.modifierTapPreferences = modifierTapPreferences
        self.textShortcutTimingPreferences = textShortcutTimingPreferences
        self.textScopeStore = textScopeStore
        self.textShortcutStore = textShortcutStore
        self.configureTextShortcut = configureTextShortcut
        self.performTextActionUseCase = performTextAction
        self.accessibilityPermission = accessibilityPermission
        self.inputMonitoringPermission = inputMonitoringPermission
        self.functionGlobeBehavior = functionGlobeBehavior
        self.trackedTextBuffer = trackedTextBuffer
        self.inputContextTracker = inputContextTracker
    }

    var isInputMonitoringPaused: Bool {
        return monitoringIsRequired && !(keyboardMonitor?.isRunning ?? false)
    }

    var isKeyboardMonitoringRunning: Bool {
        keyboardMonitor?.isRunning ?? false
    }

    var textShortcutInterception: TextShortcutInterception {
        keyboardMonitor?.textShortcutInterception ?? .inactive
    }

    var availableInputSources: [InputSource] {
        inputSourceRepository.availableInputSources()
    }

    func isInputSourceSelected(_ inputSource: InputSource) -> Bool {
        InputSourceSelectionPolicy.isSelected(
            inputSource,
            excludedIDs: inputSourceSelectionStore.excludedInputSourceIDs
        )
    }

    @discardableResult
    func setInputSource(_ inputSource: InputSource, selected: Bool) -> InputSourceSelectionUpdateResult {
        updateInputSourceSelection.setSelected(selected, inputSourceID: inputSource.id)
    }

    var textConversionScope: TextConversionScope {
        get { textScopeStore.scope }
        set {
            textScopeStore.scope = newValue
            configureKeyboardMonitor()
        }
    }

    var isAccessibilityAllowed: Bool {
        accessibilityPermission.isAllowed
    }

    var isTextActionBusy: Bool {
        performTextActionUseCase.isBusy
    }

    func isTextActionAvailable(_ action: TextAction) -> Bool {
        performTextActionUseCase.isAvailable(action)
    }

    func openAccessibilitySettings() {
        _ = accessibilityPermission.openSettings()
    }

    func openFunctionGlobeSettings() {
        _ = functionGlobeBehavior.openKeyboardSettings()
    }

    func startKeyboardMonitoring() {
        configureKeyboardMonitor()
    }

    func stopKeyboardMonitoring() {
        keyboardMonitor?.stop()
        keyboardMonitor = nil
    }

    func setTextShortcutRecording(_ isRecording: Bool) {
        guard isRecordingTextShortcut != isRecording else { return }
        isRecordingTextShortcut = isRecording
        configureKeyboardMonitor()
    }

    @discardableResult
    func setModifierShortcut(
        _ shortcut: ModifierShortcut,
        enabled: Bool
    ) -> ModifierShortcutUpdateResult {
        if shortcut == .command,
           enabled,
           hasStandaloneCommandTextGesture {
            keyboardPreferences.setEnabled(false, for: shortcut)
            configureKeyboardMonitor()
            return .unavailable(.commandShortcutConflict)
        }
        if shortcut == .functionGlobe, enabled {
            switch functionGlobeBehavior.trackingAvailability() {
            case .available:
                break
            case let .unavailable(issue):
                keyboardPreferences.setEnabled(false, for: shortcut)
                configureKeyboardMonitor()
                return .unavailable(.functionGlobe(issue))
            }
        }

        keyboardPreferences.setEnabled(enabled, for: shortcut)
        configureKeyboardMonitor()
        return .available
    }

    func isModifierShortcutEnabled(_ shortcut: ModifierShortcut) -> Bool {
        keyboardPreferences.isEnabled(shortcut)
    }

    var maximumModifierTapDuration: TimeInterval {
        modifierTapPreferences.maximumDuration
    }

    var modifierTapDurationOptions: [TimeInterval] {
        UserDefaultsModifierTapPreferences.durationOptions
    }

    var defaultModifierTapDuration: TimeInterval {
        UserDefaultsModifierTapPreferences.defaultDuration
    }

    func setMaximumModifierTapDuration(_ duration: TimeInterval) {
        modifierTapPreferences.maximumDuration = duration
        configureKeyboardMonitor()
    }

    var maximumTextShortcutMultiPressInterval: TimeInterval {
        textShortcutTimingPreferences.maximumMultiPressInterval
    }

    var textShortcutMultiPressIntervalOptions: [TimeInterval] {
        UserDefaultsTextShortcutTimingPreferences.intervalOptions
    }

    var defaultTextShortcutMultiPressInterval: TimeInterval {
        UserDefaultsTextShortcutTimingPreferences.defaultInterval
    }

    func setMaximumTextShortcutMultiPressInterval(_ interval: TimeInterval) {
        textShortcutTimingPreferences.maximumMultiPressInterval = interval
        configureKeyboardMonitor()
    }

    func textShortcut(for action: TextAction) -> TextActionShortcut? {
        textShortcutStore.shortcut(for: action)
    }

    var hasConfiguredTextShortcuts: Bool {
        TextAction.allCases.contains {
            textShortcutStore.shortcut(for: $0) != nil
        }
    }

    func validateTextShortcut(
        _ shortcut: TextActionShortcut,
        for action: TextAction
    ) -> TextActionShortcutValidationResult {
        configureTextShortcut.validateShortcut(
            shortcut,
            for: action,
            reservedShortcuts: reservedTextShortcuts
        )
    }

    @discardableResult
    func setTextShortcut(
        _ shortcut: TextActionShortcut?,
        for action: TextAction,
        reviewedConflict: TextShortcutConflict?
    ) -> ConfigureTextActionShortcutResult {
        let result = configureTextShortcut.setShortcut(
            shortcut,
            for: action,
            reservedShortcuts: reservedTextShortcuts,
            reviewedConflict: reviewedConflict
        )
        if result == .updated {
            configureKeyboardMonitor()
        }
        return result
    }

    private var reservedTextShortcuts: [TextActionShortcut] {
        keyboardPreferences.isEnabled(.command)
            ? [.once(Self.standaloneCommand)]
            : []
    }

    func performTextAction(_ action: TextAction) {
        guard accessibilityPermission.isAllowed else {
            onAccessibilityUnavailable?()
            return
        }
        performTextActionUseCase.execute(action) { [weak self] result in
            self?.onTextActionResult?(result)
        }
    }

    func performMenuTextAction(_ action: TextAction) {
        guard accessibilityPermission.isAllowed else {
            onAccessibilityUnavailable?()
            return
        }
        performTextActionUseCase.execute(action, scope: .selectionOnly) { [weak self] result in
            self?.onTextActionResult?(result)
        }
    }

    private func configureKeyboardMonitor() {
        defer { onInputMonitoringStateChanged?() }
        stopKeyboardMonitoring()
        let features = activeMonitoringFeatures
        guard features.isMonitoringRequired else {
            return
        }
        let textShortcuts: [TextAction: TextActionShortcut] = features.contains(.textShortcuts)
            ? Dictionary(uniqueKeysWithValues: TextAction.allCases.compactMap { action in
                textShortcutStore.shortcut(for: action).map { (action, $0) }
            })
            : [:]
        let monitor = CGEventKeyboardMonitor(
            modifierShortcuts: features.contains(.keyboardSwitching)
                ? keyboardPreferences.enabledShortcuts
                : [],
            maximumModifierTapDuration: modifierTapPreferences.maximumDuration,
            maximumTextShortcutMultiPressInterval:
                textShortcutTimingPreferences.maximumMultiPressInterval,
            textShortcuts: textShortcuts,
            trackedTextBuffer: trackedTextBuffer,
            contextTracker: inputContextTracker,
            onModifierTrigger: { [weak self] in
                guard let self else { return }
                self.switchInputSource.execute { [weak self] result in
                    if case .switched = result {
                        self?.trackedTextBuffer.invalidate()
                    }
                }
            },
            onTextAction: { [weak self] action in
                self?.performTextAction(action)
            },
            onUnavailable: { [weak self] in
                self?.stopKeyboardMonitoring()
                self?.onInputMonitoringStateChanged?()
                self?.onInputMonitoringUnavailable?()
            },
            diagnostics: TextActionDebugJournal.handler(component: "monitor"),
            inputMonitoringPermission: inputMonitoringPermission,
            accessibilityPermission: accessibilityPermission,
            onInterceptionChanged: { [weak self] in self?.onInputMonitoringStateChanged?() }
        )
        keyboardMonitor = monitor
        guard monitor.start() else {
            stopKeyboardMonitoring()
            onInputMonitoringUnavailable?()
            return
        }
    }

    private var monitoringIsRequired: Bool {
        activeMonitoringFeatures.isMonitoringRequired
    }

    private var activeMonitoringFeatures: InputMonitoringFeatures {
        InputMonitoringRequirement.activeFeatures(
            hasKeyboardShortcuts: !keyboardPreferences.enabledShortcuts.isEmpty,
            hasTextShortcuts: hasConfiguredTextShortcuts,
            isRecordingTextShortcut: isRecordingTextShortcut
        )
    }

    private var hasStandaloneCommandTextGesture: Bool {
        TextAction.allCases.contains {
            textShortcutStore.shortcut(for: $0)?.classicChord == Self.standaloneCommand
        }
    }
}

enum ModifierShortcutUpdateResult: Equatable {
    case available
    case unavailable(ModifierShortcutIssue)
}

enum ModifierShortcutIssue: Equatable {
    case functionGlobe(FunctionGlobeTrackingIssue)
    case commandShortcutConflict
}
