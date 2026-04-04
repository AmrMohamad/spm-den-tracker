import Foundation
import Testing
@testable import DependencyTrackerCore

struct AggregateAuditDriftTests {
    @Test
    func crossManifestAnalyzerFlagsSameMajorAsWarning() {
        let findings = CrossManifestConstraintDriftAnalyzer().analyze([
            contextReport(
                contextKey: "workspace-a",
                displayPath: "/repo/Features/Auth",
                reportPath: "/repo/Features/Auth/Package.swift",
                identity: "alamofire",
                declaredRequirement: .init(
                    identity: "alamofire",
                    source: .packageManifest,
                    kind: .upToNextMajor,
                    lowerBound: "5.9.1",
                    location: "https://example.com/alamofire.git",
                    description: "from 5.9.1"
                ),
                pin: .version("5.9.1", revision: "abc")
            ),
            contextReport(
                contextKey: "workspace-b",
                displayPath: "/repo/Features/Payments",
                reportPath: "/repo/Features/Payments/Package.swift",
                identity: "alamofire",
                declaredRequirement: .init(
                    identity: "alamofire",
                    source: .packageManifest,
                    kind: .upToNextMinor,
                    lowerBound: "5.10.0",
                    location: "https://example.com/alamofire.git",
                    description: "upToNextMinor 5.10.0"
                ),
                pin: .version("5.10.0", revision: "def")
            )
        ])

        #expect(findings.count == 1)
        #expect(findings[0].severity == .warning)
        #expect(findings[0].category == .declaredConstraint)
        #expect(findings[0].message.contains("/repo/Features/Auth/Package.swift"))
        #expect(findings[0].message.contains("/repo/Features/Payments/Package.swift"))
    }

    @Test
    func crossManifestAnalyzerFlagsCrossMajorAsError() {
        let findings = CrossManifestConstraintDriftAnalyzer().analyze([
            contextReport(
                contextKey: "workspace-a",
                displayPath: "/repo/Core",
                reportPath: "/repo/Core/Package.swift",
                identity: "protobuf",
                declaredRequirement: .init(
                    identity: "protobuf",
                    source: .packageManifest,
                    kind: .exact,
                    lowerBound: "1.2.3",
                    upperBound: "1.2.3",
                    location: "https://example.com/protobuf.git",
                    description: "exact 1.2.3"
                ),
                pin: .version("1.2.3", revision: "abc")
            ),
            contextReport(
                contextKey: "workspace-b",
                displayPath: "/repo/Shared",
                reportPath: "/repo/Shared/Package.swift",
                identity: "protobuf",
                declaredRequirement: .init(
                    identity: "protobuf",
                    source: .packageManifest,
                    kind: .exact,
                    lowerBound: "2.0.0",
                    upperBound: "2.0.0",
                    location: "https://example.com/protobuf.git",
                    description: "exact 2.0.0"
                ),
                pin: .version("2.0.0", revision: "def")
            )
        ])

        #expect(findings.count == 1)
        #expect(findings[0].severity == .error)
        #expect(findings[0].category == .declaredConstraint)
    }

    @Test
    func crossContextAnalyzerFlagsSameMajorAsWarning() {
        let findings = CrossContextResolvedDriftAnalyzer().analyze([
            contextReport(
                contextKey: "workspace-a",
                displayPath: "/repo/Features/Auth",
                reportPath: "/repo/Features/Auth/Package.swift",
                identity: "alamofire",
                declaredRequirement: nil,
                pin: .version("5.9.1", revision: "abc")
            ),
            contextReport(
                contextKey: "workspace-b",
                displayPath: "/repo/Features/Payments",
                reportPath: "/repo/Features/Payments/Package.swift",
                identity: "alamofire",
                declaredRequirement: nil,
                pin: .version("5.10.0", revision: "def")
            )
        ])

        #expect(findings.count == 1)
        #expect(findings[0].severity == .warning)
        #expect(findings[0].category == .pinStrategy)
        #expect(findings[0].message.contains("resolves differently across contexts"))
    }

    @Test
    func crossContextAnalyzerFlagsMajorOrStrategyMismatchAsError() {
        let findings = CrossContextResolvedDriftAnalyzer().analyze([
            contextReport(
                contextKey: "workspace-a",
                displayPath: "/repo/Features/Auth",
                reportPath: "/repo/Features/Auth/Package.swift",
                identity: "graphql",
                declaredRequirement: nil,
                pin: .version("1.2.3", revision: "abc")
            ),
            contextReport(
                contextKey: "workspace-b",
                displayPath: "/repo/Features/Payments",
                reportPath: "/repo/Features/Payments/Package.swift",
                identity: "graphql",
                declaredRequirement: nil,
                pin: .branch("main", revision: "def")
            )
        ])

        #expect(findings.count == 1)
        #expect(findings[0].severity == .error)
        #expect(findings[0].category == .pinStrategy)
    }

