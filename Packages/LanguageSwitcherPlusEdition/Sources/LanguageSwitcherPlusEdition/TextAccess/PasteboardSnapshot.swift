// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit

struct PasteboardSnapshot {
    private struct Item {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    private let items: [Item]

    var debugSummary: String {
        let values = items.flatMap(\.values).map {
            "\($0.type.rawValue):\($0.data.count)B"
        }
        return "items=\(items.count) values=[\(values.joined(separator: ","))]"
    }

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Item(values: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        return PasteboardSnapshot(items: items)
    }

    @discardableResult
    func restore(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        guard !items.isEmpty else {
            return true
        }

        let pasteboardItems = items.compactMap { item -> NSPasteboardItem? in
            guard !item.values.isEmpty else {
                return nil
            }
            let pasteboardItem = NSPasteboardItem()
            for value in item.values {
                pasteboardItem.setData(value.data, forType: value.type)
            }
            return pasteboardItem
        }
        guard pasteboardItems.count == items.count else {
            return false
        }
        return pasteboard.writeObjects(pasteboardItems)
    }
}
