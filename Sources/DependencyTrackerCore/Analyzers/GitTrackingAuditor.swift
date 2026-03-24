import Foundation

struct GitTrackingAuditor: Sendable {
    private let gitClient: GitClientProtocol

    init(gitClient: GitClientProtocol) {
        self.gitClient = gitClient
    }

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
