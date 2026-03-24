import Foundation

public struct MarkdownReporter: ReportFormatter {
    public init() {}

    public func format(_ report: DependencyReport) -> String {
        var lines: [String] = []
        lines.append("# SPM Dependency Report")
        lines.append("")
        lines.append("- Project: `\(report.projectPath)`")
        lines.append("- Resolved file: `\(report.resolvedFilePath)`")
        lines.append("- Generated at: `\(report.generatedAt.ISO8601Format())`")
        lines.append("")
        lines.append("## Findings")
        lines.append("")

        if report.findings.isEmpty {
            lines.append("- No findings.")
        } else {
            for finding in report.findings {
                lines.append("- **\(finding.severity.rawValue.uppercased())** \(finding.message) — \(finding.recommendation)")
            }
        }

        lines.append("")
        lines.append("## Dependencies")
        lines.append("")
        lines.append("| Package | Current | Latest | Update | Pin State |")
        lines.append("| --- | --- | --- | --- | --- |")

        for dependency in report.dependencies.sorted(by: { $0.pin.identity < $1.pin.identity }) {
            lines.append("| \(dependency.pin.identity) | \(dependency.pin.state.displayValue) | \(dependency.outdated?.latestVersion ?? "—") | \(dependency.outdated?.updateType?.rawValue ?? "—") | \(dependency.pin.state.strategyLabel) |")
        }

        return lines.joined(separator: "\n")
    }
}
