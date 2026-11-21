// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation

public enum ReleaseUpdateFailure: Equatable {
    case network
    case invalidResponse
    case invalidRelease
    case currentVersion
    case http(Int)
}

public enum ReleaseUpdateResult: Equatable {
    case upToDate
    case updateAvailable(tag: String, url: URL)
    case failure(ReleaseUpdateFailure)
}

protocol ReleaseRequestTask: AnyObject {
    func resume()
    func cancel()
}

extension URLSessionDataTask: ReleaseRequestTask {}

/// Schedules background update checks and keeps at most one request in flight.
@MainActor
public final class GitHubReleaseChecker {
    typealias Completion = @Sendable (Data?, URLResponse?, Error?) -> Void
    typealias Transport = (URLRequest, @escaping Completion) -> ReleaseRequestTask

    private let apiURL: URL
    private let releaseURL: URL
    private let currentVersion: () -> String?
    private let transport: Transport
    private var automaticChecks: Task<Void, Never>?
    private var task: ReleaseRequestTask?
    private var requestID: UUID?
    private var completions: [(ReleaseUpdateResult) -> Void] = []

    public var isChecking: Bool { requestID != nil }

    public convenience init(
        apiURL: URL,
        releaseURL: URL,
        currentVersion: @escaping () -> String? = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        }
    ) {
        self.init(apiURL: apiURL, releaseURL: releaseURL, currentVersion: currentVersion,
                  transport: { URLSession.shared.dataTask(with: $0, completionHandler: $1) })
    }

    init(apiURL: URL, releaseURL: URL, currentVersion: @escaping () -> String?,
         transport: @escaping Transport) {
        self.apiURL = apiURL
        self.releaseURL = releaseURL
        self.currentVersion = currentVersion
        self.transport = transport
    }

    public func startAutomaticChecks(completion: @escaping (ReleaseUpdateResult) -> Void) {
        startAutomaticChecks(interval: .seconds(24 * 60 * 60), completion: completion)
    }

    func startAutomaticChecks(interval: Duration, completion: @escaping (ReleaseUpdateResult) -> Void) {
        guard automaticChecks == nil else { return }
        automaticChecks = Task { [weak self] in
            let clock = ContinuousClock()
            while !Task.isCancelled {
                do { try await clock.sleep(for: interval) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.check(completion: completion)
            }
        }
        check(joinInProgress: true, completion: completion)
    }

    public func check(
        joinInProgress: Bool = false,
        completion: @escaping (ReleaseUpdateResult) -> Void
    ) {
        guard !isChecking else {
            if joinInProgress { completions.append(completion) }
            return
        }
        completions = [completion]
        let id = UUID()
        requestID = id
        let version = currentVersion()
        var request = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        task = transport(request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.requestID == id else { return }
                self.requestID = nil
                self.task = nil
                let completions = self.completions
                self.completions.removeAll()
                let result = Self.evaluate(data: data, response: response, error: error,
                    currentVersion: version, fallbackReleaseURL: self.releaseURL)
                completions.forEach { $0(result) }
            }
        }
        task?.resume()
    }

    public func cancel() {
        automaticChecks?.cancel()
        automaticChecks = nil
        requestID = nil
        completions.removeAll()
        task?.cancel()
        task = nil
    }

    deinit {
        automaticChecks?.cancel()
        task?.cancel()
    }

    nonisolated static func evaluate(data: Data?, response: URLResponse?, error: Error?,
                                    currentVersion: String?, fallbackReleaseURL: URL) -> ReleaseUpdateResult {
        if error != nil { return .failure(.network) }
        guard let response = response as? HTTPURLResponse else { return .failure(.invalidResponse) }
        guard (200...299).contains(response.statusCode) else { return .failure(.http(response.statusCode)) }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let latest = AppVersion(tag) else { return .failure(.invalidRelease) }
        guard let currentVersion, let current = AppVersion(currentVersion) else {
            return .failure(.currentVersion)
        }
        guard latest > current else { return .upToDate }
        let url = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? fallbackReleaseURL
        return .updateAvailable(tag: tag, url: url)
    }
}

private struct AppVersion: Comparable {
    private let components: [Int]

    init?(_ rawValue: String) {
        var normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedValue.lowercased().hasPrefix("v") {
            normalizedValue.removeFirst()
        }

        let components = normalizedValue.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty else {
            return nil
        }

        var parsedComponents = [Int]()
        for component in components {
            guard !component.isEmpty,
                  let parsedComponent = Int(component),
                  parsedComponent >= 0 else {
                return nil
            }

            parsedComponents.append(parsedComponent)
        }

        self.components = parsedComponents
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let componentCount = max(lhs.components.count, rhs.components.count)
        for index in 0..<componentCount {
            let leftComponent = lhs.component(at: index)
            let rightComponent = rhs.component(at: index)

            if leftComponent != rightComponent {
                return leftComponent < rightComponent
            }
        }

        return false
    }

    private func component(at index: Int) -> Int {
        guard index < components.count else {
            return 0
        }

        return components[index]
    }
}
