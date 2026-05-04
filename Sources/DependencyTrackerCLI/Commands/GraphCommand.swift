import ArgumentParser
import DependencyTrackerCore
import Foundation

/// CLI command that renders a workspace graph as Mermaid, DOT, or JSON.
struct Graph: AsyncParsableCommand {
    /// Declares the command metadata used in help output.
    static let configuration = CommandConfiguration(
        commandName: "graph",
        abstract: "Render a workspace graph derived from dependency audit metadata.",
        discussion: """
        `graph` uses the workspace analysis surface to show discovered manifests and their aggregate ownership structure.
        It is designed to stay useful even before the richer dependency-edge graph arrives from core graph helpers.

        Accepted input forms:
        - `/path/to/MyApp.xcodeproj`
        - `/path/to/repo-root`
        - `/path/to/Package.resolved`

        Analysis mode:
        - `single-target` preserves the current one-report behavior
        - `auto` lets the engine choose workspace-aware behavior for directory inputs
        - `monorepo` forces workspace-aware analysis

        Output formats:
        - `mermaid`
        - `dot`
        - `json`
        """
    )

    /// Path to the project bundle, project directory, or resolved file to inspect.
    @Argument(help: "Path to an `.xcodeproj`, a directory, or a direct `Package.resolved` file.")
    var projectPath: String

    /// Selects how the command should interpret the input path.
    @Option(name: .long, help: "Select the analysis mode: `auto`, `monorepo`, or `single-target`.")
    var analysisMode: AnalysisModeOption = .singleTarget

    /// Output formatter selected by the user.
    @Option(name: .long, help: "Select the graph output format: `mermaid`, `dot`, or `json`.")
    var format: GraphFormat = .mermaid

    /// Optional destination path for persisted graph output.
    @Option(name: .long, help: "Write the rendered graph to this file path instead of standard output.")
    var output: String?

    /// Runs the command and throws the resulting exit code for ArgumentParser.
    func run() async throws {
        throw try await Self.execute(
            projectPath: projectPath,
            analysisMode: analysisMode.coreValue,
            format: format,
            output: output
        )
    }

    /// Performs workspace analysis and renders a graph summary.
    static func execute(
        projectPath: String,
        analysisMode: AnalysisMode = .singleTarget,
        format: GraphFormat,
        output: String?,
        context: CLIContext? = nil,
        write: (String) -> Void = CLIOutput.write,
        writeFile: (String, URL) throws -> Void = CLIOutput.write,
        writeError: (String) -> Void = CLIOutput.writeError
    ) async throws -> ExitCode {
        let context = context ?? CLIContext(analysisMode: analysisMode)
        let resolvedPath = try CLIInput.resolvedProjectPath(projectPath, writeError: writeError)
        let report = try await context.workspaceEngine.analyze(rootPath: resolvedPath)
        let rendered = WorkspaceGraphRenderer().render(report, format: format.coreValue)

        if let output {
            try writeFile(rendered, URL(fileURLWithPath: output))
        } else {
            write(rendered)
        }

        return ExitCode(report.hasActionableFindings ? 1 : 0)
    }
}

extension GraphFormat {
    /// Maps the CLI format enum into the core graph format enum.
    var coreValue: WorkspaceGraphFormat {
        switch self {
        case .mermaid:
            return .mermaid
        case .dot:
            return .dot
        case .json:
            return .json
        }
    }
}
