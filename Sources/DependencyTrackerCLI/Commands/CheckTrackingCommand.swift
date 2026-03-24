import ArgumentParser
import DependencyTrackerCore
import Foundation

struct CheckTracking: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check-tracking",
        abstract: "Check whether Package.resolved is tracked by git."
    )

    @Argument(help: "Path to the Xcode project directory or .xcodeproj bundle.")
    var projectPath: String

    func run() async throws {
        throw try await Self.execute(projectPath: projectPath)
    }

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
