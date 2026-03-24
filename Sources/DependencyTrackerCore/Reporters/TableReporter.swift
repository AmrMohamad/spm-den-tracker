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
        lines.append(row(["Package", "Current", "Latest", "Update", "Pin State"]))
        lines.append(String(repeating: "-", count: 82))

        for dependency in report.dependencies.sorted(by: { $0.pin.identity < $1.pin.identity }) {
            let latest = dependency.outdated?.latestVersion ?? "—"
            let update = dependency.outdated?.updateType?.rawValue ?? "—"
            let current = dependency.pin.state.displayValue
            lines.append(row([dependency.pin.identity, current, latest, update, dependency.pin.state.strategyLabel]))
        }

        return lines.joined(separator: "\n")
    }

    private func row(_ columns: [String]) -> String {
        let widths = [24, 14, 14, 8, 14]
        return zip(columns, widths)
            .map { value, width in value.padding(toLength: width, withPad: " ", startingAt: 0) }
            .joined(separator: " ")
    }
}
