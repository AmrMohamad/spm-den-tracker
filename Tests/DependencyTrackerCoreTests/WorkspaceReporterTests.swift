import Foundation
import Testing
@testable import DependencyTrackerCore

struct WorkspaceReporterTests {
    @Test
    func tableReporterIncludesWorkspaceSummaryAndContexts() {
        let output = TableReporter().format(sampleWorkspaceReport())

        #expect(output.contains("SPM Dependency Tracker Workspace"))
        #expect(output.contains("Mode: auto"))
        #expect(output.contains("Partial failures"))
        #expect(output.contains("ContextA"))
        #expect(output.contains("alamofire"))
    }

    @Test
    func markdownReporterIncludesWorkspaceSections() {
        let output = MarkdownReporter().format(sampleWorkspaceReport())

        #expect(output.contains("# SPM Dependency Tracker Workspace Report"))
        #expect(output.contains("## Contexts"))
        #expect(output.contains("### ContextA"))
        #expect(output.contains("#### Dependencies"))
    }

    @Test
    func jsonReporterRoundTripsWorkspaceReport() throws {
        let report = sampleWorkspaceReport()

        let output = JSONReporter().format(report)
        let data = Data(output.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkspaceReport.self, from: data)

        #expect(decoded.rootPath == report.rootPath)
        #expect(decoded.analysisMode == report.analysisMode)
        #expect(decoded.contexts.count == 1)
        #expect(decoded.graphSummary?.certainty == .metadataOnly)
    }

    @Test
    func xcodeReporterIncludesScopedWorkspaceDiagnostics() {
        let output = XcodeReporter().format(sampleWorkspaceReport())

        #expect(output.contains("warning: [declaredConstraint]"))
        #expect(output.contains("warning: [partialFailure] [audit]"))
        #expect(output.contains("ContextA"))
    }

    @Test
    func junitReporterEmitsWorkspaceFailures() {
        let output = JUnitReporter().format(sampleWorkspaceReport())

        #expect(output.contains("<testsuite name=\"SPMDependencyTrackerWorkspace\""))
        #expect(output.contains("spm-dep-tracker.partialFailure"))
        #expect(output.contains("spm-dep-tracker.declaredConstraint"))
    }
}

private func sampleWorkspaceReport() -> WorkspaceReport {
    let pin = ResolvedPin(
        identity: "alamofire",
        kind: .remoteSourceControl,
        location: "https://github.com/Alamofire/Alamofire.git",
        state: .version("5.9.1", revision: "abc")
    )
    let dependency = DependencyAnalysis(
        pin: pin,
        outdated: OutdatedResult(pin: pin, latestVersion: "5.10.0", updateType: .minor, isOutdated: true),
        strategyRisk: .normal,
        declaredRequirement: DeclaredRequirement(
            identity: "alamofire",
            source: .xcodeProject,
            kind: .upToNextMajor,
            lowerBound: "5.9.1",
            location: "https://github.com/Alamofire/Alamofire.git",
            description: "from 5.9.1"
        ),
        constraintDrift: .newerAllowedAvailable,
        latestAllowedVersion: "5.10.0"
    )
    let dependencyReport = DependencyReport(
        projectPath: "/tmp/ContextA.xcodeproj",
        generatedAt: Date(timeIntervalSince1970: 0),
        resolvedFilePath: "/tmp/ContextA.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        resolvedFileStatus: .tracked,
        schemaVersion: SchemaInfo(version: 3, compatibility: .modern, message: "Schema version 3 is the modern Xcode 15+ format."),
        dependencies: [dependency],
        findings: [
            Finding(
                severity: .warning,
                category: .declaredConstraint,
                message: "Dependency can update without changing the declared requirement.",
                recommendation: "Review the declared requirement and commit the refreshed lockfile if needed.",
                isActionable: true
            )
        ]
    )
    let context = ResolutionContext(
        key: "context-a",
        displayPath: "ContextA",
        resolvedFilePath: dependencyReport.resolvedFilePath,
        manifestPaths: ["/tmp/ContextA.xcodeproj"]
    )
    let contextReport = ResolutionContextReport(
        context: context,
        reports: [dependencyReport],
        findings: [
            Finding(
                severity: .warning,
                category: .declaredConstraint,
                message: "Context drift detected.",
                recommendation: "Align the declared requirement with the shared workspace policy."
            )
        ],
        partialFailures: [
            PartialFailure(stage: .audit, subjectPath: "ContextA", message: "Skipped optional enrichment.", severity: .warning)
        ]
    )

    return WorkspaceReport(
        rootPath: "/tmp/Workspace",
        generatedAt: Date(timeIntervalSince1970: 0),
        analysisMode: .auto,
        discoveredManifests: [
            DiscoveredManifest(path: "/tmp/ContextA.xcodeproj", kind: .xcodeproj, resolvedFilePath: dependencyReport.resolvedFilePath, ownershipKey: dependencyReport.resolvedFilePath)
        ],
        contexts: [contextReport],
        aggregateFindings: [
            Finding(
                severity: .info,
                category: .schema,
                message: "Workspace discovery completed.",
                recommendation: "No action required."
            )
        ],
        partialFailures: [
            PartialFailure(stage: .discovery, subjectPath: "/tmp/Workspace", message: "One nested directory was ignored.", severity: .info)
        ],
        graphSummary: WorkspaceGraphSummary(certainty: .metadataOnly, message: "Topology derived from discovered workspace contexts.")
    )
}
