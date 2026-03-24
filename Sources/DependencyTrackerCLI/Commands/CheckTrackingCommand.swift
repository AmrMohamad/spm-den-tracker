import ArgumentParser
import DependencyTrackerCore
import Foundation

/// CLI command that reports only the git-tracking state of `Package.resolved`.
struct CheckTracking: AsyncParsableCommand {
    /// Declares the command name and summary used by ArgumentParser help output.
    static let configuration = CommandConfiguration(
        commandName: "check-tracking",
        abstract: "Check whether the resolved lockfile exists and is tracked by git.",
        discussion: """
        `check-tracking` is a narrow, script-friendly command for CI or preflight checks.
        It resolves the same input forms as the other commands, then prints one line describing whether the target `Package.resolved` file is:

        - tracked
        - untracked
        - gitignored
        - missing

        Accepted input forms:
        - `/path/to/MyApp.xcodeproj`
        - `/path/to/repo-root` when that directory contains exactly one `.xcodeproj`
        - `/path/to/Package.resolved`

        Exit codes:
        - `0` when the file is tracked
        - `2` when the file is missing, untracked, or ignored
        - `65` when the input path does not exist
        """
    )

    /// Path to the project bundle, project directory, or resolved file to inspect.
    @Argument(help: "Path to an `.xcodeproj`, a directory containing one `.xcodeproj`, or a direct `Package.resolved` file.")
    var projectPath: String

    /// Runs the command and converts the returned exit code into the throwing style expected by ArgumentParser.
    func run() async throws {
        throw try await Self.execute(projectPath: projectPath)
    }

    /// Performs the tracking check with injectable output closures for tests.
    ///
    /// The command intentionally bypasses the full report pipeline and emits a compact one-line
    /// status so it can be used in scripts as a fast guard for lockfile tracking problems.
    ///
    /// - Parameters:
    ///   - projectPath: User-provided project path.
    ///   - context: Shared engine/formatter bundle used by the command.
    ///   - write: Standard-output sink for the compact status message.
    ///   - writeError: Standard-error sink used during path validation.
    /// - Returns: Exit code `0` for tracked files and `2` for all other statuses.
    static func execute(
        projectPath: String,
        context: CLIContext = CLIContext(),
        write: (String) -> Void = CLIOutput.write,
        writeError: (String) -> Void = CLIOutput.writeError
    ) async throws -> ExitCode {
        let resolvedPath = try CLIInput.resolvedProjectPath(projectPath, writeError: writeError)
        let resolvedFileURL = try context.engine.locateResolvedFile(at: resolvedPath)
        let status = try await context.engine.auditGitTracking(resolvedFileURL: resolvedFileURL)

        write(context.describe(status, resolvedFileURL: resolvedFileURL))
        return ExitCode(status.isTracked ? 0 : 2)
    }
}
