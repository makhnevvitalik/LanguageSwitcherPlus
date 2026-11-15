// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit

@MainActor
final class ModelessAlertPresenter<Key: Hashable> {
    private var windows: [Key: ModelessAlert] = [:]

    @discardableResult
    func raise(_ key: Key) -> Bool {
        guard let window = windows[key] else { return false }
        window.bringToFront()
        return true
    }

    func show(_ key: Key, alert: NSAlert, onResponse: @escaping (Bool) -> Void = { _ in }) {
        guard !raise(key) else { return }
        let window = ModelessAlert(alert: alert) { [weak self] accepted in
            self?.windows.removeValue(forKey: key)
            onResponse(accepted)
        }
        windows[key] = window
        window.bringToFront()
    }

    func dismiss(_ key: Key) {
        windows.removeValue(forKey: key)?.dismiss()
    }
}

@MainActor
private final class ModelessAlert: NSObject, NSWindowDelegate {
    private let alert: NSAlert
    private var response: ((Bool) -> Void)?

    init(alert: NSAlert, response: @escaping (Bool) -> Void) {
        self.alert = alert
        self.response = response
        super.init()

        alert.layout()
        for button in alert.buttons {
            button.target = self
            button.action = #selector(selectButton(_:))
        }
        if alert.buttons.count == 2 { alert.buttons.last?.keyEquivalent = "\u{1b}" }
        let window = alert.window
        window.delegate = self
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.center()
    }

    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        response = nil
        alert.window.close()
    }

    func windowWillClose(_ notification: Notification) {
        let response = self.response
        self.response = nil
        response?(false)
    }

    @objc private func selectButton(_ sender: NSButton) {
        let response = self.response
        dismiss()
        response?(sender === alert.buttons.first)
    }
}
