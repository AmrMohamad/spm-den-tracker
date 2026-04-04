import Foundation
import Testing
@testable import DependencyTrackerCore

struct FoundationContractsTests {
    @Test
    func trackerConfigurationDefaultsMatchWorkspaceBaseline() {
        let configuration = TrackerConfiguration()

        #expect(configuration.analysisMode == .singleTarget)
        #expect(configuration.maxDiscoveryDepth == 10)
        #expect(configuration.ignoreFileName == ".spm-dep-tracker-ignore")
        #expect(configuration.enableGraphEnrichment)
        #expect(configuration.continueOnPartialFailure)
    }

    @Test
    func workspaceReportBecomesActionableForAggregateFindings() {
        let report = WorkspaceReport(
            rootPath: "/tmp/repo",
            generatedAt: Date(),
            analysisMode: .monorepo,
            discoveredManifests: [],
            contexts: [],
            aggregateFindings: [
                Finding(
                    severity: .warning,
                    category: .pinStrategy,
                    message: "warning",
                    recommendation: "fix"
                )
            ],
            partialFailures: []
        )

        #expect(report.hasActionableFindings)
    }

    @Test
    func workspaceAuditEngineWrapsSingleTargetReport() async throws {
        let fixturePath = try namedResolvedFixtureCopyURL().path
        let configuration = TrackerConfiguration(
            analysisMode: .monorepo,
            checkOutdated: false,
            checkDeclaredConstraints: false,
            timeout: 2
        )

        let workspaceReport = try await WorkspaceAuditEngine(configuration: configuration)
            .analyze(rootPath: fixturePath)

        #expect(workspaceReport.analysisMode == .monorepo)
        #expect(workspaceReport.discoveredManifests.count == 1)
        #expect(workspaceReport.contexts.count == 1)
        #expect(workspaceReport.contexts[0].reports.count == 1)
        #expect(workspaceReport.contexts[0].reports[0].resolvedFilePath == fixturePath)
    }
}

private func fixtureURL(named name: String) -> URL {
    Bundle.module.resourceURL!
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent(name)
}

private func namedResolvedFixtureCopyURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let destination = directory.appendingPathComponent("Package.resolved")
    try FileManager.default.copyItem(at: fixtureURL(named: "Package.resolved.v3.json"), to: destination)
    return destination.standardizedFileURL.resolvingSymlinksInPath()
}
