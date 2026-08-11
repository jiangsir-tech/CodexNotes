import Combine
import Foundation

enum AppUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case updateAvailable(version: String, url: URL)
    case failed
}

struct AvailableAppUpdate: Equatable, Sendable {
    let version: String
    let url: URL
}

struct AppBundleVersion: Equatable, Sendable {
    static let missingValue = "—"

    let version: String
    let build: String

    static var current: AppBundleVersion {
        AppBundleVersion(bundle: .main)
    }

    init(bundle: Bundle) {
        self.init(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    init(version: String?, build: String?) {
        self.version = Self.presentableValue(version)
        self.build = Self.presentableValue(build)
    }

    var displayVersion: String {
        "\(version) (\(build))"
    }

    private static func presentableValue(_ value: String?) -> String {
        guard let value else {
            return missingValue
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? missingValue : trimmed
    }
}

enum AppUpdateValidation {
    static func availableUpdate(
        version rawVersion: String,
        url rawURL: String,
        installedVersion rawInstalledVersion: String
    ) -> AvailableAppUpdate? {
        guard
            let installedVersion = SemanticVersion(rawInstalledVersion),
            let availableVersion = SemanticVersion(rawVersion),
            availableVersion > installedVersion,
            let releaseURL = validatedReleaseURL(
                rawURL,
                matchingVersion: availableVersion.displayString
            )
        else {
            return nil
        }

        return AvailableAppUpdate(
            version: availableVersion.displayString,
            url: releaseURL
        )
    }

    static func validatedReleaseURL(
        _ rawValue: String,
        matchingVersion rawVersion: String
    ) -> URL? {
        let releaseTagPathPrefix = "/jiangsir-tech/CodexNotes/releases/tag/"
        guard
            let expectedVersion = SemanticVersion(rawVersion),
            let components = URLComponents(string: rawValue),
            components.scheme?.lowercased() == "https",
            components.host?.lowercased() == "github.com",
            components.user == nil,
            components.password == nil,
            components.port == nil,
            components.query == nil,
            components.fragment == nil,
            components.percentEncodedPath == components.path,
            components.path.hasPrefix(releaseTagPathPrefix),
            let urlVersion = SemanticVersion(
                String(components.path.dropFirst(releaseTagPathPrefix.count))
            ),
            urlVersion.hasSameIdentity(as: expectedVersion),
            let url = components.url
        else {
            return nil
        }

        return url
    }
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    typealias Fetcher = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let latestReleaseAPIURL = URL(
        string: "https://api.github.com/repos/jiangsir-tech/CodexNotes/releases/latest"
    )!
    static let requestTimeout: TimeInterval = 10
    static let maximumResponseSize = 1_048_576

    @Published private(set) var state: AppUpdateState = .idle

    private let currentVersion: String
    private let fetcher: Fetcher
    private var checkTask: Task<AppUpdateState?, Never>?
    private var requestGeneration = 0

    convenience init(currentVersion: String = AppBundleVersion.current.version) {
        self.init(currentVersion: currentVersion) { request in
            try await URLSession.shared.data(for: request)
        }
    }

    init(
        currentVersion: String,
        fetcher: @escaping Fetcher
    ) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
    }

    /// Runs a user-requested update check. A concurrent call returns immediately.
    @discardableResult
    func checkForUpdates() async -> AppUpdateState? {
        guard checkTask == nil else {
            return nil
        }

        requestGeneration &+= 1
        let generation = requestGeneration
        let request = Self.makeRequest()
        let currentVersion = currentVersion
        let fetcher = fetcher

        state = .checking
        let task = Task { () -> AppUpdateState? in
            do {
                let (data, response) = try await fetcher(request)
                guard !Task.isCancelled else {
                    return nil
                }
                return Self.evaluate(
                    data: data,
                    response: response,
                    currentVersion: currentVersion
                )
            } catch {
                guard !Task.isCancelled else {
                    return nil
                }
                return .failed
            }
        }
        checkTask = task

        guard let nextState = await task.value else {
            return nil
        }
        guard finish(nextState, generation: generation) else {
            return nil
        }
        return nextState
    }

    func cancel() {
        guard let checkTask else {
            return
        }

        requestGeneration &+= 1
        self.checkTask = nil
        checkTask.cancel()
        if state == .checking {
            state = .idle
        }
    }

    private func finish(_ nextState: AppUpdateState, generation: Int) -> Bool {
        guard generation == requestGeneration else {
            return false
        }

        checkTask = nil
        state = nextState
        return true
    }

    private static func makeRequest() -> URLRequest {
        var request = URLRequest(
            url: latestReleaseAPIURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: requestTimeout
        )
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CodexNotes", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func evaluate(
        data: Data,
        response: URLResponse,
        currentVersion: String
    ) -> AppUpdateState {
        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            data.count <= maximumResponseSize,
            let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
            release.draft == false,
            release.prerelease == false,
            let installedVersion = SemanticVersion(currentVersion),
            let latestVersion = SemanticVersion(release.tagName),
            let releaseURL = AppUpdateValidation.validatedReleaseURL(
                release.htmlURL,
                matchingVersion: latestVersion.displayString
            )
        else {
            return .failed
        }

        guard latestVersion > installedVersion else {
            return .upToDate
        }

        return .updateAvailable(
            version: latestVersion.displayString,
            url: releaseURL
        )
    }

}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

private struct SemanticVersion: Comparable, Sendable {
    private enum PrereleaseIdentifier: Equatable, Sendable {
        case numeric(UInt)
        case textual(String)

        var description: String {
            switch self {
            case let .numeric(value):
                return String(value)
            case let .textual(value):
                return value
            }
        }
    }

    let major: UInt
    let minor: UInt
    let patch: UInt
    private let prerelease: [PrereleaseIdentifier]
    private let buildMetadata: [String]

    var displayString: String {
        var value = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            value += "-" + prerelease.map(\.description).joined(separator: ".")
        }
        if !buildMetadata.isEmpty {
            value += "+" + buildMetadata.joined(separator: ".")
        }
        return value
    }

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == rawValue, !trimmed.isEmpty else {
            return nil
        }

        let versionText: Substring
        if trimmed.first == "v" || trimmed.first == "V" {
            versionText = trimmed.dropFirst()
        } else {
            versionText = Substring(trimmed)
        }

        let buildParts = versionText.split(separator: "+", omittingEmptySubsequences: false)
        guard buildParts.count <= 2 else {
            return nil
        }

        let precedenceText = buildParts[0]
        let coreText: Substring
        let prereleaseText: Substring?
        if let separatorIndex = precedenceText.firstIndex(of: "-") {
            coreText = precedenceText[..<separatorIndex]
            prereleaseText = precedenceText[precedenceText.index(after: separatorIndex)...]
        } else {
            coreText = precedenceText
            prereleaseText = nil
        }

        let coreParts = coreText.split(separator: ".", omittingEmptySubsequences: false)
        guard
            coreParts.count == 3,
            let major = Self.parseCoreNumber(coreParts[0]),
            let minor = Self.parseCoreNumber(coreParts[1]),
            let patch = Self.parseCoreNumber(coreParts[2])
        else {
            return nil
        }

        var prerelease: [PrereleaseIdentifier] = []
        if let prereleaseText {
            let identifiers = prereleaseText.split(
                separator: ".",
                omittingEmptySubsequences: false
            )
            guard !identifiers.isEmpty else {
                return nil
            }

            for identifier in identifiers {
                guard Self.isValidIdentifier(identifier) else {
                    return nil
                }
                if identifier.allSatisfy(\.isNumber) {
                    guard
                        identifier.count == 1 || identifier.first != "0",
                        let value = UInt(identifier)
                    else {
                        return nil
                    }
                    prerelease.append(.numeric(value))
                } else {
                    prerelease.append(.textual(String(identifier)))
                }
            }
        }

        var buildMetadata: [String] = []
        if buildParts.count == 2 {
            let identifiers = buildParts[1].split(
                separator: ".",
                omittingEmptySubsequences: false
            )
            guard !identifiers.isEmpty, identifiers.allSatisfy(Self.isValidIdentifier) else {
                return nil
            }
            buildMetadata = identifiers.map(String.init)
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true):
            return false
        case (true, false):
            return false
        case (false, true):
            return true
        case (false, false):
            break
        }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) {
            if left == right {
                continue
            }

            switch (left, right) {
            case let (.numeric(leftValue), .numeric(rightValue)):
                return leftValue < rightValue
            case (.numeric, .textual):
                return true
            case (.textual, .numeric):
                return false
            case let (.textual(leftValue), .textual(rightValue)):
                return leftValue < rightValue
            }
        }

        return lhs.prerelease.count < rhs.prerelease.count
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major
            && lhs.minor == rhs.minor
            && lhs.patch == rhs.patch
            && lhs.prerelease == rhs.prerelease
    }

    func hasSameIdentity(as other: SemanticVersion) -> Bool {
        self == other && buildMetadata == other.buildMetadata
    }

    private static func parseCoreNumber(_ value: Substring) -> UInt? {
        guard
            !value.isEmpty,
            value.allSatisfy(\.isNumber),
            value.count == 1 || value.first != "0"
        else {
            return nil
        }
        return UInt(value)
    }

    private static func isValidIdentifier(_ value: Substring) -> Bool {
        !value.isEmpty && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
        }
    }
}
