import Foundation
import Testing
@testable import DependencyTrackerCore

struct AnalyzerTests {
    @Test
    func requirementStrategyMapsAllPinStates() {
        let pins: [ResolvedPin] = [
            .init(identity: "tagged", kind: .remoteSourceControl, location: "https://example.com/tagged.git", state: .version("1.0.0", revision: "1")),
            .init(identity: "branch", kind: .remoteSourceControl, location: "https://example.com/branch.git", state: .branch("main", revision: "2")),
            .init(identity: "sha", kind: .remoteSourceControl, location: "https://example.com/sha.git", state: .revision("3")),
            .init(identity: "local", kind: .fileSystem, location: "/tmp/local", state: .local),
        ]

        let results = RequirementStrategyAuditor().audit(pins)

        #expect(results.map(\.risk) == [.normal, .elevated, .elevated, .environmentSensitive])
    }

    @Test
    func outdatedCheckerClassifiesMinorUpdate() async throws {
        let client = StubGitClient(tags: [
            "https://example.com/sdk.git": [
                "refs/tags/v1.2.3",
                "refs/tags/v1.4.0",
                "refs/tags/v1.4.0^{}",
            ]
        ])
        let checker = OutdatedChecker(gitClient: client, concurrentFetchLimit: 2)
        let pin = ResolvedPin(identity: "sdk", kind: .remoteSourceControl, location: "https://example.com/sdk.git", state: .version("1.2.3", revision: "abc"))

        let results = try await checker.check([pin])

        #expect(results.count == 1)
        #expect(results[0].latestVersion == "1.4.0")
        #expect(results[0].updateType == .minor)
        #expect(results[0].isOutdated)
    }

    @Test
    func outdatedCheckerClassifiesMajorAndPatchUpdates() async throws {
        let client = StubGitClient(tags: [
            "https://example.com/major.git": [
                "refs/tags/v1.2.3",
                "refs/tags/v2.0.0",
            ],
            "https://example.com/patch.git": [
                "refs/tags/v1.2.3",
                "refs/tags/v1.2.4",
            ],
        ])
        let checker = OutdatedChecker(gitClient: client, concurrentFetchLimit: 2)
        let majorPin = ResolvedPin(identity: "major", kind: .remoteSourceControl, location: "https://example.com/major.git", state: .version("1.2.3", revision: "abc"))
        let patchPin = ResolvedPin(identity: "patch", kind: .remoteSourceControl, location: "https://example.com/patch.git", state: .version("1.2.3", revision: "def"))

        let results = try await checker.check([majorPin, patchPin])

        #expect(results.first(where: { $0.pin.identity == "major" })?.updateType == .major)
        #expect(results.first(where: { $0.pin.identity == "patch" })?.updateType == .patch)
    }

    @Test
    func outdatedCheckerIgnoresPrereleaseOnlyTags() async throws {
        let client = StubGitClient(tags: [
            "https://example.com/sdk.git": [
                "refs/tags/v2.0.0-beta.1",
                "refs/tags/v1.2.3",
            ]
        ])
        let checker = OutdatedChecker(gitClient: client, concurrentFetchLimit: 1)
        let pin = ResolvedPin(identity: "sdk", kind: .remoteSourceControl, location: "https://example.com/sdk.git", state: .version("1.2.3", revision: "abc"))

        let result = try await checker.check([pin]).first

        #expect(result?.isOutdated == false)
        #expect(result?.latestVersion == "1.2.3")
    }

    @Test
    func outdatedCheckerReportsNoStableSemanticTags() async throws {
        let client = StubGitClient(tags: [
            "https://example.com/sdk.git": [
                "refs/tags/dev-build",
                "refs/tags/beta.1",
            ]
        ])
        let checker = OutdatedChecker(gitClient: client, concurrentFetchLimit: 1)
        let pin = ResolvedPin(identity: "sdk", kind: .remoteSourceControl, location: "https://example.com/sdk.git", state: .version("1.2.3", revision: "abc"))

        let result = try await checker.check([pin]).first

        #expect(result?.isOutdated == false)
        #expect(result?.noteKind == .noStableSemanticTags)
    }

    @Test
    func outdatedCheckerReportsNonSemanticResolvedVersion() async throws {
        let client = StubGitClient(tags: [
            "https://example.com/sdk.git": [
                "refs/tags/v1.4.0",
            ]
        ])
        let checker = OutdatedChecker(gitClient: client, concurrentFetchLimit: 1)
        let pin = ResolvedPin(identity: "sdk", kind: .remoteSourceControl, location: "https://example.com/sdk.git", state: .version("main-snapshot", revision: "abc"))

        let result = try await checker.check([pin]).first

        #expect(result?.isOutdated == false)
        #expect(result?.noteKind == .nonSemanticResolvedVersion)
    }

    @Test
    func outdatedCheckerCapturesRemoteFailuresAsNotes() async throws {
        let client = StubGitClient(erroringLocations: ["https://example.com/sdk.git"])
        let checker = OutdatedChecker(gitClient: client, concurrentFetchLimit: 1)
        let pin = ResolvedPin(identity: "sdk", kind: .remoteSourceControl, location: "https://example.com/sdk.git", state: .version("1.2.3", revision: "abc"))

        let result = try await checker.check([pin]).first

        #expect(result?.isOutdated == false)
        #expect(result?.noteKind == .remoteLookupFailure)
        #expect(result?.note != nil)
    }
}

private struct StubGitClient: GitClientProtocol {
    let tags: [String: [String]]
    let erroringLocations: Set<String>

    init(tags: [String: [String]] = [:], erroringLocations: Set<String> = []) {
        self.tags = tags
        self.erroringLocations = erroringLocations
    }

    func repositoryRoot(containing path: URL) async throws -> URL? { path.deletingLastPathComponent() }
    func isTracked(filePath: URL, repositoryRoot: URL) async throws -> Bool { false }
    func checkIgnore(filePath: URL, repositoryRoot: URL) async throws -> GitIgnoreMatch? { nil }

    func remoteTags(for location: String) async throws -> [String] {
        if erroringLocations.contains(location) {
            throw DependencyTrackerError.commandFailed(command: ["git", "ls-remote", "--tags", location], status: 1, stderr: "network failed")
        }
        return tags[location] ?? []
    }
}
