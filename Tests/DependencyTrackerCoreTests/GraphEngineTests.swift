import Foundation
import Testing
@testable import DependencyTrackerCore

struct GraphEngineTests {
    @Test
    func workspaceAuditAddsDependencyGraphSummaryWhenEnrichmentIsEnabled() async throws {
        let root = try temporaryPackageRoot()
        let engine = WorkspaceAuditEngine(
            configuration: TrackerConfiguration(
                analysisMode: .singleTarget,
                checkOutdated: false,
                checkGitTracking: false,
                checkDeclaredConstraints: false,
                enableGraphEnrichment: true
            )
        )

        let report = try await engine.analyze(rootPath: root.path)
        let document = WorkspaceGraphBuilder().makeDocument(from: report)

        #expect(report.graphSummary?.certainty == .partiallyEnriched)
        #expect(document.nodes.contains { $0.kind == "dependency" && $0.metadata["identity"] == "kingfisher" })
        #expect(document.edges.contains { $0.provenance.source == .packageResolved })
        #expect(report.aggregateFindings.contains { $0.category == .graph && $0.message.contains("without direct declaration provenance") })
    }

    @Test
    func workspaceAuditKeepsMetadataOnlyGraphWhenEnrichmentIsDisabled() async throws {
        let root = try temporaryPackageRoot()
        let engine = WorkspaceAuditEngine(
            configuration: TrackerConfiguration(
                analysisMode: .singleTarget,
                checkOutdated: false,
                checkGitTracking: false,
                checkDeclaredConstraints: false,
                enableGraphEnrichment: false
            )
        )

        let report = try await engine.analyze(rootPath: root.path)
        let document = WorkspaceGraphBuilder().makeDocument(from: report)

        #expect(report.graphSummary?.certainty == .metadataOnly)
        #expect(!document.nodes.contains { $0.kind == "dependency" })
        #expect(!document.edges.contains { $0.provenance.source == .packageResolved })
        #expect(report.aggregateFindings.isEmpty)
    }
}

private func temporaryPackageRoot() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try """
    // swift-tools-version: 6.0
    import PackageDescription
    let package = Package(name: "Fixture")
    """.write(
        to: directory.appendingPathComponent("Package.swift"),
        atomically: true,
        encoding: .utf8
    )

    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Package.resolved.v3.json")
    let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)
    try fixture.write(
        to: directory.appendingPathComponent("Package.resolved"),
        atomically: true,
        encoding: .utf8
    )
    return directory
}
