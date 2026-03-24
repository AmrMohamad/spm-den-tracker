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
        let projectPath = try CLIInput.resolvedProjectPath(projectPath)
        let context = CLIContext()
        let report = try await context.engine.analyze(projectPath: projectPath)
        CLIOutput.write(context.tableFormatter.format(report))
        throw ExitCode(report.hasActionableFindings ? 1 : 0)
    }
}
