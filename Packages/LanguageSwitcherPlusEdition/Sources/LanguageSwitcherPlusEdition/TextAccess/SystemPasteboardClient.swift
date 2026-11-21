// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit

protocol PasteboardClient: AnyObject {
    var changeCount: Int { get }
    func captureSnapshot() -> PasteboardSnapshot
    func readString() -> String?
    func restore(_ snapshot: PasteboardSnapshot) -> Bool
}

final class SystemPasteboardClient: PasteboardClient {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func captureSnapshot() -> PasteboardSnapshot {
        PasteboardSnapshot.capture(from: pasteboard)
    }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    func restore(_ snapshot: PasteboardSnapshot) -> Bool {
        snapshot.restore(to: pasteboard)
    }
}
