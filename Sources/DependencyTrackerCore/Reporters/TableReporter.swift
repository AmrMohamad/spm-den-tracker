import Foundation

public struct TableReporter: ReportFormatter {
    public init() {}

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
        let headers = ["Package", "Current", "Latest", "Update", "Pin State"]
        let rows = report.dependencies.sorted(by: { $0.pin.identity < $1.pin.identity }).map { dependency in
            [
                dependency.pin.identity,
                dependency.pin.state.displayValue,
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

    private func row(_ columns: [String], widths: [Int]) -> String {
        return zip(columns, widths)
            .map { value, width in value.padding(toLength: width, withPad: " ", startingAt: 0) }
            .joined(separator: "  ")
    }

    private func columnWidths(headers: [String], rows: [[String]]) -> [Int] {
        headers.enumerated().map { index, header in
            max(header.count, rows.map { $0[index].count }.max() ?? 0)
        }
    }

    private func separator(widths: [Int]) -> String {
        widths
            .map { String(repeating: "-", count: $0) }
            .joined(separator: "  ")
    }
}
