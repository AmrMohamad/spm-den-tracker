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
        throw try await Self.execute(projectPath: projectPath, format: format, output: output)
    }

    static func execute(
        projectPath: String,
        format: ReportFormat,
        output: String?,
        context: CLIContext = CLIContext(),
        write: (String) -> Void = CLIOutput.write,
        writeFile: (String, URL) throws -> Void = CLIOutput.write,
        writeError: (String) -> Void = CLIOutput.writeError
    ) async throws -> ExitCode {
        let resolvedPath = try CLIInput.resolvedProjectPath(projectPath, writeError: writeError)
        let report = try await context.engine.analyze(projectPath: resolvedPath)
        let rendered = context.render(report, format: format)

        if let output {
            try writeFile(rendered, URL(fileURLWithPath: output))
        } else {
            write(rendered)
        }

        return ExitCode(report.hasActionableFindings ? 1 : 0)
    }
}
