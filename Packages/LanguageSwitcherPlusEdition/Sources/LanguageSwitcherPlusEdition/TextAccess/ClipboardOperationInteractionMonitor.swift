// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import LanguageSwitcherMacOS

protocol ClipboardOperationInteractionMonitoring: AnyObject {
    func start(onInteraction: @escaping () -> Void)
    func stop()
}

final class ClipboardOperationInteractionMonitor: ClipboardOperationInteractionMonitoring {
    private var monitor: Any?

    func start(onInteraction: @escaping () -> Void) {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            guard event.cgEvent?.getIntegerValueField(.eventSourceUserData)
                != KeyboardCommandEventMarker.value else {
                return
            }
            if Thread.isMainThread {
                onInteraction()
            } else {
                DispatchQueue.main.async(execute: onInteraction)
            }
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    deinit {
        stop()
    }
}
