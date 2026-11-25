// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Combine
import Foundation

protocol ReleaseRequestTask: AnyObject {
    func resume()
    func cancel()
}
extension URLSessionDataTask: ReleaseRequestTask {}

public enum ReleaseUpdateFailure: Equatable {
    case network, invalidResponse, invalidRelease, currentVersion, rateLimited
    case http(Int)
}

public struct AvailableRelease: Equatable {
    public let tag: String
    public let url: URL

    public init(tag: String, url: URL) {
        self.tag = tag
        self.url = url
    }
}

public enum ReleaseUpdateResult: Equatable {
    case upToDate
    case updateAvailable(AvailableRelease)
    case notPublished
    case failure(ReleaseUpdateFailure)
}

@MainActor
public final class GitHubReleaseChecker: ObservableObject {
    public enum State: Equatable {
        case idle, checking
        case finished(ReleaseUpdateResult)
    }
    typealias Completion = @Sendable (Data?, URLResponse?, Error?) -> Void
    typealias Transport = (URLRequest, @escaping Completion) -> ReleaseRequestTask

    public nonisolated static let automaticCheckInterval: Duration = .seconds(24 * 60 * 60)

    @Published public private(set) var state = State.idle
    @Published public private(set) var availableRelease: AvailableRelease?
    private let apiURL: URL
    private let releaseURL: URL
    private let userAgent: String
    private var automaticChecks: Task<Void, Never>?
    private let currentVersion: () -> String?
    private let transport: Transport
    private var task: ReleaseRequestTask?
    private var requestID: UUID?

    public convenience init(
        apiURL: URL, releaseURL: URL, userAgent: String,
        currentVersion: @escaping () -> String? = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        }
    ) {
        self.init(apiURL: apiURL, releaseURL: releaseURL, userAgent: userAgent,
                  currentVersion: currentVersion,
                  transport: { URLSession.shared.dataTask(with: $0, completionHandler: $1) })
    }

    init(apiURL: URL, releaseURL: URL, userAgent: String,
         currentVersion: @escaping () -> String?, transport: @escaping Transport) {
        self.apiURL = apiURL
        self.releaseURL = releaseURL
        self.userAgent = userAgent
        self.currentVersion = currentVersion
        self.transport = transport
    }

    public func startAutomaticChecks(interval: Duration = automaticCheckInterval) {
        guard automaticChecks == nil else { return }
        automaticChecks = Task { [weak self] in
            let clock = ContinuousClock()
            while !Task.isCancelled {
                do { try await clock.sleep(for: interval) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.check()
            }
        }
        check()
    }

    public func check() {
        guard state != .checking else { return }
        let id = UUID()
        requestID = id
        state = .checking
        let version = currentVersion()
        var request = URLRequest(url: apiURL,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        task = transport(request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.requestID == id else { return }
                self.requestID = nil
                self.task = nil
                let result = Self.evaluate(data: data, response: response, error: error,
                                           currentVersion: version, fallbackReleaseURL: self.releaseURL)
                let nextRelease: AvailableRelease?
                switch result {
                case let .updateAvailable(release): nextRelease = release
                case .upToDate, .notPublished: nextRelease = nil
                case .failure: nextRelease = self.availableRelease
                }
                if self.availableRelease != nextRelease { self.availableRelease = nextRelease }
                self.state = .finished(result)
            }
        }
        task?.resume()
    }

    public func cancel() {
        automaticChecks?.cancel()
        automaticChecks = nil
        requestID = nil
        task?.cancel()
        task = nil
        if state == .checking { state = .idle }
    }

    deinit {
        automaticChecks?.cancel()
        task?.cancel()
    }

    nonisolated static func evaluate(data: Data?, response: URLResponse?, error: Error?,
                                     currentVersion: String?, fallbackReleaseURL: URL) -> ReleaseUpdateResult {
        if error != nil { return .failure(.network) }
        guard let response = response as? HTTPURLResponse else { return .failure(.invalidResponse) }
        if response.statusCode == 404 { return .notPublished }
        if response.statusCode == 429 ||
            (response.statusCode == 403 &&
             (response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" ||
              response.value(forHTTPHeaderField: "Retry-After") != nil)) {
            return .failure(.rateLimited)
        }
        guard (200...299).contains(response.statusCode) else { return .failure(.http(response.statusCode)) }
        guard let data, data.count <= 1_048_576,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              release.prerelease != true, release.draft != true,
              let latest = AppVersion(release.tagName) else { return .failure(.invalidRelease) }
        guard let currentVersion, let current = AppVersion(currentVersion) else { return .failure(.currentVersion) }
        guard latest > current else { return .upToDate }
        let url = release.htmlURL.flatMap { trustedReleaseURL($0, fallbackReleaseURL: fallbackReleaseURL) }
            ?? fallbackReleaseURL
        return .updateAvailable(AvailableRelease(tag: release.tagName, url: url))
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String?
        let prerelease: Bool?
        let draft: Bool?
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", htmlURL = "html_url", prerelease, draft
        }
    }

    nonisolated private static func trustedReleaseURL(_ raw: String, fallbackReleaseURL: URL) -> URL? {
        let tagPath = fallbackReleaseURL.deletingLastPathComponent().path + "/tag/"
        guard let url = URL(string: raw), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host?.lowercased() == "github.com",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.hasPrefix(tagPath),
              !parts.path.dropFirst(tagPath.count).isEmpty,
              !parts.path.split(separator: "/").contains("..") else { return nil }
        return url
    }
}

/// Numeric app/release versions, with an optional Git tag prefix (v or V).
private struct AppVersion: Comparable {
    private let components: [Int]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" { value.removeFirst() }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(part) else { return nil }
            numbers.append(number)
        }
        components = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}
