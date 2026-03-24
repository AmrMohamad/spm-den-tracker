import DependencyTrackerCore
import Foundation

/// Bundles the core engine and reporters used by all CLI commands.
struct CLIContext: Sendable {
    /// Shared audit engine configured with the CLI defaults.
    let engine = TrackerEngine(configuration: TrackerConfiguration())
    /// Plain-text table formatter used by `doctor` and the default `report` mode.
    let tableFormatter = TableReporter()
    /// Markdown formatter used when the user requests sharable output.
    let markdownFormatter = MarkdownReporter()
    /// JSON formatter used for machine-readable output.
    let jsonFormatter = JSONReporter()

    /// Renders a report using the formatter selected by the CLI option.
    func render(_ report: DependencyReport, format: ReportFormat) -> String {
        switch format {
        case .table:
            return tableFormatter.format(report)
        case .markdown:
            return markdownFormatter.format(report)
        case .json:
            return jsonFormatter.format(report)
        }
    }

    /// Converts a resolved-file status into the one-line output expected by `check-tracking`.
    func describe(_ status: ResolvedFileStatus, resolvedFileURL: URL) -> String {
        switch status {
        case .tracked:
            return "\(resolvedFileURL.path): tracked"
        case .untracked:
            return "\(resolvedFileURL.path): exists but is not tracked"
        case .missing:
            return "\(resolvedFileURL.path): missing"
        case .gitignored(let match):
            return "\(resolvedFileURL.path): gitignored by \(match.summary)"
        }
    }
}
