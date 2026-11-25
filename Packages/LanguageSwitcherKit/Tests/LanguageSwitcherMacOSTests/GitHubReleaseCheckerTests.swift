// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Combine
import Foundation
@testable import LanguageSwitcherMacOS
import XCTest

@MainActor
final class GitHubReleaseCheckerTests: XCTestCase {
    private let apiURL = URL(string: "https://api.github.com/repos/example/app/releases/latest")!
    private let releaseURL = URL(string: "https://github.com/example/app/releases/latest")!

    func testVersionComparisonUsesNumericComponentsAndOptionalTagPrefix() {
        for tag in ["1.0.2", "v1.0.2", "V1.0.2", "1.0", "1", "0.9.9"] {
            XCTAssertEqual(evaluate(tag: tag), .upToDate, tag)
        }
        XCTAssertEqual(evaluate(tag: "v1.0.10"), .updateAvailable(.init(tag: "v1.0.10", url: releaseURL)))
        XCTAssertEqual(evaluate(tag: "2.0.0"), .updateAvailable(.init(tag: "2.0.0", url: releaseURL)))
    }

    func testNewReleaseKeepsItsURLAndFallsBackWhenURLIsMissing() {
        let tagURL = URL(string: "https://github.com/example/app/releases/tag/v1.1.0")!
        XCTAssertEqual(evaluate(tag: "v1.1.0", url: tagURL.absoluteString),
                       .updateAvailable(.init(tag: "v1.1.0", url: tagURL)))
        XCTAssertEqual(evaluate(tag: "v1.1.0"), .updateAvailable(.init(tag: "v1.1.0", url: releaseURL)))
    }

    func testInvalidVersionsAndMalformedReleaseAreReported() {
        for tag in ["", "v", "1..2", "1.-1.0", "latest", "1.1.0-beta.1"] {
            XCTAssertEqual(evaluate(tag: tag), .failure(.invalidRelease), tag)
        }
        XCTAssertEqual(evaluate(tag: "1.1.0", current: nil), .failure(.currentVersion))
        XCTAssertEqual(evaluate(tag: "1.1.0", current: "unknown"), .failure(.currentVersion))
        for data in [Data("not json".utf8), Data("[]".utf8), Data("{}".utf8)] {
            XCTAssertEqual(GitHubReleaseChecker.evaluate(data: data, response: response(), error: nil,
                currentVersion: "1.0.2", fallbackReleaseURL: releaseURL), .failure(.invalidRelease))
        }
    }

    func testNetworkAndHTTPFailuresRemainDistinct() {
        XCTAssertEqual(GitHubReleaseChecker.evaluate(data: nil, response: nil,
            error: URLError(.notConnectedToInternet), currentVersion: "1.0.2", fallbackReleaseURL: releaseURL),
            .failure(.network))
        XCTAssertEqual(GitHubReleaseChecker.evaluate(data: nil, response: nil, error: nil,
            currentVersion: "1.0.2", fallbackReleaseURL: releaseURL), .failure(.invalidResponse))
        for status in [403, 500] {
            XCTAssertEqual(GitHubReleaseChecker.evaluate(data: nil, response: response(status), error: nil,
                currentVersion: "1.0.2", fallbackReleaseURL: releaseURL), .failure(.http(status)))
        }
    }

    func testUnpublishedAndRateLimitedResponses() {
        let cases: [(Int, [String: String], ReleaseUpdateResult)] = [
            (404, [:], .notPublished),
            (429, [:], .failure(.rateLimited)),
            (403, ["X-RateLimit-Remaining": "0"], .failure(.rateLimited)),
            (403, ["Retry-After": "10"], .failure(.rateLimited))
        ]
        for (status, headers, expected) in cases {
            let response = HTTPURLResponse(url: apiURL, statusCode: status, httpVersion: nil, headerFields: headers)!
            XCTAssertEqual(GitHubReleaseChecker.evaluate(data: nil, response: response, error: nil,
                currentVersion: "1.0.2", fallbackReleaseURL: releaseURL), expected)
        }
    }

    func testRejectsDraftsPrereleasesAndUntrustedURLs() {
        for flag in ["draft", "prerelease"] {
            let data = try! JSONSerialization.data(withJSONObject: ["tag_name": "v1.1.0", flag: true])
            XCTAssertEqual(GitHubReleaseChecker.evaluate(data: data, response: response(), error: nil,
                currentVersion: "1.0.2", fallbackReleaseURL: releaseURL), .failure(.invalidRelease))
        }
        for url in ["https://example.org/installer", "https://github.com/other/app/releases/tag/v1.1.0",
                    "https://github.com/example/app/releases/tag/", "https://github.com/example/app/releases/tag/../x",
                    "https://github.com/example/app/releases/tag/v1.1.0?key=value"] {
            XCTAssertEqual(evaluate(tag: "v1.1.0", url: url), .updateAvailable(.init(tag: "v1.1.0", url: releaseURL)))
        }
    }

