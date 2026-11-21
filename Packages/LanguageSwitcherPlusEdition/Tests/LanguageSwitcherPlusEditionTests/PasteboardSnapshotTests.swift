// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
@testable import LanguageSwitcherPlusEdition
import XCTest

final class PasteboardSnapshotTests: XCTestCase {
    func testRestoresEveryItemAndAvailableType() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let customType = NSPasteboard.PasteboardType("com.languageswitcher.tests.custom")
        let first = NSPasteboardItem()
        first.setString("hello", forType: .string)
        first.setData(Data([1, 2, 3]), forType: customType)
        let second = NSPasteboardItem()
        second.setString("world", forType: .string)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([first, second]))
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("replacement", forType: .string)
        XCTAssertTrue(snapshot.restore(to: pasteboard))

        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
        XCTAssertEqual(pasteboard.pasteboardItems?[0].string(forType: .string), "hello")
        XCTAssertEqual(pasteboard.pasteboardItems?[0].data(forType: customType), Data([1, 2, 3]))
        XCTAssertEqual(pasteboard.pasteboardItems?[1].string(forType: .string), "world")
    }

    func testRestoresEmptyPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.setString("temporary", forType: .string)
        XCTAssertTrue(snapshot.restore(to: pasteboard))

        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true)
    }
}
