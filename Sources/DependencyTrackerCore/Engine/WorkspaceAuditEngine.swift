import Foundation

/// Coordinates aggregate workspace analysis while preserving the existing single-target engine.
public struct WorkspaceAuditEngine: Sendable {
    /// Shared configuration used to select discovery and audit behavior.
    public let configuration: TrackerConfiguration

    private let trackerEngine: TrackerEngine
    private let manifestIndex: ManifestIndex
    private let resolutionContextDetector: ResolutionContextDetector
    private let graphBuilder: WorkspaceGraphBuilder
    private let transitivePinAuditor: TransitivePinAuditor
    private let blastRadiusAnalyzer: BlastRadiusAnalyzer

    /// Creates a workspace engine backed by the supplied single-target engine.
    public init(
        configuration: TrackerConfiguration,
        trackerEngine: TrackerEngine? = nil,
        manifestIndex: ManifestIndex? = nil
    ) {
        self.configuration = configuration
        self.trackerEngine = trackerEngine ?? TrackerEngine(configuration: configuration)
        self.manifestIndex = manifestIndex ?? ManifestIndex(
            maxDepth: configuration.maxDiscoveryDepth,
            ignoreFileName: configuration.ignoreFileName
        )
        self.resolutionContextDetector = ResolutionContextDetector()
        self.graphBuilder = WorkspaceGraphBuilder()
        self.transitivePinAuditor = TransitivePinAuditor()
        self.blastRadiusAnalyzer = BlastRadiusAnalyzer()
    }

    /// Builds a workspace report for the supplied root path.
    public func analyze(rootPath: String) async throws -> WorkspaceReport {
        if shouldUseSingleTargetPath(for: rootPath) {
            return try await wrapSingleTarget(path: rootPath, analysisMode: configuration.analysisMode)
        }

        let discoveredManifests = try manifestIndex.discover(from: rootPath)
        guard !discoveredManifests.isEmpty else {
            throw DependencyTrackerError.invalidPath(rootPath)
        }

        let contexts = resolutionContextDetector.detect(from: discoveredManifests)
        var contextReports: [ResolutionContextReport] = []
        var aggregatePartialFailures: [PartialFailure] = []

        for context in contexts {
            let targetPath = context.resolvedFilePath ?? context.manifestPaths.first ?? context.displayPath

            do {
                let report = try await trackerEngine.analyze(projectPath: targetPath)
                contextReports.append(
                    ResolutionContextReport(
                        context: context,
                        reports: [report],
                        findings: report.findings,
                        partialFailures: []
                    )
                )
            } catch {
                guard configuration.continueOnPartialFailure else {
                    throw error
                }

                let failure = PartialFailure(
                    stage: .audit,
                    subjectPath: targetPath,
                    message: error.localizedDescription,
                    severity: .warning
                )
                contextReports.append(
                    ResolutionContextReport(
                        context: context,
                        reports: [],
                        findings: [],
                        partialFailures: [failure]
                    )
                )
                aggregatePartialFailures.append(failure)
            }
        }

        let sortedContextReports = contextReports.sorted { $0.context.displayPath < $1.context.displayPath }
        let graphSummary = makeGraphSummary(contextReports: sortedContextReports)
        let generatedAt = Date()
        let graphFindings = makeGraphFindings(
            rootPath: rootPath,
            generatedAt: generatedAt,
            contexts: sortedContextReports,
            graphSummary: graphSummary
        )

        return WorkspaceReport(
            rootPath: rootPath,
            generatedAt: generatedAt,
            analysisMode: configuration.analysisMode,
            discoveredManifests: discoveredManifests,
            contexts: sortedContextReports,
            aggregateFindings: graphFindings,
            partialFailures: aggregatePartialFailures.sorted { $0.subjectPath < $1.subjectPath },
            graphSummary: graphSummary
        )
    }

    /// Chooses whether a given input should stay on the single-target path.
    private func shouldUseSingleTargetPath(for rootPath: String) -> Bool {
        var isDirectory: ObjCBool = false
        let path = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return true
        }

        if !isDirectory.boolValue {
            return true
        }

