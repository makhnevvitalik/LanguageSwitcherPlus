// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import CoreServices
import LanguageSwitcherLocalization

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let languageStore = AppLanguageStore()
    private lazy var applicationCoordinator = ApplicationCoordinator(
        identity: AppCompositionRoot.identity,
        appController: AppCompositionRoot.makeAppController(),
        languageStore: languageStore
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = launchEvent?.eventID == kAEOpenApplication
            && launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
                == keyAELaunchedAsLogInItem
        AppLocalization.configure(language: languageStore.selectedLanguage)
        applicationCoordinator.start(inBackground: launchedAtLogin)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        applicationCoordinator.showSettings()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applicationCoordinator.applicationDidBecomeActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        applicationCoordinator.stop()
    }
}
