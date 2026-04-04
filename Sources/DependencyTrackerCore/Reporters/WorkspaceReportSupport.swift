import Foundation

/// Shared helpers for rendering aggregate workspace reports.
enum WorkspaceReportSupport {
    /// Returns the human-readable form of the analysis mode.
    static func analysisModeLabel(_ mode: AnalysisMode) -> String {
        switch mode {
        case .auto:
            return "auto"
        case .singleTarget:
            return "single-target"
        case .monorepo:
            return "monorepo"
        }
    }

    /// Flattens all findings visible in the workspace report.
    static func allFindings(_ report: WorkspaceReport) -> [Finding] {
        report.aggregateFindings + report.contexts.flatMap(\.findings)
    }

    /// Flattens all partial failures visible in the workspace report.
    static func allPartialFailures(_ report: WorkspaceReport) -> [PartialFailure] {
        report.partialFailures + report.contexts.flatMap(\.partialFailures)
    }

    /// Flattens all dependency reports visible in the workspace report.
    static func allDependencyReports(_ report: WorkspaceReport) -> [DependencyReport] {
        report.contexts.flatMap(\.reports)
    }

    /// Returns findings paired with the workspace scope that produced them.
    static func scopedFindings(_ report: WorkspaceReport) -> [(scope: String, finding: Finding)] {
        let aggregate = report.aggregateFindings.map { (scope: report.rootPath, finding: $0) }
        let contextual = report.contexts.flatMap { contextReport in
            contextReport.findings.map { (scope: contextReport.context.displayPath, finding: $0) }
        }
        return aggregate + contextual
    }

    /// Returns partial failures paired with the workspace scope that produced them.
    static func scopedPartialFailures(_ report: WorkspaceReport) -> [(scope: String, failure: PartialFailure)] {
        let aggregate = report.partialFailures.map { (scope: report.rootPath, failure: $0) }
        let contextual = report.contexts.flatMap { contextReport in
            contextReport.partialFailures.map { (scope: contextReport.context.displayPath, failure: $0) }
        }
        return aggregate + contextual
    }

    /// Builds a summary string for a partial failure so reporters stay consistent.
    static func partialFailureSummary(_ failure: PartialFailure) -> String {
        "[\(failure.stage.rawValue)] \(failure.message)"
    }
}
