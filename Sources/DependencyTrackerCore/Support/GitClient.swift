import Foundation

protocol GitClientProtocol: Sendable {
    func repositoryRoot(containing path: URL) async throws -> URL?
    func isTracked(filePath: URL, repositoryRoot: URL) async throws -> Bool
    func checkIgnore(filePath: URL, repositoryRoot: URL) async throws -> GitIgnoreMatch?
    func remoteTags(for location: String) async throws -> [String]
}

struct GitClient: GitClientProtocol {
    private let processRunner: ProcessRunning
    private let timeout: TimeInterval

    init(processRunner: ProcessRunning = ProcessRunner(), timeout: TimeInterval) {
        self.processRunner = processRunner
        self.timeout = timeout
    }

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

    func isTracked(filePath: URL, repositoryRoot: URL) async throws -> Bool {
        let relativePath = relativePath(for: filePath, repositoryRoot: repositoryRoot)
        let result = try await processRunner.run(
            arguments: ["git", "-C", repositoryRoot.path, "ls-files", "--error-unmatch", relativePath],
            currentDirectoryURL: repositoryRoot,
            timeout: timeout
        )
        return result.status == 0
    }

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
            .compactMap { line in
                line.split(separator: "\t").last.map(String.init)
            }
    }

    private func relativePath(for filePath: URL, repositoryRoot: URL) -> String {
        let file = filePath.standardizedFileURL.path
        let root = repositoryRoot.standardizedFileURL.path
        guard file.hasPrefix(root) else {
            return filePath.path
        }

        let index = file.index(file.startIndex, offsetBy: root.count)
        let suffix = file[index...]
        return suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
