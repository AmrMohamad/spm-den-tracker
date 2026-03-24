import ArgumentParser
import DependencyTrackerCore
import Foundation

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Run the full dependency audit and print a terminal summary."
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
        let report = try await context.engine.analyze(projectPath: resolvedPath)
        write(context.tableFormatter.format(report))
        return ExitCode(report.hasActionableFindings ? 1 : 0)
    }
}
