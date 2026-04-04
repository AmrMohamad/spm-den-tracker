import Foundation

/// Renders reports as markdown suitable for sharing in documents or pull requests.
public struct MarkdownReporter: ReportFormatter {
    /// Creates a markdown reporter.
    public init() {}

    /// Formats the report into sections for metadata, findings, and dependencies.
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
        appendFindingList(report.findings, into: &lines)
        lines.append("")
        appendDependencyTable(report, heading: "## Dependencies", into: &lines)

        return lines.joined(separator: "\n")
    }

    /// Formats an aggregate workspace report in a shareable markdown structure.
    public func format(_ report: WorkspaceReport) -> String {
        var lines: [String] = []
        lines.append("# SPM Dependency Tracker Workspace Report")
        lines.append("")
        lines.append("- Root: `\(report.rootPath)`")
        lines.append("- Mode: `\(WorkspaceReportSupport.analysisModeLabel(report.analysisMode))`")
        lines.append("- Generated at: `\(report.generatedAt.ISO8601Format())`")
        lines.append("- Discovered manifests: `\(report.discoveredManifests.count)`")
        lines.append("- Contexts: `\(report.contexts.count)`")
        lines.append("- Partial failures: `\(WorkspaceReportSupport.allPartialFailures(report).count)`")
        lines.append("")
        lines.append("## Findings")
        lines.append("")
        appendFindingList(WorkspaceReportSupport.allFindings(report), into: &lines)

        if !WorkspaceReportSupport.allPartialFailures(report).isEmpty {
            lines.append("")
            lines.append("## Partial Failures")
            lines.append("")
            for failure in WorkspaceReportSupport.allPartialFailures(report) {
                lines.append("- **\(failure.severity.rawValue.uppercased())** \(WorkspaceReportSupport.partialFailureSummary(failure))")
            }
        }

        lines.append("")
        lines.append("## Contexts")
        lines.append("")

        if report.contexts.isEmpty {
            lines.append("- No contexts discovered.")
        } else {
            for context in report.contexts {
                lines.append("### \(context.context.displayPath)")
                lines.append("")
                lines.append("- Resolved: `\(context.context.resolvedFilePath ?? "—")`")
                lines.append("- Manifests: `\(context.context.manifestPaths.count)`")
                lines.append("- Findings: `\(context.findings.count)`")
                lines.append("- Partial failures: `\(context.partialFailures.count)`")

                for dependencyReport in context.reports {
                    lines.append("")
                    appendDependencyTable(dependencyReport, heading: "#### Dependencies", into: &lines)
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Appends a markdown list of findings.
    private func appendFindingList(_ findings: [Finding], into lines: inout [String]) {
        if findings.isEmpty {
            lines.append("- No findings.")
            return
        }

        for finding in findings {
            lines.append("- **\(finding.severity.rawValue.uppercased())** \(finding.message) — \(finding.recommendation)")
        }
    }

    /// Appends a dependency table under the supplied heading.
    private func appendDependencyTable(_ report: DependencyReport, heading: String, into lines: inout [String]) {
        lines.append(heading)
        lines.append("")
        lines.append("| Package | Current | Declared | Allowed | Latest | Update | Pin State |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- |")

        for dependency in report.dependencies.sorted(by: { $0.pin.identity < $1.pin.identity }) {
            lines.append("| \(dependency.pin.identity) | \(dependency.pin.state.displayValue) | \(dependency.declaredRequirement?.description ?? "—") | \(dependency.latestAllowedVersion ?? "—") | \(dependency.outdated?.latestVersion ?? "—") | \(dependency.outdated?.updateType?.rawValue ?? "—") | \(dependency.pin.state.strategyLabel) |")
        }
    }
}
