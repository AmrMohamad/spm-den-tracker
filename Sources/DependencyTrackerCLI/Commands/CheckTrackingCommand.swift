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
        let projectPath = try CLIInput.resolvedProjectPath(projectPath)
        let context = CLIContext()
        let resolvedFileURL = try await context.engine.locateResolvedFile(at: projectPath)
        let status = try await context.engine.auditGitTracking(resolvedFileURL: resolvedFileURL)

        CLIOutput.write(context.describe(status, resolvedFileURL: resolvedFileURL))
        throw ExitCode(status.isTracked ? 0 : 2)
    }
}
