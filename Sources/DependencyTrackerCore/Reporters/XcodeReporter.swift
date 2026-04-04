import Foundation

/// Renders findings in Xcode-parsable warning and error lines.
public struct XcodeReporter: ReportFormatter {
    /// Creates an Xcode reporter.
    public init() {}

    /// Formats the findings into one compiler-style line per finding.
    public func format(_ report: DependencyReport) -> String {
        report.findings.map { finding in
            let level = finding.severity == .error ? "error" : "warning"
            return "\(report.resolvedFilePath): \(level): [\(finding.category.rawValue)] \(finding.message) \(finding.recommendation)"
        }
        .joined(separator: "\n")
    }

    /// Formats aggregate workspace findings as compiler-style diagnostics.
    public func format(_ report: WorkspaceReport) -> String {
        var lines: [String] = []

        for scoped in WorkspaceReportSupport.scopedFindings(report) {
            let finding = scoped.finding
            let level = finding.severity == .error ? "error" : "warning"
            lines.append("\(scoped.scope): \(level): [\(finding.category.rawValue)] \(finding.message) \(finding.recommendation)")
        }

        for scoped in WorkspaceReportSupport.scopedPartialFailures(report) {
            let failure = scoped.failure
            let level = failure.severity == .error ? "error" : "warning"
            lines.append("\(scoped.scope): \(level): [partialFailure] [\(failure.stage.rawValue)] \(failure.message)")
        }

        return lines.joined(separator: "\n")
    }
}
