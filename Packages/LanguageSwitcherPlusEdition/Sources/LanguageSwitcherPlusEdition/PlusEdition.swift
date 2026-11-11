// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation
import LanguageSwitcherEdition

public enum PlusEdition {
    public static let identity = AppIdentity(
        brandName: "Language Switcher",
        editionName: "Plus",
        productName: "Language Switcher Plus",
        repositoryURL: URL(
            string: "https://github.com/makhnevvitalik/LanguageSwitcherPlus"
        )!,
        latestReleaseURL: URL(
            string: "https://github.com/makhnevvitalik/"
                + "LanguageSwitcherPlus/releases/latest"
        )!,
        latestReleaseAPIURL: URL(
            string: "https://api.github.com/repos/"
                + "makhnevvitalik/LanguageSwitcherPlus/releases/latest"
        )!
    )
}
