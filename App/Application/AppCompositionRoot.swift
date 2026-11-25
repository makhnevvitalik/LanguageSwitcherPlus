// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation
import LanguageSwitcherApplication
import LanguageSwitcherDomain
import LanguageSwitcherLexicon
import LanguageSwitcherMacOS
import LanguageSwitcherPlusEdition

@MainActor
enum AppCompositionRoot {
    static let identity = PlusEdition.identity

    static func makeAppController() -> AppController {
        let inputSourceRepository = TISInputSourceRepository()
        let inputSourceSelectionStore = UserDefaultsInputSourceSelectionStore()
        let textScopeStore = UserDefaultsTextConversionScopeStore()
        let textShortcutStore = UserDefaultsTextActionShortcutStore()
        let accessibilityPermission = AccessibilityPermissionController()
        let keyboardLayoutProvider = TISKeyboardLayoutProvider()
        let frequencyProvider = BundledWordFrequencyProvider()
        let spellingChecker = NSSpellCheckerAdapter()
        let trackedTextBuffer = TrackedTextBuffer()
        let inputContextTracker = InputContextTracker()
        let selectedTextEditor = SelectedTextClipboardEditor(
            permissionController: accessibilityPermission,
            trackedTextBuffer: trackedTextBuffer,
            contextTracker: inputContextTracker,
            diagnostics: TextActionDebugJournal.handler(component: "selected")
        )
        let trackedTextEditor = TrackedTextEventEditor(
            permissionController: accessibilityPermission,
            buffer: trackedTextBuffer,
            contextTracker: inputContextTracker,
            diagnostics: TextActionDebugJournal.handler(component: "tracked")
        )
        prepareLanguageResources(
            inputSources: inputSourceRepository.availableInputSources(),
            frequencyProvider: frequencyProvider,
            spellingChecker: spellingChecker
        )
        let inputSourceActivator = VerifiedInputSourceActivator(
            repository: inputSourceRepository,
            diagnostics: TextActionDebugJournal.handler(component: "inputSource")
        )

        return AppController(
            inputSourceRepository: inputSourceRepository,
            inputSourceSelectionStore: inputSourceSelectionStore,
            updateInputSourceSelection: UpdateInputSourceSelection(
                repository: inputSourceRepository,
                selectionStore: inputSourceSelectionStore
            ),
            switchInputSource: SwitchToNextInputSource(
                repository: inputSourceRepository,
                selectionStore: inputSourceSelectionStore,
                activator: inputSourceActivator
            ),
            keyboardPreferences: UserDefaultsKeyboardSwitchingPreferences(),
            modifierTapPreferences: UserDefaultsModifierTapPreferences(),
            textShortcutTimingPreferences: UserDefaultsTextShortcutTimingPreferences(),
            textScopeStore: textScopeStore,
            textShortcutStore: textShortcutStore,
            configureTextShortcut: ConfigureTextActionShortcut(
                store: textShortcutStore,
                checkConflict: { TextShortcutConflictDetector.conflict(for: $0) }
            ),
            performTextAction: PerformTextAction(
                selectedTextReplacer: selectedTextEditor,
                trackedTextReplacer: trackedTextEditor,
                inputSourceRepository: inputSourceRepository,
                inputSourceSelectionStore: inputSourceSelectionStore,
                automaticLayoutConverter: LanguageAwareLayoutConverter(
                    keyboardLayoutProvider: keyboardLayoutProvider,
                    frequencyProvider: frequencyProvider,
                    spellingChecker: spellingChecker
                ),
                inputSourceActivator: inputSourceActivator,
                scopeStore: textScopeStore
            ),
            accessibilityPermission: accessibilityPermission,
            functionGlobeBehavior: LanguageSwitcherMacOS.FunctionGlobeSystemBehaviorController(),
            trackedTextBuffer: trackedTextBuffer,
            inputContextTracker: inputContextTracker,
            inputMonitoringPermission: InputMonitoringPermissionController()
        )
    }

    private static func prepareLanguageResources(
        inputSources: [InputSource],
        frequencyProvider: BundledWordFrequencyProvider,
        spellingChecker: NSSpellCheckerAdapter
    ) {
        let languageCodes = Set(inputSources.compactMap {
            LexiconLanguageResolver.languageCode(for: $0.localeIdentifier)
        }).filter(frequencyProvider.supports(languageCode:)).sorted()
        let startedAt = ProcessInfo.processInfo.systemUptime
        frequencyProvider.prepare(languageCodes: languageCodes)
        let frequencyPreparedAt = ProcessInfo.processInfo.systemUptime
        spellingChecker.prepare(languageCodes: languageCodes)
        let spellingPreparedAt = ProcessInfo.processInfo.systemUptime
        let frequencyMilliseconds = Int((frequencyPreparedAt - startedAt) * 1_000)
        let spellingMilliseconds = Int((spellingPreparedAt - frequencyPreparedAt) * 1_000)
        let elapsedMilliseconds = Int(
            (spellingPreparedAt - startedAt) * 1_000
        )
        TextActionDebugJournal.handler(component: "lexicon")?(
            "prepared languages=\(languageCodes.joined(separator: ",")) "
                + "frequencyMs=\(frequencyMilliseconds) "
                + "spellingMs=\(spellingMilliseconds) "
                + "elapsedMs=\(elapsedMilliseconds)"
        )
    }
}
