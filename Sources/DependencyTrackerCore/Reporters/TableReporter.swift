import Foundation

/// Renders reports as aligned plain text for terminal output.
public struct TableReporter: ReportFormatter {
    /// Creates a table reporter.
    public init() {}

    /// Formats the report into a terminal-friendly summary followed by an aligned dependency table.
    public func format(_ report: DependencyReport) -> String {
        var lines: [String] = []
        lines.append("SPM Dependency Tracker")
        lines.append("Project: \(report.projectPath)")
        lines.append("Resolved: \(report.resolvedFilePath)")
        lines.append("")
        appendFindings(report.findings, into: &lines)
        lines.append("")
        appendDependencyTable(for: report, into: &lines)

        return lines.joined(separator: "\n")
    }

    /// Formats an aggregate workspace report while preserving the same terminal style.
    public func format(_ report: WorkspaceReport) -> String {
        var lines: [String] = []
        lines.append("SPM Dependency Tracker Workspace")
        lines.append("Root: \(report.rootPath)")
        lines.append("Mode: \(WorkspaceReportSupport.analysisModeLabel(report.analysisMode))")
        lines.append("Generated: \(report.generatedAt.ISO8601Format())")
        lines.append("Discovered manifests: \(report.discoveredManifests.count)")
        lines.append("Contexts: \(report.contexts.count)")
        lines.append("Partial failures: \(WorkspaceReportSupport.allPartialFailures(report).count)")
        lines.append("")
        appendFindings(WorkspaceReportSupport.allFindings(report), into: &lines)
        if !WorkspaceReportSupport.allPartialFailures(report).isEmpty {
            lines.append("")
            lines.append("Partial failures")
            for failure in WorkspaceReportSupport.allPartialFailures(report) {
                lines.append("- [\(failure.severity.rawValue.uppercased())] \(WorkspaceReportSupport.partialFailureSummary(failure))")
            }
        }

        lines.append("")
        lines.append("Contexts")
        if report.contexts.isEmpty {
            lines.append("- No contexts discovered.")
        } else {
            for context in report.contexts {
                lines.append("- \(context.context.displayPath)")
                lines.append("  Resolved: \(context.context.resolvedFilePath ?? "—")")
                lines.append("  Manifests: \(context.context.manifestPaths.count)")
                lines.append("  Findings: \(context.findings.count)")
                lines.append("  Partial failures: \(context.partialFailures.count)")
                for dependencyReport in context.reports {
                    lines.append("")
                    lines.append(indent(format(dependencyReport)))
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Pads each row to the computed column widths.
    private func row(_ columns: [String], widths: [Int]) -> String {
        return zip(columns, widths)
            .map { value, width in value.padding(toLength: width, withPad: " ", startingAt: 0) }
            .joined(separator: "  ")
    }

    /// Appends findings in the standard terminal style.
    private func appendFindings(_ findings: [Finding], into lines: inout [String]) {
        lines.append("Findings")
        if findings.isEmpty {
            lines.append("- No findings.")
            return
        }

        for finding in findings {
            lines.append("- [\(finding.severity.rawValue.uppercased())] \(finding.message)")
        }
    }

    /// Appends a dependency table for a single dependency report.
    private func appendDependencyTable(for report: DependencyReport, into lines: inout [String]) {
        let headers = ["Package", "Current", "Declared", "Allowed", "Latest", "Update", "Pin State"]
        let rows = report.dependencies.sorted(by: { $0.pin.identity < $1.pin.identity }).map { dependency in
            [
                dependency.pin.identity,
                dependency.pin.state.displayValue,
                dependency.declaredRequirement?.description ?? "—",
                dependency.latestAllowedVersion ?? "—",
                dependency.outdated?.latestVersion ?? "—",
                dependency.outdated?.updateType?.rawValue ?? "—",
                dependency.pin.state.strategyLabel,
            ]
        }
        let widths = columnWidths(headers: headers, rows: rows)

        lines.append(row(headers, widths: widths))
        lines.append(separator(widths: widths))

        for columns in rows {
            lines.append(row(columns, widths: widths))
        }
    }

    /// Indents a nested section so workspace output stays readable.
    private func indent(_ string: String, prefix: String = "  ") -> String {
        string
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    /// Computes the widest value in each column so long package names do not get truncated.
    private func columnWidths(headers: [String], rows: [[String]]) -> [Int] {
        headers.enumerated().map { index, header in
            max(header.count, rows.map { $0[index].count }.max() ?? 0)
        }
    }

    /// Builds the underline row that visually separates table headers from data.
    private func separator(widths: [Int]) -> String {
        widths
            .map { String(repeating: "-", count: $0) }
            .joined(separator: "  ")
    }
}
