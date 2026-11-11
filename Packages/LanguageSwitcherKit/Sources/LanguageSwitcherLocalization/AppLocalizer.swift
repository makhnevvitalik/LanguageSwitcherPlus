// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation

public struct AppLocalizer: Sendable {
    public let language: AppLanguage
    private let localizedBundle: Bundle?

    public init(language: AppLanguage) {
        self.language = language
        localizedBundle = Bundle.module.url(
            forResource: language.rawValue,
            withExtension: "lproj"
        ).flatMap(Bundle.init(url:))
    }

    public func text(_ key: String) -> String {
        guard language != .fallback else { return key }
        return localizedBundle?.localizedString(
            forKey: key,
            value: key,
            table: nil
        ) ?? key
    }

    public func format(_ key: String, arguments: [CVarArg]) -> String {
        String(
            format: text(key),
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }
}
