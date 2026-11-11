// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

public struct KeyboardLayoutPair: Equatable, Sendable {
    public let source: String
    public let target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

public struct KeyboardLayoutMap: Equatable, Sendable {
    private let replacements: [Character: String]

    public init(pairTiers: [[KeyboardLayoutPair]]) {
        var result: [Character: String] = [:]
        var higherPrioritySources: Set<Character> = []
        for tier in pairTiers {
            let tierReplacements = Self.makeReplacements(from: tier)
            for (source, target) in tierReplacements
                where !higherPrioritySources.contains(source) {
                result[source] = target
            }
            higherPrioritySources.formUnion(tier.compactMap(Self.validSource))
        }
        replacements = result
    }

    private static func makeReplacements(
        from pairs: [KeyboardLayoutPair]
    ) -> [Character: String] {
        var replacements: [Character: String] = [:]
        var ambiguousSources: Set<Character> = []

        for pair in pairs {
            guard let source = validSource(pair),
                  !ambiguousSources.contains(source) else {
                continue
            }

            if let existing = replacements[source], existing != pair.target {
                replacements.removeValue(forKey: source)
                ambiguousSources.insert(source)
            } else {
                replacements[source] = pair.target
            }
        }

        return replacements
    }

    private static func validSource(_ pair: KeyboardLayoutPair) -> Character? {
        guard pair.source.count == 1,
              let source = pair.source.first,
              !pair.target.isEmpty else {
            return nil
        }
        return source
    }

    public func replacement(for character: Character) -> String? {
        replacements[character]
    }

    public var isEmpty: Bool {
        replacements.isEmpty
    }
}
