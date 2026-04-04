import ArgumentParser
import DependencyTrackerCore
import Foundation

/// CLI command that runs the full audit and renders the terminal table summary.
struct Doctor: AsyncParsableCommand {
    /// Declares the command name and help text.
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Run the full dependency audit and print a terminal summary.",
        discussion: """
        `doctor` is the fastest way to inspect the health of a project's Swift Package lockfile.
        It checks:

        - whether `Package.resolved` exists and is tracked by git
        - which schema version the file uses
        - whether dependencies are pinned to version, branch, revision, or local path
        - which declared dependency rules come from the project or manifest
        - whether newer stable upstream versions are available for version-pinned remote packages
        - when explicitly enabled, workspace-level findings across multiple manifests

        Accepted input forms:
        - `/path/to/MyApp.xcodeproj`
        - `/path/to/repo-root` when that directory contains exactly one `.xcodeproj`
        - `/path/to/Package.resolved`

        Analysis mode:
        - `single-target` preserves the current one-report behavior
        - `auto` lets the engine choose workspace-aware behavior for directory inputs
        - `monorepo` forces workspace-aware analysis

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

    /// Promotes declared-constraint findings into actionable failures.
    @Flag(name: .long, help: "Treat declared-constraint findings as actionable failures.")
    var strictConstraints = false

    /// Runs the command and throws the resulting exit code for ArgumentParser.
    func run() async throws {
        throw try await Self.execute(
            projectPath: projectPath,
            analysisMode: analysisMode.coreValue,
            strictConstraints: strictConstraints
        )
    }

    /// Performs the audit with injectable writers so CLI behavior can be regression tested.
    ///
    /// - Parameters:
    ///   - projectPath: User-provided project path.
    ///   - context: Shared engine/formatter bundle used by the command.
    ///   - write: Standard-output sink for the rendered table.
    ///   - writeError: Standard-error sink used during path validation.
    /// - Returns: Exit code `1` when the report contains actionable findings, otherwise `0`.
    static func execute(
        projectPath: String,
        analysisMode: AnalysisMode = .singleTarget,
        strictConstraints: Bool = false,
        context: CLIContext? = nil,
        write: (String) -> Void = CLIOutput.write,
        writeError: (String) -> Void = CLIOutput.writeError
    ) async throws -> ExitCode {
        let context = context ?? CLIContext(strictConstraints: strictConstraints, analysisMode: analysisMode)
        let resolvedPath = try CLIInput.resolvedProjectPath(projectPath, writeError: writeError)
        if analysisMode == .singleTarget {
            let report = try await context.engine.analyze(projectPath: resolvedPath)
            write(context.tableFormatter.format(report))
            return ExitCode(report.hasActionableFindings ? 1 : 0)
        }

        let report = try await context.workspaceEngine.analyze(rootPath: resolvedPath)
        write(context.tableFormatter.format(report))
        return ExitCode(report.hasActionableFindings ? 1 : 0)
    }
}
