// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation

enum TextActionDebugJournal {
#if INTERNAL_BUILD
    private static let writer = TextActionDebugJournalWriter()

    static func handler(component: String) -> ((String) -> Void)? {
        return { message in
            writer.append("\(component) \(message)")
        }
    }

    static func recordResult(_ result: String) {
        writer.append("action.result value=\(result)")
    }
#else
    static func handler(component: String) -> ((String) -> Void)? {
        return nil
    }
#endif
}

#if INTERNAL_BUILD
private final class TextActionDebugJournalWriter {
    private static let maximumFileSize: UInt64 = 20 * 1024 * 1024
    private static let maximumFileCount = 5
    private static let entryTruncationMarker = Data(
        "\n[journal] Entry truncated at the 20 MiB file limit.\n".utf8
    )

    // Keep temporary internal diagnostics away from the keyboard-event path.
    private let queue = DispatchQueue(
        label: "\(Bundle.main.bundleIdentifier ?? "LanguageSwitcher").text-action-journal",
        qos: .utility
    )
    private let timestampFormatter = ISO8601DateFormatter()
    private let fileURL: URL?
    private var fileHandle: FileHandle?

    init() {
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fileURL = nil
            return
        }

        let productName = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String ?? "LanguageSwitcher"
        let directory = applicationSupport
            .appendingPathComponent(productName, isDirectory: true)
            .appendingPathComponent("Debug", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            fileURL = directory.appendingPathComponent("text-actions.log")
        } catch {
            fileURL = nil
        }
    }

    deinit {
        try? fileHandle?.close()
    }

    func append(_ message: String) {
        let timestamp = Date()
        queue.async { [weak self] in
            guard let self,
                  let data = "\(timestampFormatter.string(from: timestamp)) \(message)\n"
                .data(using: .utf8) else {
                return
            }
            do {
                let data = Self.truncateOversizedEntry(data)
                try prepareFile()
                guard let fileHandle else {
                    return
                }
                let currentSize = try fileHandle.seekToEnd()
                if currentSize > 0,
                   currentSize + UInt64(data.count) > Self.maximumFileSize {
                    try rotateFiles()
                }
                try self.fileHandle?.seekToEnd()
                try self.fileHandle?.write(contentsOf: data)
            } catch {
                return
            }
        }
    }

    private func prepareFile() throws {
        guard fileHandle == nil, let fileURL else {
            return
        }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        fileHandle = try FileHandle(forUpdating: fileURL)
    }

    private func rotateFiles() throws {
        guard let fileURL else {
            return
        }

        try fileHandle?.close()
        fileHandle = nil

        let fileManager = FileManager.default
        for index in stride(
            from: Self.maximumFileCount - 1,
            through: 1,
            by: -1
        ) {
            let destinationURL = archiveURL(index: index, for: fileURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            let sourceURL = index == 1
                ? fileURL
                : archiveURL(index: index - 1, for: fileURL)
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            }
        }

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        fileHandle = try FileHandle(forUpdating: fileURL)
    }

    private func archiveURL(index: Int, for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(
            "\(fileURL.lastPathComponent).\(index)"
        )
    }

    private static func truncateOversizedEntry(_ data: Data) -> Data {
        guard UInt64(data.count) > maximumFileSize else {
            return data
        }

        let prefixSize = Int(maximumFileSize) - entryTruncationMarker.count - 4
        let prefix = String(decoding: data.prefix(prefixSize), as: UTF8.self)
        var result = Data(prefix.utf8)
        result.append(entryTruncationMarker)
        return result
    }
}
#endif
