// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit

public protocol FrontmostApplicationProviding: AnyObject {
    var applicationID: String? { get }
}

public final class FrontmostApplicationProvider: FrontmostApplicationProviding {
    public init() {}

    public var applicationID: String? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return application.bundleIdentifier ?? "pid:\(application.processIdentifier)"
    }
}
