// swift-tools-version: 5.9
// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import PackageDescription

let package = Package(
    name: "LanguageSwitcherKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LanguageSwitcherDomain", targets: ["LanguageSwitcherDomain"]),
        .library(name: "LanguageSwitcherEdition", targets: ["LanguageSwitcherEdition"]),
        .library(name: "LanguageSwitcherApplication", targets: ["LanguageSwitcherApplication"]),
        .library(name: "LanguageSwitcherLocalization", targets: ["LanguageSwitcherLocalization"]),
        .library(name: "LanguageSwitcherLexicon", targets: ["LanguageSwitcherLexicon"]),
        .library(name: "LanguageSwitcherMacOS", targets: ["LanguageSwitcherMacOS"])
    ],
    targets: [
        .target(name: "LanguageSwitcherDomain"),
        .target(name: "LanguageSwitcherEdition"),
        .target(
            name: "LanguageSwitcherApplication",
            dependencies: ["LanguageSwitcherDomain"]
        ),
        .target(
            name: "LanguageSwitcherLocalization",
            resources: [.process("Resources")]
        ),
        .target(
            name: "LanguageSwitcherMacOS",
            dependencies: ["LanguageSwitcherApplication", "LanguageSwitcherDomain"]
        ),
        .target(
            name: "LanguageSwitcherLexicon",
            dependencies: ["LanguageSwitcherApplication"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LanguageSwitcherDomainTests",
            dependencies: ["LanguageSwitcherDomain"]
        ),
        .testTarget(
            name: "LanguageSwitcherApplicationTests",
            dependencies: ["LanguageSwitcherApplication", "LanguageSwitcherDomain"]
        ),
        .testTarget(
            name: "LanguageSwitcherLocalizationTests",
            dependencies: ["LanguageSwitcherLocalization"]
        ),
        .testTarget(
            name: "LanguageSwitcherMacOSTests",
            dependencies: ["LanguageSwitcherMacOS", "LanguageSwitcherApplication", "LanguageSwitcherDomain"]
        ),
        .testTarget(
            name: "LanguageSwitcherLexiconTests",
            dependencies: ["LanguageSwitcherLexicon"],
            resources: [.copy("Fixtures")]
        )
    ]
)
