import Foundation
import Testing
@testable import DependencyTrackerCore

struct WorkspaceGraphRendererTests {
    @Test
    func mermaidOutputKeepsWorkspaceTopology() {
        let report = sampleWorkspaceReport()
        let output = WorkspaceGraphRenderer().render(report, format: .mermaid)

        #expect(output.contains("graph TD"))
        #expect(output.contains("MyWorkspace"))
        #expect(output.contains("ContextA"))
        #expect(output.contains("contains"))
    }

    @Test
    func dotOutputKeepsWorkspaceTopology() {
        let report = sampleWorkspaceReport()
        let output = WorkspaceGraphRenderer().render(report, format: .dot)

        #expect(output.contains("digraph WorkspaceGraph"))
        #expect(output.contains("rankdir=TB"))
        #expect(output.contains("shape=ellipse"))
        #expect(output.contains("MyWorkspace"))
    }

    @Test
    func jsonOutputCarriesCertaintyAndMessage() throws {
        let report = sampleWorkspaceReport()
        let output = WorkspaceGraphRenderer().render(report, format: .json)
        let data = Data(output.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkspaceGraphDocument.self, from: data)

        #expect(decoded.rootPath == report.rootPath)
        #expect(decoded.certainty == .metadataOnly)
        #expect(decoded.message == "Topology derived from discovered workspace contexts.")
        #expect(decoded.nodes.count == 3)
        #expect(decoded.edges.count == 2)
    }
}

private func sampleWorkspaceReport() -> WorkspaceReport {
    let dependencyReport = DependencyReport(
        projectPath: "/tmp/ContextA.xcodeproj",
        generatedAt: Date(timeIntervalSince1970: 0),
        resolvedFilePath: "/tmp/ContextA.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        resolvedFileStatus: .tracked,
        schemaVersion: SchemaInfo(version: 3, compatibility: .modern, message: "Schema version 3 is the modern Xcode 15+ format."),
        dependencies: [],
        findings: []
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
        findings: [],
        partialFailures: []
    )

    return WorkspaceReport(
        rootPath: "/tmp/MyWorkspace",
        generatedAt: Date(timeIntervalSince1970: 0),
        analysisMode: .auto,
        discoveredManifests: [
            DiscoveredManifest(path: "/tmp/ContextA.xcodeproj", kind: .xcodeproj, resolvedFilePath: dependencyReport.resolvedFilePath, ownershipKey: dependencyReport.resolvedFilePath)
        ],
        contexts: [contextReport],
        aggregateFindings: [],
        partialFailures: [],
        graphSummary: WorkspaceGraphSummary(certainty: .metadataOnly, message: "Topology derived from discovered workspace contexts.")
    )
}
