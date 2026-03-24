import DependencyTrackerCore
import Foundation

struct CLIContext: Sendable {

    let engine = TrackerEngine(configuration: TrackerConfiguration())
    let tableFormatter = TableReporter()
    let markdownFormatter = MarkdownReporter()
    let jsonFormatter = JSONReporter()

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
