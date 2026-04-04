import Foundation

/// Assembles a stable workspace report from discovery, per-context reports, and aggregate findings.
public struct WorkspaceReportAssembler: Sendable {
    public init() {}

    /// Builds a workspace report with deterministic ordering and retained partial-failure detail.
    public func assemble(
        rootPath: String,
        generatedAt: Date,
        analysisMode: AnalysisMode,
        discoveredManifests: [DiscoveredManifest],
        contextReports: [ResolutionContextReport],
        aggregateFindings: [Finding],
        partialFailures: [PartialFailure],
        graphSummary: WorkspaceGraphSummary? = nil
    ) -> WorkspaceReport {
        WorkspaceReport(
            rootPath: rootPath,
            generatedAt: generatedAt,
            analysisMode: analysisMode,
            discoveredManifests: discoveredManifests.sorted(by: { $0.path < $1.path }),
            contexts: contextReports.sorted(by: contextReportSortOrder),
            aggregateFindings: aggregateFindings.sorted(by: findingSortOrder),
            partialFailures: partialFailures.sorted(by: partialFailureSortOrder),
            graphSummary: graphSummary
        )
    }

    /// Sorts context reports deterministically.
    private func contextReportSortOrder(_ lhs: ResolutionContextReport, _ rhs: ResolutionContextReport) -> Bool {
        if lhs.context.displayPath != rhs.context.displayPath {
            return lhs.context.displayPath < rhs.context.displayPath
        }
        return lhs.context.key < rhs.context.key
    }

    /// Sorts findings by severity, then category, then message.
    private func findingSortOrder(_ lhs: Finding, _ rhs: Finding) -> Bool {
        if lhs.severity != rhs.severity {
            return severityRank(lhs.severity) < severityRank(rhs.severity)
        }
        if lhs.category != rhs.category {
            return lhs.category.rawValue < rhs.category.rawValue
        }
        return lhs.message < rhs.message
    }

    /// Sorts partial failures by severity, then stage, then subject.
    private func partialFailureSortOrder(_ lhs: PartialFailure, _ rhs: PartialFailure) -> Bool {
        if lhs.severity != rhs.severity {
            return severityRank(lhs.severity) < severityRank(rhs.severity)
        }
        if lhs.stage != rhs.stage {
            return lhs.stage.rawValue < rhs.stage.rawValue
        }
        return lhs.subjectPath < rhs.subjectPath
    }

    /// Maps severities to a stable sort order.
    private func severityRank(_ severity: Severity) -> Int {
        switch severity {
        case .error: return 0
        case .warning: return 1
        case .info: return 2
        }
    }
}
