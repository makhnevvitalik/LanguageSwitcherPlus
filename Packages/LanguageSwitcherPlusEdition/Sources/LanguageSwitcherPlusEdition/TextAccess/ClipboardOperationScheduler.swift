// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation

protocol ClipboardOperationScheduling: AnyObject {
    var now: TimeInterval { get }
    func schedule(after delay: TimeInterval, operation: @escaping () -> Void)
}

final class ClipboardOperationScheduler: ClipboardOperationScheduling {
    var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func schedule(after delay: TimeInterval, operation: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: operation)
    }
}
