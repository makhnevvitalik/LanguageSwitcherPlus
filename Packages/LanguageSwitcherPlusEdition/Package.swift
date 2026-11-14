// swift-tools-version: 5.9
// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import PackageDescription

let package = Package(
    name: "LanguageSwitcherPlusEdition",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LanguageSwitcherPlusEdition",
            targets: ["LanguageSwitcherPlusEdition"]
        )
    ],
    dependencies: [
        .package(path: "../LanguageSwitcherKit")
    ],
    targets: [
        .target(
            name: "LanguageSwitcherPlusEdition",
            dependencies: [
                .product(
                    name: "LanguageSwitcherEdition",
                    package: "LanguageSwitcherKit"
                )
            ]
        )
    ]
)
