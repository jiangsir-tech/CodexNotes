import Foundation
import XCTest
@testable import CodexNotesProbe

@MainActor
final class AppUpdateCheckerTests: XCTestCase {
    func testUpdateAvailableUsesExpectedRequestAndValidatedReleaseURL() async {
        let recorder = RequestRecorder()
        let data = releaseData(
            tag: "v1.5.0",
            url: "https://github.com/jiangsir-tech/CodexNotes/releases/tag/v1.5.0"
        )
        let response = httpResponse(statusCode: 200)
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            await recorder.record(request)
            return (data, response)
        }

        await checker.checkForUpdates()

        XCTAssertEqual(
            checker.state,
            .updateAvailable(
                version: "1.5.0",
                url: URL(
                    string: "https://github.com/jiangsir-tech/CodexNotes/releases/tag/v1.5.0"
                )!
            )
        )
        let request = await recorder.request
        XCTAssertEqual(request?.url, AppUpdateChecker.latestReleaseAPIURL)
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.timeoutInterval, 10)
        XCTAssertEqual(
            request?.value(forHTTPHeaderField: "Accept"),
            "application/vnd.github+json"
        )
        XCTAssertEqual(
            request?.value(forHTTPHeaderField: "X-GitHub-Api-Version"),
            "2022-11-28"
        )
        XCTAssertEqual(request?.value(forHTTPHeaderField: "User-Agent"), "CodexNotes")
    }

    func testEqualAndOlderLatestVersionsAreUpToDate() async {
        for latestVersion in ["v1.4.68", "1.4.67"] {
            let state = await checkedState(
                currentVersion: "1.4.68",
                data: releaseData(tag: latestVersion)
            )
            XCTAssertEqual(state, .upToDate, "Unexpected result for \(latestVersion)")
        }
    }

    func testSemanticVersionComparisonHandlesNumericComponentsAndPrereleaseIdentifiers() async {
        let numericComponentState = await checkedState(
            currentVersion: "1.9.9",
            data: releaseData(tag: "v1.10.0")
        )
        XCTAssertEqual(
            numericComponentState,
            .updateAvailable(
                version: "1.10.0",
                url: releaseURL(tag: "v1.10.0")
            )
        )

        let prereleaseState = await checkedState(
            currentVersion: "2.0.0-alpha-beta.1",
            data: releaseData(tag: "v2.0.0-alpha-beta.2+build.7")
        )
        XCTAssertEqual(
            prereleaseState,
            .updateAvailable(
                version: "2.0.0-alpha-beta.2+build.7",
                url: releaseURL(tag: "v2.0.0-alpha-beta.2+build.7")
            )
        )

        let stableState = await checkedState(
            currentVersion: "2.0.0-alpha.9",
            data: releaseData(tag: "2.0.0")
        )
        XCTAssertEqual(
            stableState,
            .updateAvailable(version: "2.0.0", url: releaseURL(tag: "2.0.0"))
        )
    }

    func testRejectsDraftAndPrereleaseGitHubReleases() async {
        let draftState = await checkedState(
            data: releaseData(tag: "1.5.0", draft: true)
        )
        let prereleaseState = await checkedState(
            data: releaseData(tag: "1.5.0", prerelease: true)
        )

        XCTAssertEqual(draftState, .failed)
        XCTAssertEqual(prereleaseState, .failed)
    }

    func testRejectsNonSuccessHTTPResponsesAndResponsesLargerThanOneMiB() async {
        let nonSuccessState = await checkedState(
            data: releaseData(tag: "1.5.0"),
            statusCode: 404
        )
        let oversizedState = await checkedState(
            data: Data(count: AppUpdateChecker.maximumResponseSize + 1)
        )

        XCTAssertEqual(nonSuccessState, .failed)
        XCTAssertEqual(oversizedState, .failed)
    }

    func testRejectsMalformedPayloadsAndInvalidSemanticVersions() async {
        let malformedState = await checkedState(data: Data("{}".utf8))
        XCTAssertEqual(malformedState, .failed)

        let invalidVersions = [
            "1.4",
            "01.4.0",
            "1.04.0",
            "1.4.00",
            "1.4.0-01",
            "1.4.0+",
            " 1.4.0",
            "1.4.0_1"
        ]
        for version in invalidVersions {
            let state = await checkedState(data: releaseData(tag: version))
            XCTAssertEqual(state, .failed, "Unexpectedly accepted \(version)")
        }

        let invalidCurrentVersionState = await checkedState(
            currentVersion: AppBundleVersion.missingValue,
            data: releaseData(tag: "1.5.0")
        )
        XCTAssertEqual(invalidCurrentVersionState, .failed)
    }

    func testRejectsReleaseURLsOutsideTheExpectedHTTPSGitHubPath() async {
        let invalidURLs = [
            "http://github.com/jiangsir-tech/CodexNotes/releases/tag/v1.5.0",
            "https://github.com.evil.example/jiangsir-tech/CodexNotes/releases/tag/v1.5.0",
            "https://github.com/another-owner/CodexNotes/releases/tag/v1.5.0",
            "https://github.com/jiangsir-tech/CodexNotes/issues/1",
            "https://github.com/jiangsir-tech/CodexNotes/releases/download/v1.5.0/CodexNotes.zip",
            "https://github.com/jiangsir-tech/CodexNotes/releases/tag/v9.9.9",
            "https://github.com/jiangsir-tech/CodexNotes/releases/tag/v1.5.0/extra",
            "https://user@github.com/jiangsir-tech/CodexNotes/releases/tag/v1.5.0",
            "https://github.com:443/jiangsir-tech/CodexNotes/releases/tag/v1.5.0",
            "https://github.com/jiangsir-tech/CodexNotes/releases/tag/v1.5.0?download=1",
            "https://github.com/jiangsir-tech/CodexNotes/releases/tag/v1.5.0#notes"
        ]

        for url in invalidURLs {
            let state = await checkedState(data: releaseData(tag: "1.5.0", url: url))
            XCTAssertEqual(state, .failed, "Unexpectedly accepted \(url)")
        }
    }

    func testConcurrentCheckDoesNotStartAnotherRequest() async {
        let fetcher = SuspendedFetcher(
            result: (
                releaseData(tag: "1.5.0"),
                httpResponse(statusCode: 200)
            )
        )
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await fetcher.fetch(request)
        }

        let firstCheck = Task { await checker.checkForUpdates() }
        await waitUntil { await fetcher.callCount == 1 }
        XCTAssertEqual(checker.state, .checking)

        await checker.checkForUpdates()
        let callCount = await fetcher.callCount
        XCTAssertEqual(callCount, 1)

        await fetcher.resume()
        _ = await firstCheck.value
        XCTAssertEqual(
            checker.state,
            .updateAvailable(version: "1.5.0", url: releaseURL(tag: "1.5.0"))
        )
    }

    func testCancellationReturnsToIdleAndDoesNotPublishFailure() async {
        let fetcher = SuspendedFetcher(
            result: (
                releaseData(tag: "1.5.0"),
                httpResponse(statusCode: 200)
            )
        )
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await fetcher.fetch(request)
        }

        let check = Task { await checker.checkForUpdates() }
        await waitUntil { await fetcher.callCount == 1 }
        checker.cancel()

        XCTAssertEqual(checker.state, .idle)
        await fetcher.resume()
        _ = await check.value
        XCTAssertEqual(checker.state, .idle)
    }

    func testCancellationAfterFetchResumesBeforePublicationReturnsNilAndStaysIdle() async {
        let fetcher = SynchronouslyResumableFetcher(
            result: (
                releaseData(tag: "1.5.0"),
                httpResponse(statusCode: 200)
            )
        )
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await fetcher.fetch(request)
        }

        let check = Task { await checker.checkForUpdates() }
        await waitUntil { fetcher.callCount == 1 }

        fetcher.resume()
        checker.cancel()

        let result = await check.value
        XCTAssertNil(result)
        XCTAssertEqual(checker.state, .idle)
    }

    func testThrownFetcherErrorPublishesFailure() async {
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { _ in
            throw StubError.network
        }

        await checker.checkForUpdates()

        XCTAssertEqual(checker.state, .failed)
    }

    func testBundleVersionTrimsValuesAndUsesDashForMissingFields() {
        let populatedVersion = AppBundleVersion(
            version: " 1.4.68\n",
            build: " 88 "
        )
        XCTAssertEqual(populatedVersion.version, "1.4.68")
        XCTAssertEqual(populatedVersion.build, "88")
        XCTAssertEqual(populatedVersion.displayVersion, "1.4.68 (88)")
        XCTAssertEqual(
            AppBundleVersion(version: nil, build: " \n "),
            AppBundleVersion(version: "—", build: "—")
        )
        XCTAssertEqual(
            AppBundleVersion(version: nil, build: nil).displayVersion,
            "— (—)"
        )
    }

    private var defaultReleaseURL: URL {
        releaseURL(tag: "v1.5.0")
    }

    private func releaseURL(tag: String) -> URL {
        URL(string: "https://github.com/jiangsir-tech/CodexNotes/releases/tag/\(tag)")!
    }

    private func checkedState(
        currentVersion: String = "1.4.68",
        data: Data,
        statusCode: Int = 200
    ) async -> AppUpdateState {
        let response = httpResponse(statusCode: statusCode)
        let checker = AppUpdateChecker(currentVersion: currentVersion) { _ in
            (data, response)
        }
        await checker.checkForUpdates()
        return checker.state
    }

    private func releaseData(
        tag: String,
        url: String? = nil,
        draft: Bool = false,
        prerelease: Bool = false
    ) -> Data {
        let encodedTag = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let inferredURL = "https://github.com/jiangsir-tech/CodexNotes/releases/tag/\(encodedTag)"
        return try! JSONSerialization.data(withJSONObject: [
            "tag_name": tag,
            "html_url": url ?? inferredURL,
            "draft": draft,
            "prerelease": prerelease
        ])
    }

    private func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: AppUpdateChecker.latestReleaseAPIURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        _ predicate: @escaping @Sendable () async -> Bool
    ) async {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        while !(await predicate()) {
            if DispatchTime.now().uptimeNanoseconds - startedAt >= timeoutNanoseconds {
                XCTFail("Timed out waiting for asynchronous state")
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private actor RequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }
}

private actor SuspendedFetcher {
    private let result: (Data, URLResponse)
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private(set) var callCount = 0

    init(result: (Data, URLResponse)) {
        self.result = result
    }

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private final class SynchronouslyResumableFetcher: @unchecked Sendable {
    private let lock = NSLock()
    private let result: (Data, URLResponse)
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var storedCallCount = 0

    var callCount: Int {
        lock.withLock { storedCallCount }
    }

    init(result: (Data, URLResponse)) {
        self.result = result
    }

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                storedCallCount += 1
                self.continuation = continuation
            }
        }
    }

    func resume() {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: result)
    }
}

private enum StubError: Error {
    case network
}
