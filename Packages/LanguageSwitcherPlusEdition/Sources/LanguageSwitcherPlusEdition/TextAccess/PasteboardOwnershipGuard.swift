// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

struct PasteboardOwnershipGuard {
    private var ownedChangeCount: Int?

    mutating func claim(changeCount: Int) {
        ownedChangeCount = changeCount
    }

    func owns(changeCount: Int) -> Bool {
        ownedChangeCount == changeCount
    }

    mutating func reset() {
        ownedChangeCount = nil
    }
}
