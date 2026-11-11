// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

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
        XCTAssertEqual(evaluate(tag: "v1.0.10"), .updateAvailable(tag: "v1.0.10", url: releaseURL))
        XCTAssertEqual(evaluate(tag: "2.0.0"), .updateAvailable(tag: "2.0.0", url: releaseURL))
    }

    func testNewReleaseKeepsItsURLAndFallsBackWhenURLIsMissing() {
        let tagURL = URL(string: "https://github.com/example/app/releases/tag/v1.1.0")!
        XCTAssertEqual(evaluate(tag: "v1.1.0", url: tagURL.absoluteString),
                       .updateAvailable(tag: "v1.1.0", url: tagURL))
        XCTAssertEqual(evaluate(tag: "v1.1.0"), .updateAvailable(tag: "v1.1.0", url: releaseURL))
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
        for status in [403, 404, 429, 500] {
            XCTAssertEqual(GitHubReleaseChecker.evaluate(data: nil, response: response(status), error: nil,
                currentVersion: "1.0.2", fallbackReleaseURL: releaseURL), .failure(.http(status)))
        }
    }

    func testCheckUsesConfiguredRepositoryAndPreventsOverlappingRequests() async {
        let transport = ReleaseTransportFake()
        let checker = makeChecker(transport)
        var results: [ReleaseUpdateResult] = []
        checker.check { results.append($0) }
        checker.check { results.append($0) }
        XCTAssertTrue(checker.isChecking)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url, apiURL)
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(transport.requests[0].timeoutInterval, 15)
        XCTAssertTrue(transport.tasks[0].resumed)
        transport.completions[0](releaseData("v1.1.0"), response(), nil)
        await flushMainQueue()
        XCTAssertFalse(checker.isChecking)
        XCTAssertEqual(results, [.updateAvailable(tag: "v1.1.0", url: releaseURL)])
        checker.check { results.append($0) }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testCancelAndRestartIgnoreLateResultFromPreviousWindow() async {
        let transport = ReleaseTransportFake()
        let checker = makeChecker(transport)
        var results: [ReleaseUpdateResult] = []
        checker.check { results.append($0) }
        checker.cancel()
        XCTAssertFalse(checker.isChecking)
        XCTAssertTrue(transport.tasks[0].cancelled)
        checker.check { results.append($0) }
        transport.completions[0](releaseData("v9.0.0"), response(), nil)
        transport.completions[1](releaseData("v1.0.2"), response(), nil)
        await flushMainQueue()
        XCTAssertFalse(checker.isChecking)
        XCTAssertEqual(results, [.upToDate])
    }

    func testNetworkFailureCompletesAndAllowsRetry() async {
        let transport = ReleaseTransportFake()
        let checker = makeChecker(transport)
        var result: ReleaseUpdateResult?
        checker.check { result = $0 }
        transport.completions[0](nil, nil, URLError(.timedOut))
        await flushMainQueue()
        XCTAssertEqual(result, .failure(.network))
        XCTAssertFalse(checker.isChecking)
        checker.check { _ in }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testDeinitializationCancelsPendingRequest() {
        let transport = ReleaseTransportFake()
        var checker: GitHubReleaseChecker? = makeChecker(transport)
        checker?.check { _ in XCTFail("Released checker must not deliver results") }
        checker = nil
        XCTAssertTrue(transport.tasks[0].cancelled)
    }

    private func makeChecker(_ transport: ReleaseTransportFake) -> GitHubReleaseChecker {
        GitHubReleaseChecker(apiURL: apiURL, releaseURL: releaseURL, currentVersion: { "1.0.2" },
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
