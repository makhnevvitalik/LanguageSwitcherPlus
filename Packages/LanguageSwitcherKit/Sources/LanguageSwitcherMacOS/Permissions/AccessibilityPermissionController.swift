// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import ApplicationServices

public protocol AccessibilityPermissionChecking: AnyObject {
    var isAllowed: Bool { get }
}

public final class AccessibilityPermissionController: AccessibilityPermissionChecking {
    private let checkAccess: () -> Bool
    private let openURL: (URL) -> Bool

    public convenience init() {
        self.init(
            isAllowed: { AXIsProcessTrusted() },
            openURL: { NSWorkspace.shared.open($0) }
        )
    }

    init(
        isAllowed: @escaping () -> Bool,
        openURL: @escaping (URL) -> Bool
    ) {
        checkAccess = isAllowed
        self.openURL = openURL
    }

    public var isAllowed: Bool {
        checkAccess()
    }

    @discardableResult
    public func openSettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return false
        }
        return openURL(url)
    }
}
