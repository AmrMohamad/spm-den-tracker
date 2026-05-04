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
        #expect(output.contains("contains [manifestDiscovery]"))
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
        #expect(decoded.edges.allSatisfy { $0.provenance.source != .packageResolved })
    }

    @Test
    func enrichedJsonCarriesDependencyEdgesAndProvenance() throws {
        let report = sampleWorkspaceReport(
            dependencies: [
                sampleDependency(identity: "alamofire", declaredRequirement: sampleRequirement(identity: "alamofire")),
                sampleDependency(identity: "swift-log"),
            ],
            graphSummary: WorkspaceGraphSummary(
                certainty: .partiallyEnriched,
                message: "2 resolved dependency edges were added; 1 has direct declaration provenance."
            )
        )
        let output = WorkspaceGraphRenderer().render(report, format: .json)
        let data = Data(output.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkspaceGraphDocument.self, from: data)

        #expect(decoded.certainty == .partiallyEnriched)
        #expect(decoded.nodes.contains { $0.kind == "dependency" && $0.metadata["identity"] == "alamofire" })
        #expect(decoded.edges.contains { $0.label == "resolves 5.9.1" && $0.provenance.source == .packageResolved })
        #expect(decoded.edges.contains { $0.label == "declares upToNextMajor" && $0.provenance.source == .packageManifest })
    }

    @Test
    func graphAnalyzersReportBlastRadiusAndTransitivePins() {
        let document = WorkspaceGraphBuilder().makeDocument(
            from: sampleMultiContextReport(
                dependency: sampleDependency(identity: "shared-kit"),
                graphSummary: WorkspaceGraphSummary(
                    certainty: .partiallyEnriched,
                    message: "2 resolved dependency edges were added; 0 have direct declaration provenance."
                )
            )
        )

        let transitiveFindings = TransitivePinAuditor().analyze(document)
        let blastFindings = BlastRadiusAnalyzer().analyze(document)

        #expect(transitiveFindings.count == 2)
        #expect(transitiveFindings.allSatisfy { $0.category == .graph })
        #expect(blastFindings.count == 1)
        #expect(blastFindings[0].message.contains("shared-kit"))
        #expect(blastFindings[0].message.contains("2 workspace contexts"))
    }
}

private func sampleWorkspaceReport(
    dependencies: [DependencyAnalysis] = [],
    graphSummary: WorkspaceGraphSummary = WorkspaceGraphSummary(
        certainty: .metadataOnly,
        message: "Topology derived from discovered workspace contexts."
    )
) -> WorkspaceReport {
    let dependencyReport = DependencyReport(
        projectPath: "/tmp/ContextA.xcodeproj",
        generatedAt: Date(timeIntervalSince1970: 0),
        resolvedFilePath: "/tmp/ContextA.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        resolvedFileStatus: .tracked,
        schemaVersion: SchemaInfo(version: 3, compatibility: .modern, message: "Schema version 3 is the modern Xcode 15+ format."),
        dependencies: dependencies,
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
        graphSummary: graphSummary
    )
}

private func sampleMultiContextReport(
    dependency: DependencyAnalysis,
    graphSummary: WorkspaceGraphSummary
) -> WorkspaceReport {
    func contextReport(name: String) -> ResolutionContextReport {
        let dependencyReport = DependencyReport(
            projectPath: "/tmp/\(name)/Package.swift",
            generatedAt: Date(timeIntervalSince1970: 0),
            resolvedFilePath: "/tmp/\(name)/Package.resolved",
            resolvedFileStatus: .tracked,
            schemaVersion: SchemaInfo(version: 3, compatibility: .modern, message: "Schema version 3 is the modern Xcode 15+ format."),
            dependencies: [dependency],
            findings: []
        )
        let context = ResolutionContext(
            key: name,
            displayPath: name,
            resolvedFilePath: dependencyReport.resolvedFilePath,
            manifestPaths: [dependencyReport.projectPath]
        )
        return ResolutionContextReport(context: context, reports: [dependencyReport], findings: [], partialFailures: [])
    }

    return WorkspaceReport(
        rootPath: "/tmp/MyWorkspace",
        generatedAt: Date(timeIntervalSince1970: 0),
        analysisMode: .auto,
        discoveredManifests: [],
        contexts: [contextReport(name: "App"), contextReport(name: "Tools")],
        aggregateFindings: [],
        partialFailures: [],
        graphSummary: graphSummary
    )
}

private func sampleDependency(identity: String, declaredRequirement: DeclaredRequirement? = nil) -> DependencyAnalysis {
    let pin = ResolvedPin(
        identity: identity,
        kind: .remoteSourceControl,
        location: "https://github.com/example/\(identity).git",
        state: .version("5.9.1", revision: "abc123")
    )
    return DependencyAnalysis(
        pin: pin,
        outdated: nil,
        strategyRisk: .normal,
        declaredRequirement: declaredRequirement,
        constraintDrift: declaredRequirement == nil ? .declarationUnavailable : .currentIsLatestAllowed,
        latestAllowedVersion: declaredRequirement == nil ? nil : "5.9.1"
    )
}

private func sampleRequirement(identity: String) -> DeclaredRequirement {
    DeclaredRequirement(
        identity: identity,
        source: .packageManifest,
        kind: .upToNextMajor,
        lowerBound: "5.0.0",
        upperBound: "6.0.0",
        location: "https://github.com/example/\(identity).git",
        description: "from: 5.0.0"
    )
}
