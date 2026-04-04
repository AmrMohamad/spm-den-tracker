import Foundation

/// Emits a compact JUnit XML document for CI systems that already ingest test reports.
public struct JUnitReporter: ReportFormatter {
    /// Creates a JUnit reporter.
    public init() {}

    /// Formats one audit suite with actionable findings as failures and the full summary in system-out.
    public func format(_ report: DependencyReport) -> String {
        let actionableFindings = report.findings.filter(\.isActionable)
        let testCases = actionableFindings.enumerated().map { index, finding in
            """
              <testcase classname="spm-dep-tracker.\(finding.category.rawValue)" name="finding-\(index + 1)">
                <failure message="\(escape(finding.message))">\(escape(finding.recommendation))</failure>
              </testcase>
            """
        }.joined(separator: "\n")

        let systemOut = escape(TableReporter().format(report))

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuite name="SPMDependencyTracker" tests="\(actionableFindings.count)" failures="\(actionableFindings.count)">
        \(testCases)
          <system-out>\(systemOut)</system-out>
        </testsuite>
        """
    }

    /// Formats aggregate workspace findings as a single CI suite.
    public func format(_ report: WorkspaceReport) -> String {
        let actionableFindings = WorkspaceReportSupport.scopedFindings(report).filter { $0.finding.isActionable }
        let actionableFailures = WorkspaceReportSupport.scopedPartialFailures(report).filter { $0.failure.severity != .info }

        let findingCases = actionableFindings.enumerated().map { index, finding in
            """
              <testcase classname="spm-dep-tracker.\(finding.finding.category.rawValue)" name="finding-\(index + 1)">
                <failure message="\(escape(finding.scope))">\(escape("\(finding.finding.message) - \(finding.finding.recommendation)"))</failure>
              </testcase>
            """
        }

        let failureCases = actionableFailures.enumerated().map { index, failure in
            """
              <testcase classname="spm-dep-tracker.partialFailure" name="partial-failure-\(index + 1)">
                <failure message="\(escape(failure.scope))">\(escape(WorkspaceReportSupport.partialFailureSummary(failure.failure)))</failure>
              </testcase>
            """
        }

        let testCases = (findingCases + failureCases).joined(separator: "\n")
        let systemOut = escape(TableReporter().format(report))

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuite name="SPMDependencyTrackerWorkspace" tests="\(actionableFindings.count + actionableFailures.count)" failures="\(actionableFindings.count + actionableFailures.count)">
        \(testCases)
          <system-out>\(systemOut)</system-out>
        </testsuite>
        """
    }

    /// Escapes XML-sensitive characters inside report text.
    private func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
