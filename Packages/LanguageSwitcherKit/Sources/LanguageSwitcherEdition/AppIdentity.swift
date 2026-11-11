// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation

public struct AppIdentity: Equatable, Sendable {
    public let brandName: String
    public let editionName: String
    public let productName: String
    public let repositoryURL: URL
    public let latestReleaseURL: URL
    public let latestReleaseAPIURL: URL

    public init(
        brandName: String,
        editionName: String,
        productName: String,
        repositoryURL: URL,
        latestReleaseURL: URL,
        latestReleaseAPIURL: URL
    ) {
        self.brandName = brandName
        self.editionName = editionName
        self.productName = productName
        self.repositoryURL = repositoryURL
        self.latestReleaseURL = latestReleaseURL
        self.latestReleaseAPIURL = latestReleaseAPIURL
    }
}
