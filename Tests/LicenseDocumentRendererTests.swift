// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit

@main struct LicenseDocumentRendererTests {
    @MainActor static func main() {
        do { try run() }
        catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    @MainActor private static func run() throws {
        let renderer = LicenseDocumentRenderer.self
        let plain = renderer.render("MIT License\n\nIN NO EVENT SHALL THE\nAUTHORS BE LIABLE.\n", format:.plainText)
        try expect(plain.string == "MIT License\nIN NO EVENT SHALL THE AUTHORS BE LIABLE.", "Hard wrapping in the MIT disclaimer must become one paragraph")

        let nested = renderer.render("Title\n\nA CC-\nlicensed work.\n\nSection 2 -- Scope.\n\n  a. First item\n     continues here.\n\n       1. Nested item\n          continues.\n\n  b. Second item.", format:.plainText)
        try expect(nested.string == "Title\nA CC-licensed work.\nSection 2 -- Scope.\na. First item continues here.\n1. Nested item continues.\nb. Second item.", "Paragraphs, nested numbering and compound words must survive reflow")
        let n = nested.string as NSString
        let outer = nested.attribute(.paragraphStyle,at:n.range(of:"a. First").location,effectiveRange:nil) as? NSParagraphStyle
        let inner = nested.attribute(.paragraphStyle,at:n.range(of:"1. Nested").location,effectiveRange:nil) as? NSParagraphStyle
        try expect(outer != nil && inner != nil && inner!.firstLineHeadIndent > outer!.firstLineHeadIndent, "Nested CC clauses must retain their nesting")
        try expect(inner!.headIndent > inner!.firstLineHeadIndent,"Wrapped list text must align after its marker")

        let prose = renderer.render("Title\n\nCreative Commons is not a party to public\nlicenses. Notwithstanding, it may publish works.",format:.plainText)
        try expect(prose.string == "Title\nCreative Commons is not a party to public licenses. Notwithstanding, it may publish works.","A word ending with a period is not an alphabetic list marker")

        let crossReference = renderer.render("Title\n\n  b. Terminated under\n     Section 6(a), it reinstates:\n\n       1. Automatically.",format:.plainText)
        try expect(crossReference.string == "Title\nb. Terminated under Section 6(a), it reinstates:\n1. Automatically.","A wrapped reference to a section must not become a new heading")

        let md = renderer.render("<!-- SPDX metadata\nnot reader content -->\n# Notices\n\nParagraph with `LICENSE` wrapped\nacross lines.\n\n- First bullet\n  https://example.test/source\n- Second bullet\n  continues.\n",format:.markdown)
        try expect(md.string == "Notices\nParagraph with LICENSE wrapped across lines.\n- First bullet https://example.test/source\n- Second bullet continues.","Markdown comments and markup must be hidden without merging adjacent list items")
        let linkRange = (md.string as NSString).range(of:"https://example.test/source")
        let link = md.attribute(.link,at:linkRange.location,effectiveRange:nil) as? URL
        try expect(link?.absoluteString == "https://example.test/source", "Displayed source links must be clickable")

        let separated = renderer.render("Title\n\n=======\n\nBody text.\n\n=======\n\nFinal paragraph.",format:.plainText)
        try expect(separated.string == "Title\nBody text.\nFinal paragraph.","Decorative CC separator rows must not wrap or merge neighboring paragraphs")
        try expect(renderer.render("\n \n",format:.plainText).string.isEmpty,"Empty resources must render empty")

        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        for (name,format) in [("LICENSE",LicenseDocumentRenderer.Format.plainText),("THIRD_PARTY_NOTICES.md",.markdown),("Packages/LanguageSwitcherKit/Sources/LanguageSwitcherLexicon/Resources/ATTRIBUTION.md",.markdown),("Packages/LanguageSwitcherKit/Sources/LanguageSwitcherLexicon/Resources/LICENSE-CC-BY-SA-4.0.txt",.plainText)] {
            let source = try String(contentsOf:root.appendingPathComponent(name),encoding:.utf8)
            let rendered = renderer.render(source,format:format)
            // Independently compare every non-layout character. Formatting markers and
            // SPDX comments are excluded only in Markdown, decorative '=' rows only in text.
            var expected = source
            if format == .markdown {
                expected = expected.replacingOccurrences(of:"(?s)<!--.*?-->",with:"",options:.regularExpression)
                    .replacingOccurrences(of:"(?m)^#{1,6} +",with:"",options:.regularExpression)
                    .replacingOccurrences(of:"`",with:"")
            } else {
                expected = expected.replacingOccurrences(of:"(?m)^=+\\s*$",with:"",options:.regularExpression)
            }
            let canonical: (String)->String = { $0.components(separatedBy:.whitespacesAndNewlines).joined() }
            try expect(canonical(rendered.string) == canonical(expected),"Document words, numbering, punctuation or URLs lost: " + name)
            if format == .plainText {
                let paragraphs = source.components(separatedBy:"\n\n")
                    .map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.allSatisfy { $0 == "=" } }
                try expect(rendered.string.components(separatedBy:"\n").count == paragraphs.count,"Plain-text paragraph boundaries changed: " + name)
            }
            try expect(!rendered.string.contains("<!--") && !rendered.string.contains("======"),"Reader-visible markup: " + name)
            print("PASS: complete document preserved and reflowed: " + name)
        }
        print("PASS: MIT wrapping, CC hierarchy/hyphenation, Markdown lists/comments, clickable links and all four document bodies")
    }
    static func expect(_ condition:Bool,_ message:String) throws {
        if !condition { throw NSError(domain:message,code:1) }
    }
}
