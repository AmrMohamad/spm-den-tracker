import ArgumentParser
import DependencyTrackerCore
import Foundation

/// CLI command that renders the full report in table, markdown, or JSON form.
struct Report: AsyncParsableCommand {
    /// Declares the command name, summary, and longer discussion text.
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Generate a dependency report in table, markdown, JSON, Xcode, or JUnit format.",
        discussion: """
        `report` runs the same analysis pipeline as `doctor` but lets you choose the output format and optionally persist the rendered report to disk.

        Accepted input forms:
        - `/path/to/MyApp.xcodeproj`
        - `/path/to/repo-root` when that directory contains exactly one `.xcodeproj`
        - `/path/to/Package.resolved`

        Analysis mode:
        - `single-target` preserves the current one-report behavior
        - `auto` lets the engine choose workspace-aware behavior for directory inputs
        - `monorepo` forces workspace-aware analysis

        Common examples:
          spm-dep-tracker report MyApp.xcodeproj
          spm-dep-tracker report MyApp.xcodeproj --format markdown
          spm-dep-tracker report MyApp.xcodeproj --format json --output ./Reports/dependencies.json
          spm-dep-tracker report . --analysis-mode monorepo --format markdown
          spm-dep-tracker report MyApp.xcodeproj --format xcode
          spm-dep-tracker report MyApp.xcodeproj --format junit --strict-constraints

        Exit codes:
        - `0` when only informational findings were produced
        - `1` when warnings or errors were found
        - `65` when the input path does not exist
        """
    )

    /// Path to the project bundle, project directory, or resolved file to audit.
    @Argument(help: "Path to an `.xcodeproj`, a directory containing one `.xcodeproj`, or a direct `Package.resolved` file.")
    var projectPath: String

    /// Selects how the command should interpret the input path.
    @Option(name: .long, help: "Select the analysis mode: `auto`, `monorepo`, or `single-target`.")
    var analysisMode: AnalysisModeOption = .singleTarget

    /// Output formatter selected by the user.
    @Option(name: .long, help: "Select the output format: `table`, `markdown`, `json`, `xcode`, or `junit`.")
    var format: ReportFormat = .table

    /// Optional destination path; when omitted the report is written to standard output.
    @Option(name: .long, help: "Write the rendered report to this file path instead of standard output. Parent directories are created automatically if needed.")
    var output: String?

    /// Promotes declared-constraint findings into actionable failures.
    @Flag(name: .long, help: "Treat declared-constraint findings as actionable failures.")
    var strictConstraints = false

    /// Runs the command and throws the resulting exit code for ArgumentParser.
    func run() async throws {
        throw try await Self.execute(projectPath: projectPath, format: format, output: output, strictConstraints: strictConstraints)
    }

    /// Performs the report generation with injectable side effects for CLI tests.
    ///
    /// The command resolves and validates the path first, runs the same engine used by `doctor`,
    /// then chooses either terminal output or file output depending on whether `--output` was
    /// supplied. The injectable closures are deliberate seams used by CLI regression tests so they
    /// can verify text and exit-code behavior without touching real stdio or the filesystem.
    ///
    /// - Parameters:
    ///   - projectPath: User-provided project path.
    ///   - format: The requested report format.
    ///   - output: Optional destination path for persisted output.
    ///   - context: Shared engine/formatter bundle used by the command.
    ///   - write: Standard-output sink used when `output` is `nil`.
    ///   - writeFile: File-writing closure used when persisting rendered content.
    ///   - writeError: Standard-error sink used during path validation.
    /// - Returns: Exit code `1` when the report contains actionable findings, otherwise `0`.
    static func execute(
        projectPath: String,
        analysisMode: AnalysisMode = .singleTarget,
        format: ReportFormat,
        output: String?,
        strictConstraints: Bool = false,
        context: CLIContext? = nil,
        write: (String) -> Void = CLIOutput.write,
        writeFile: (String, URL) throws -> Void = CLIOutput.write,
        writeError: (String) -> Void = CLIOutput.writeError
    ) async throws -> ExitCode {
        let context = context ?? CLIContext(strictConstraints: strictConstraints, analysisMode: analysisMode)
        let resolvedPath = try CLIInput.resolvedProjectPath(projectPath, writeError: writeError)
        if analysisMode == .singleTarget {
            let report = try await context.engine.analyze(projectPath: resolvedPath)
            let rendered = context.render(report, format: format)

            if let output {
                try writeFile(rendered, URL(fileURLWithPath: output))
            } else {
                write(rendered)
            }

            return ExitCode(report.hasActionableFindings ? 1 : 0)
        }

        let report = try await context.workspaceEngine.analyze(rootPath: resolvedPath)
        let rendered = context.render(report, format: format)

        if let output {
            try writeFile(rendered, URL(fileURLWithPath: output))
        } else {
            write(rendered)
        }

        return ExitCode(report.hasActionableFindings ? 1 : 0)
    }
}
