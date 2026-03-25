import Foundation
import Testing
@testable import DependencyTrackerCore

struct GitClientTests {
    @Test
    func outsideRootPathsAreNotCollapsedBySharedPrefix() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(status: 0, stdout: "", stderr: ""))
        let client = GitClient(processRunner: runner, timeout: 5)
        let repositoryRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
        let filePath = URL(fileURLWithPath: "/tmp/repo-old/Package.resolved")

        _ = try await client.isTracked(filePath: filePath, repositoryRoot: repositoryRoot)

        let invocations = await runner.invocations
        #expect(invocations.count == 1)
        #expect(invocations[0] == ["git", "-C", "/tmp/repo", "ls-files", "--error-unmatch", "/tmp/repo-old/Package.resolved"])
    }

    @Test
    func inRepoPathsRemainRepositoryRelative() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(status: 0, stdout: "", stderr: ""))
        let client = GitClient(processRunner: runner, timeout: 5)
        let repositoryRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
        let filePath = URL(fileURLWithPath: "/tmp/repo/subdir/Package.resolved")

        _ = try await client.isTracked(filePath: filePath, repositoryRoot: repositoryRoot)

        let invocations = await runner.invocations
        #expect(invocations.count == 1)
        #expect(invocations[0] == ["git", "-C", "/tmp/repo", "ls-files", "--error-unmatch", "subdir/Package.resolved"])
    }

    @Test
    func remoteTagsFiltersPeeledRefs() async throws {
        let stdout = """
        abc\trefs/tags/v1.2.3
        def\trefs/tags/v1.2.3^{}
        ghi\trefs/tags/v1.4.0
        """
        let runner = RecordingProcessRunner(result: ProcessResult(status: 0, stdout: stdout, stderr: ""))
        let client = GitClient(processRunner: runner, timeout: 5)

        let tags = try await client.remoteTags(for: "https://example.com/sdk.git")

        #expect(tags == ["refs/tags/v1.2.3", "refs/tags/v1.4.0"])
    }
}

private actor RecordingProcessRunner: ProcessRunning {
    private(set) var invocations: [[String]] = []
    private let result: ProcessResult

    init(result: ProcessResult) {
        self.result = result
    }

    func run(arguments: [String], currentDirectoryURL: URL?, timeout: TimeInterval) async throws -> ProcessResult {
        invocations.append(arguments)
        return result
    }
}
