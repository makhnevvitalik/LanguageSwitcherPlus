// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit

/// Reader presentation for the bundled plain-text licenses and Markdown notices.
/// Reflows source-file wrapping without modifying the bundled legal documents.
@MainActor
enum LicenseDocumentRenderer {
    enum Format {
        case plainText
        case markdown
    }

    static func render(_ source: String, format: Format) -> NSAttributedString {
        let input = format == .markdown
            ? source.replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
            : source
        let output = NSMutableAttributedString(string: "")
        var paragraphText = ""
        var indentation: CGFloat = 0
        var marker: String?
        var isHeading = false

        func flushParagraph() {
            guard !paragraphText.isEmpty else { return }
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            style.paragraphSpacing = AppStyle.AboutLayout.contentSpacing
            style.firstLineHeadIndent = indentation
            style.headIndent = indentation
            if let marker {
                style.headIndent += (marker as NSString).size(withAttributes: [.font: AppStyle.Font.body]).width
            }
            let font = isHeading || output.length == 0
                ? AppStyle.Font.emphasizedBody : AppStyle.Font.body
            if output.length > 0 { output.append(NSAttributedString(string: "\n")) }
            output.append(NSAttributedString(string: paragraphText, attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style
            ]))
            paragraphText = ""
            indentation = 0
            marker = nil
            isHeading = false
        }

        for rawLine in input.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            // The fixed-width '=' separators in the CC text carry no legal wording.
            if line.isEmpty || (line.count >= 3 && line.allSatisfy({ $0 == "=" })) {
                flushParagraph()
                continue
            }

            let heading = format == .markdown
                ? line.range(of: "^#{1,6} +", options: .regularExpression)
                : nil
            if let heading { line.removeSubrange(heading) }
            if format == .markdown { line = line.replacingOccurrences(of: "`", with: "") }
            let listPrefix = line.range(
                of: format == .markdown ? "^- +" : "^(?:[a-z]|[ivx]+|[0-9]+)\\. +",
                options: .regularExpression
            ).map { String(line[$0]) }
            let plainHeading = format == .plainText && (
                line.range(of: "^Section [0-9]+ -- .+\\.$", options: .regularExpression) != nil ||
                ["License Scope", "MIT License", "\"Commons Clause\" License Condition v1.0",
                 "Using Creative Commons Public Licenses"].contains(line)
            )
            if heading != nil || plainHeading || listPrefix != nil { flushParagraph() }
            if paragraphText.isEmpty {
                // Keep the original CC nesting as paragraph indentation rather than
                // whitespace on every physical line. Continuations use a hanging indent.
                indentation = CGFloat(rawLine.prefix(while: { $0 == " " }).count) * 2.5
                marker = listPrefix
                isHeading = heading != nil || plainHeading
            } else if !paragraphText.hasSuffix("-") {
                paragraphText += " "
            }
            paragraphText += line
            if isHeading { flushParagraph() }
        }
        flushParagraph()

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(location: 0, length: output.length)
            for match in detector.matches(in: output.string, range: range) {
                if let url = match.url { output.addAttribute(.link, value: url, range: match.range) }
            }
        }
        return NSAttributedString(attributedString: output)
    }
}
