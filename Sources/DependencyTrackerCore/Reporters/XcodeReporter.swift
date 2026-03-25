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
}