    func testCheckUsesConfiguredRepositoryAndPreventsOverlappingRequests() async {
        let transport = ReleaseTransportFake()
        let checker = makeChecker(transport)
        var states: [GitHubReleaseChecker.State] = []
        let observation = checker.$state.sink { states.append($0) }
        checker.startAutomaticChecks()
        checker.check()
        XCTAssertEqual(checker.state, .checking)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url, apiURL)
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "User-Agent"), "Language Switcher Test")
        XCTAssertEqual(transport.requests[0].timeoutInterval, 15)
        XCTAssertTrue(transport.tasks[0].resumed)
        transport.completions[0](releaseData("v1.1.0"), response(), nil)
        await flushMainQueue()
        XCTAssertEqual(states, [.idle, .checking, .finished(.updateAvailable(.init(tag: "v1.1.0", url: releaseURL)))])
        XCTAssertEqual(checker.availableRelease?.url, releaseURL)
        withExtendedLifetime(observation) {}
    }

    func testCancelAndRestartIgnoreLateResultFromPreviousCheck() async {
        let transport = ReleaseTransportFake()
        let checker = makeChecker(transport)
        checker.check()
        checker.cancel()
        XCTAssertEqual(checker.state, .idle)
        XCTAssertTrue(transport.tasks[0].cancelled)
        checker.check()
        transport.completions[0](releaseData("v9.0.0"), response(), nil)
        transport.completions[1](releaseData("v1.0.2"), response(), nil)
        await flushMainQueue()
        XCTAssertEqual(checker.state, .finished(.upToDate))
        XCTAssertNil(checker.availableRelease)
    }

    func testKeepsAvailableReleaseDuringRecheckAndFailureAndClearsItWhenUpToDate() async {
        let transport = ReleaseTransportFake()
        let checker = makeChecker(transport)
        var releases: [AvailableRelease?] = []
        let observation = checker.$availableRelease.sink { releases.append($0) }

        checker.check()
        transport.completions[0](releaseData("v1.1.0"), response(), nil)
        await flushMainQueue()
        let release = checker.availableRelease
        XCTAssertEqual(release?.tag, "v1.1.0")

        checker.check()
        XCTAssertEqual(checker.availableRelease, release)
        transport.completions[1](nil, nil, URLError(.timedOut))
        await flushMainQueue()
        XCTAssertEqual(checker.state, .finished(.failure(.network)))
        XCTAssertEqual(checker.availableRelease, release)

        checker.check()
        transport.completions[2](releaseData("v1.1.0"), response(), nil)
        await flushMainQueue()
        checker.check()
        transport.completions[3](releaseData("v1.0.2"), response(), nil)
        await flushMainQueue()
        XCTAssertEqual(checker.state, .finished(.upToDate))
        XCTAssertEqual(releases, [nil, release, nil])
        withExtendedLifetime(observation) {}
    }

    func testAutomaticChecksStartImmediatelyAndRepeatUntilCancelled() async throws {
        let transport = ReleaseTransportFake()
        let checker = makeChecker(transport)
        let interval: Duration = .milliseconds(25)
        let clock = ContinuousClock()
        checker.startAutomaticChecks(interval: interval)
        checker.startAutomaticChecks(interval: interval)
        XCTAssertEqual(transport.requests.count, 1)
        try await clock.sleep(for: interval * 2)
        XCTAssertEqual(transport.requests.count, 1, "Automatic checks must not overlap")

        transport.completions[0](releaseData("v1.0.2"), response(), nil)
        let deadline = clock.now + .seconds(2)
        while transport.requests.count < 2 && clock.now < deadline {
            try await clock.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(transport.requests.count, 2)

        checker.cancel()
        XCTAssertTrue(transport.tasks.last?.cancelled == true)
        try await clock.sleep(for: interval * 2)
        XCTAssertEqual(transport.requests.count, 2, "Cancellation must stop future checks")
    }

    func testDeinitializationCancelsPendingRequest() {
        let transport = ReleaseTransportFake()
        var checker: GitHubReleaseChecker? = makeChecker(transport)
        checker?.check()
        checker = nil
        XCTAssertTrue(transport.tasks[0].cancelled)
    }

    private func makeChecker(_ transport: ReleaseTransportFake) -> GitHubReleaseChecker {
        GitHubReleaseChecker(apiURL: apiURL, releaseURL: releaseURL, userAgent: "Language Switcher Test", currentVersion: { "1.0.2" },
            transport: { transport.makeTask($0, completion: $1) })
    }

    private func evaluate(tag: String, url: String? = nil, current: String? = "1.0.2") -> ReleaseUpdateResult {
        GitHubReleaseChecker.evaluate(data: releaseData(tag, url: url), response: response(), error: nil,
            currentVersion: current, fallbackReleaseURL: releaseURL)
    }

    private func releaseData(_ tag: String, url: String? = nil) -> Data {
        var json = ["tag_name": tag]
        if let url { json["html_url"] = url }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func response(_ status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: apiURL, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private func flushMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

private final class ReleaseTaskFake: ReleaseRequestTask {
    var resumed = false
    var cancelled = false
    func resume() { resumed = true }
    func cancel() { cancelled = true }
}

private final class ReleaseTransportFake {
    var requests: [URLRequest] = []
    var completions: [GitHubReleaseChecker.Completion] = []
    var tasks: [ReleaseTaskFake] = []
    func makeTask(_ request: URLRequest, completion: @escaping GitHubReleaseChecker.Completion) -> ReleaseRequestTask {
        requests.append(request)
        completions.append(completion)
        let task = ReleaseTaskFake()
        tasks.append(task)
        return task
    }
}
