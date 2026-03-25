import Foundation

/// Defines the git operations the analyzers need without tying tests to `Process`.
protocol GitClientProtocol: Sendable {
    /// Returns the repository root containing the supplied file or directory, if any.
    func repositoryRoot(containing path: URL) async throws -> URL?
    /// Indicates whether the file is tracked by git from the given repository root.
    func isTracked(filePath: URL, repositoryRoot: URL) async throws -> Bool
    /// Returns the ignore rule that matches the file, if git reports one.
    func checkIgnore(filePath: URL, repositoryRoot: URL) async throws -> GitIgnoreMatch?
    /// Fetches all remote tag refs for the dependency location.
    func remoteTags(for location: String) async throws -> [String]
}

/// Implements git queries by shelling out to the host `git` executable.
struct GitClient: GitClientProtocol {
    /// The process runner used to execute git commands.
    private let processRunner: ProcessRunning
    /// The timeout applied to each git invocation.
    private let timeout: TimeInterval

    /// Creates a git client with injectable process execution for tests.
    init(processRunner: ProcessRunning = ProcessRunner(), timeout: TimeInterval) {
        self.processRunner = processRunner
        self.timeout = timeout
    }

    /// Resolves the repository root for a path and returns `nil` when the path is outside any git checkout.
    func repositoryRoot(containing path: URL) async throws -> URL? {
        let directory = path.hasDirectoryPath ? path : path.deletingLastPathComponent()
        let result = try await processRunner.run(
            arguments: ["git", "-C", directory.path, "rev-parse", "--show-toplevel"],
            currentDirectoryURL: directory,
            timeout: timeout
        )
        guard result.status == 0 else {
            return nil
        }

        let root = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: root, isDirectory: true)
    }

    /// Uses `git ls-files --error-unmatch` to verify tracking without mutating the repository.
    func isTracked(filePath: URL, repositoryRoot: URL) async throws -> Bool {
        let relativePath = relativePath(for: filePath, repositoryRoot: repositoryRoot)
        let result = try await processRunner.run(
            arguments: ["git", "-C", repositoryRoot.path, "ls-files", "--error-unmatch", relativePath],
            currentDirectoryURL: repositoryRoot,
            timeout: timeout
        )
        return result.status == 0
    }

    /// Uses `git check-ignore -v` so ignored files can report the exact matching rule.
    func checkIgnore(filePath: URL, repositoryRoot: URL) async throws -> GitIgnoreMatch? {
        let relativePath = relativePath(for: filePath, repositoryRoot: repositoryRoot)
        let result = try await processRunner.run(
            arguments: ["git", "-C", repositoryRoot.path, "check-ignore", "-v", relativePath],
            currentDirectoryURL: repositoryRoot,
            timeout: timeout
        )

        guard result.status == 0 else {
            return nil
        }

        let line = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        guard let metadata = pieces.first else {
            return nil
        }

        let components = metadata.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count >= 3 else {
            return nil
        }

        let sourcePath = String(components[0])
        let lineNumber = Int(components[1]) ?? 0
        let pattern = components.dropFirst(2).joined(separator: ":")
        return GitIgnoreMatch(sourcePath: sourcePath, line: lineNumber, pattern: pattern)
    }

    /// Lists remote tags for a dependency and throws when git cannot reach the upstream.
    func remoteTags(for location: String) async throws -> [String] {
        let result = try await processRunner.run(
            arguments: ["git", "ls-remote", "--tags", location],
            currentDirectoryURL: nil,
            timeout: timeout
        )

        guard result.status == 0 else {
            throw DependencyTrackerError.commandFailed(
                command: ["git", "ls-remote", "--tags", location],
                status: result.status,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return result.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard let ref = line.split(separator: "\t").last.map(String.init) else {
                    return nil
                }
                return ref.hasSuffix("^{}") ? nil : ref
            }
    }

    /// Converts an absolute file URL into the repository-relative path git expects.
    private func relativePath(for filePath: URL, repositoryRoot: URL) -> String {
        let fileComponents = filePath.standardizedFileURL.pathComponents
        let rootComponents = repositoryRoot.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
            return filePath.path
        }

        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
