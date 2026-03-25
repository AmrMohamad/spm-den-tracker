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
        lines.append("Findings")
        if report.findings.isEmpty {
            lines.append("- No findings.")
        } else {
            for finding in report.findings {
                lines.append("- [\(finding.severity.rawValue.uppercased())] \(finding.message)")
            }
        }

        lines.append("")
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

        return lines.joined(separator: "\n")
    }

    /// Pads each row to the computed column widths.
    private func row(_ columns: [String], widths: [Int]) -> String {
        return zip(columns, widths)
            .map { value, width in value.padding(toLength: width, withPad: " ", startingAt: 0) }
            .joined(separator: "  ")
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
