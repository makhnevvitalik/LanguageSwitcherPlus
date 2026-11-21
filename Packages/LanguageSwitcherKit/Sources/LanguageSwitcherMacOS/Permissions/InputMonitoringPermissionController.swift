// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import CoreGraphics

protocol InputMonitoringPermissionChecking: AnyObject {
    var isAllowed: Bool { get }
}

public final class InputMonitoringPermissionController: InputMonitoringPermissionChecking {
    public init() {}

    public var isAllowed: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    public func requestAccess() -> Bool {
        CGRequestListenEventAccess()
    }

    @discardableResult
    public func openSettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}
