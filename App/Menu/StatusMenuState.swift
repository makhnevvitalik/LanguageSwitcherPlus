// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

struct StatusMenuState {
    let monitoringWarning: KeyboardMonitoringWarning?
    let isLaunchAtLoginEnabled: Bool
}

enum KeyboardMonitoringWarning: Equatable {
    case inputMonitoringPaused
    case textShortcutsNeedAccessibility
    case textShortcutInterceptionUnavailable

    @MainActor var title: String {
        switch self {
        case .inputMonitoringPaused:
            localized("Input Monitoring is paused")
        case .textShortcutsNeedAccessibility:
            localized("Letter and digit shortcuts need permission")
        case .textShortcutInterceptionUnavailable:
            localized("Letter and digit shortcuts are paused")
        }
    }

    @MainActor var buttonTitle: String {
        switch self {
        case .textShortcutsNeedAccessibility:
            localized("Open Accessibility")
        case .inputMonitoringPaused, .textShortcutInterceptionUnavailable:
            localized("Resume…")
        }
    }
}