        switch configuration.analysisMode {
        case .singleTarget:
            return true
        case .monorepo:
            return false
        case .auto:
            do {
                _ = try trackerEngine.locateAuditTarget(at: rootPath)
                return true
            } catch DependencyTrackerError.ambiguousProjectPath {
                return false
            } catch DependencyTrackerError.invalidPath {
                return false
            } catch {
                return true
            }
        }
    }

    /// Wraps the existing single-target engine output into one workspace report.
    private func wrapSingleTarget(path: String, analysisMode: AnalysisMode) async throws -> WorkspaceReport {
        let auditTarget = try trackerEngine.locateAuditTarget(at: path)
        let report = try await trackerEngine.analyze(projectPath: path)
        let discoveredPath = auditTarget.projectFileURL?.path
            ?? auditTarget.manifestURL?.path
            ?? auditTarget.resolvedFileURL.path
        let discovered = DiscoveredManifest(
            path: discoveredPath,
            kind: inferManifestKind(from: discoveredPath),
            resolvedFilePath: report.resolvedFilePath,
            ownershipKey: report.resolvedFilePath
        )
        let context = ResolutionContext(
            key: report.resolvedFilePath,
            displayPath: discoveredPath,
            resolvedFilePath: report.resolvedFilePath,
            manifestPaths: [discoveredPath]
        )
        let contextReport = ResolutionContextReport(
            context: context,
            reports: [report],
            findings: report.findings,
            partialFailures: []
        )

        let contextReports = [contextReport]
        let graphSummary = makeGraphSummary(contextReports: contextReports)
        let graphFindings = makeGraphFindings(
            rootPath: path,
            generatedAt: report.generatedAt,
            contexts: contextReports,
            graphSummary: graphSummary
        )

        return WorkspaceReport(
            rootPath: path,
            generatedAt: report.generatedAt,
            analysisMode: analysisMode,
            discoveredManifests: [discovered],
            contexts: contextReports,
            aggregateFindings: graphFindings,
            partialFailures: [],
            graphSummary: graphSummary
        )
    }

    /// Maps current single-target inputs into the discovery kinds expected by aggregate reporting.
    private func inferManifestKind(from path: String) -> DiscoveredManifestKind {
        if path.hasSuffix(".xcodeproj") {
            return .xcodeproj
        }
        if path.hasSuffix(".xcworkspace") {
            return .xcworkspace
        }
        if path.hasSuffix("Package.swift") {
            return .packageManifest
        }
        return .resolvedFile
    }

    /// Summarizes how much dependency-edge provenance the current workspace report can prove.
    private func makeGraphSummary(contextReports: [ResolutionContextReport]) -> WorkspaceGraphSummary {
        guard configuration.enableGraphEnrichment else {
            return WorkspaceGraphSummary(
                certainty: .metadataOnly,
                message: "Graph enrichment is disabled; output is limited to workspace, context, and manifest metadata."
            )
        }

        let dependencies = contextReports.flatMap { context in
            context.reports.flatMap(\.dependencies)
        }
        guard !dependencies.isEmpty else {
            return WorkspaceGraphSummary(
                certainty: .metadataOnly,
                message: "No resolved dependencies were available for dependency-edge graph enrichment."
            )
        }

        let dependenciesWithDeclarations = dependencies.filter { $0.declaredRequirement != nil }.count
        if dependenciesWithDeclarations == dependencies.count {
            return WorkspaceGraphSummary(
                certainty: .complete,
                message: "Every resolved dependency edge has declaration provenance from a manifest or Xcode project."
            )
        }

        return WorkspaceGraphSummary(
            certainty: .partiallyEnriched,
            message: "\(dependencies.count) \(edgeNoun(count: dependencies.count)) \(wereVerb(count: dependencies.count)) added; \(dependenciesWithDeclarations) \(haveVerb(count: dependenciesWithDeclarations)) direct declaration provenance."
        )
    }

    /// Grammar helpers keep graph summaries readable in CLI and AppKit surfaces.
    private func edgeNoun(count: Int) -> String {
        count == 1 ? "resolved dependency edge" : "resolved dependency edges"
    }

    private func wereVerb(count: Int) -> String {
        count == 1 ? "was" : "were"
    }

    private func haveVerb(count: Int) -> String {
        count == 1 ? "has" : "have"
    }

    /// Runs graph-aware analyzers only when dependency edges were actually produced.
    private func makeGraphFindings(
        rootPath: String,
        generatedAt: Date,
        contexts: [ResolutionContextReport],
        graphSummary: WorkspaceGraphSummary
    ) -> [Finding] {
        guard graphSummary.certainty != .metadataOnly else { return [] }
        let report = WorkspaceReport(
            rootPath: rootPath,
            generatedAt: generatedAt,
            analysisMode: configuration.analysisMode,
            discoveredManifests: [],
            contexts: contexts,
            aggregateFindings: [],
            partialFailures: [],
            graphSummary: graphSummary
        )
        let document = graphBuilder.makeDocument(from: report)
        return (transitivePinAuditor.analyze(document) + blastRadiusAnalyzer.analyze(document))
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return severityRank(lhs.severity) < severityRank(rhs.severity)
                }
                if lhs.category != rhs.category {
                    return lhs.category.rawValue < rhs.category.rawValue
                }
                return lhs.message < rhs.message
            }
    }

    /// Local severity ordering for graph findings.
    private func severityRank(_ severity: Severity) -> Int {
        switch severity {
        case .error: return 0
        case .warning: return 1
        case .info: return 2
        }
    }
}