    @Test
    func workspaceAssemblerProducesDeterministicWorkspaceReport() {
        let discovered = [
            DiscoveredManifest(path: "/repo/Features/Auth/Package.swift", kind: .packageManifest, resolvedFilePath: "/repo/Features/Auth/Package.resolved", ownershipKey: "/repo/Features/Auth/Package.resolved"),
            DiscoveredManifest(path: "/repo/Features/Payments/Package.swift", kind: .packageManifest, resolvedFilePath: "/repo/Features/Payments/Package.resolved", ownershipKey: "/repo/Features/Payments/Package.resolved")
        ]

        let contextReports = [
            contextReport(
                contextKey: "workspace-b",
                displayPath: "/repo/Features/Payments",
                reportPath: "/repo/Features/Payments/Package.swift",
                identity: "alamofire",
                declaredRequirement: nil,
                pin: .version("5.10.0", revision: "def")
            ),
            contextReport(
                contextKey: "workspace-a",
                displayPath: "/repo/Features/Auth",
                reportPath: "/repo/Features/Auth/Package.swift",
                identity: "alamofire",
                declaredRequirement: nil,
                pin: .version("5.9.1", revision: "abc")
            )
        ]

        let workspace = WorkspaceReportAssembler().assemble(
            rootPath: "/repo",
            generatedAt: Date(timeIntervalSince1970: 0),
            analysisMode: .monorepo,
            discoveredManifests: discovered,
            contextReports: contextReports,
            aggregateFindings: [
                Finding(
                    severity: .warning,
                    category: .declaredConstraint,
                    message: "first",
                    recommendation: "keep"
                ),
                Finding(
                    severity: .error,
                    category: .pinStrategy,
                    message: "second",
                    recommendation: "fix"
                )
            ],
            partialFailures: [
                PartialFailure(stage: .audit, subjectPath: "/repo/Features/Auth", message: "audit failed", severity: .warning),
                PartialFailure(stage: .discovery, subjectPath: "/repo/Features/Payments", message: "discovery failed", severity: .error)
            ],
            graphSummary: WorkspaceGraphSummary(certainty: .metadataOnly, message: "metadata only")
        )

        #expect(workspace.rootPath == "/repo")
        #expect(workspace.analysisMode == .monorepo)
        #expect(workspace.discoveredManifests.map(\.path) == [
            "/repo/Features/Auth/Package.swift",
            "/repo/Features/Payments/Package.swift"
        ])
        #expect(workspace.contexts.map(\.context.key) == ["workspace-a", "workspace-b"])
        #expect(workspace.aggregateFindings.map(\.message) == ["second", "first"])
        #expect(workspace.partialFailures.map(\.subjectPath) == ["/repo/Features/Payments", "/repo/Features/Auth"])
        #expect(workspace.graphSummary?.certainty == .metadataOnly)
    }
}

private func contextReport(
    contextKey: String,
    displayPath: String,
    reportPath: String,
    identity: String,
    declaredRequirement: DeclaredRequirement?,
    pin: PinState
) -> ResolutionContextReport {
    let resolvedPin = ResolvedPin(identity: identity, kind: .remoteSourceControl, location: "https://example.com/\(identity).git", state: pin)
    let dependency = DependencyAnalysis(
        pin: resolvedPin,
        outdated: nil,
        strategyRisk: .normal,
        declaredRequirement: declaredRequirement,
        constraintDrift: .declarationUnavailable,
        latestAllowedVersion: nil
    )
    let report = DependencyReport(
        projectPath: reportPath,
        generatedAt: Date(timeIntervalSince1970: 0),
        resolvedFilePath: reportPath.replacingOccurrences(of: "Package.swift", with: "Package.resolved"),
        resolvedFileStatus: .tracked,
        schemaVersion: SchemaInfo(version: 3, compatibility: .modern, message: "Schema version 3 is the modern Xcode 15+ format."),
        dependencies: [dependency],
        findings: []
    )
    return ResolutionContextReport(
        context: ResolutionContext(
            key: contextKey,
            displayPath: displayPath,
            resolvedFilePath: report.resolvedFilePath,
            manifestPaths: [reportPath]
        ),
        reports: [report],
        findings: [],
        partialFailures: []
    )
}
