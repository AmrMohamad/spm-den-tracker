import Foundation

/// Audits whether the resolved lockfile is present and properly tracked by git.
struct GitTrackingAuditor: Sendable {
    /// The git abstraction used so repository checks remain testable.
    private let gitClient: GitClientProtocol

    /// Creates an auditor backed by the supplied git client.
    init(gitClient: GitClientProtocol) {
        self.gitClient = gitClient
    }

    /// Resolves the lockfile status by checking existence, repository membership, tracking, and ignore rules.
    func audit(resolvedFileURL: URL) async throws -> ResolvedFileStatus {
        guard FileManager.default.fileExists(atPath: resolvedFileURL.path) else {
            return .missing
        }

        guard let repositoryRoot = try await gitClient.repositoryRoot(containing: resolvedFileURL) else {
            return .untracked
        }

        if try await gitClient.isTracked(filePath: resolvedFileURL, repositoryRoot: repositoryRoot) {
            return .tracked
        }

        if let match = try await gitClient.checkIgnore(filePath: resolvedFileURL, repositoryRoot: repositoryRoot) {
            return .gitignored(match: match)
        }

        return .untracked
    }
}
