import ArgumentParser
import DependencyTrackerCore
import Foundation

struct Report: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Generate a structured dependency report.",
        discussion: """
        The report command uses the same Core audit pipeline as doctor, but lets you choose a formatter and an output file.
        """
    )

    @Argument(help: "Path to the Xcode project directory or .xcodeproj bundle.")
    var projectPath: String

    @Option(name: .long, help: "Select the report format.")
    var format: ReportFormat = .table

    @Option(name: .long, help: "Write the report to this path instead of standard output.")
    var output: String?

    func run() async throws {
        let projectPath = try CLIInput.resolvedProjectPath(projectPath)
        let context = CLIContext()
        let report = try await context.engine.analyze(projectPath: projectPath)
        let rendered = context.render(report, format: format)

        if let output {
            try CLIOutput.write(rendered, to: URL(fileURLWithPath: output))
        } else {
            CLIOutput.write(rendered)
        }

        throw ExitCode(report.hasActionableFindings ? 1 : 0)
    }
}
