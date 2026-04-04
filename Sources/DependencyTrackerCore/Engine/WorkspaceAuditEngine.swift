import Foundation

/// Coordinates aggregate workspace analysis while preserving the existing single-target engine.
public struct WorkspaceAuditEngine: Sendable {
    /// Shared configuration used to select discovery and audit behavior.
    public let configuration: TrackerConfiguration

    private let trackerEngine: TrackerEngine
    private let manifestIndex: ManifestIndex
    private let resolutionContextDetector: ResolutionContextDetector
    private let workspaceReportAssembler: WorkspaceReportAssembler
    private let crossManifestConstraintDriftAnalyzer: CrossManifestConstraintDriftAnalyzer
    private let crossContextResolvedDriftAnalyzer: CrossContextResolvedDriftAnalyzer

    /// Creates a workspace engine backed by the supplied single-target engine.
    public init(
        configuration: TrackerConfiguration,
        trackerEngine: TrackerEngine? = nil,
        manifestIndex: ManifestIndex? = nil
    ) {
        self.init(
            configuration: configuration,
            trackerEngine: trackerEngine,
            manifestIndex: manifestIndex,
            resolutionContextDetector: ResolutionContextDetector(),
            workspaceReportAssembler: WorkspaceReportAssembler(),
            crossManifestConstraintDriftAnalyzer: CrossManifestConstraintDriftAnalyzer(),
            crossContextResolvedDriftAnalyzer: CrossContextResolvedDriftAnalyzer()
        )
    }

    /// Internal dependency-injection initializer used by tests and integration seams.
    init(
        configuration: TrackerConfiguration,
        trackerEngine: TrackerEngine? = nil,
        manifestIndex: ManifestIndex? = nil,
        resolutionContextDetector: ResolutionContextDetector = ResolutionContextDetector(),
        workspaceReportAssembler: WorkspaceReportAssembler = WorkspaceReportAssembler(),
        crossManifestConstraintDriftAnalyzer: CrossManifestConstraintDriftAnalyzer = CrossManifestConstraintDriftAnalyzer(),
        crossContextResolvedDriftAnalyzer: CrossContextResolvedDriftAnalyzer = CrossContextResolvedDriftAnalyzer()
    ) {
        self.configuration = configuration
        self.trackerEngine = trackerEngine ?? TrackerEngine(configuration: configuration)
        self.manifestIndex = manifestIndex ?? ManifestIndex(
            maxDepth: configuration.maxDiscoveryDepth,
            ignoreFileName: configuration.ignoreFileName
        )
        self.resolutionContextDetector = resolutionContextDetector
        self.workspaceReportAssembler = workspaceReportAssembler
        self.crossManifestConstraintDriftAnalyzer = crossManifestConstraintDriftAnalyzer
        self.crossContextResolvedDriftAnalyzer = crossContextResolvedDriftAnalyzer
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

        let aggregateFindings =
            crossManifestConstraintDriftAnalyzer.analyze(contextReports)
            + crossContextResolvedDriftAnalyzer.analyze(contextReports)

        return workspaceReportAssembler.assemble(
            rootPath: rootPath,
            generatedAt: Date(),
            analysisMode: configuration.analysisMode,
            discoveredManifests: discoveredManifests,
            contextReports: contextReports,
            aggregateFindings: aggregateFindings,
            partialFailures: aggregatePartialFailures
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
            return false
        }
    }

    /// Wraps the existing single-target engine output into one workspace report.
    private func wrapSingleTarget(path: String, analysisMode: AnalysisMode) async throws -> WorkspaceReport {
        let report = try await trackerEngine.analyze(projectPath: path)
        let discovered = DiscoveredManifest(
            path: report.projectPath,
            kind: inferManifestKind(from: report.projectPath),
            resolvedFilePath: report.resolvedFilePath,
            ownershipKey: report.resolvedFilePath
        )
        let context = ResolutionContext(
            key: report.resolvedFilePath,
            displayPath: report.projectPath,
            resolvedFilePath: report.resolvedFilePath,
            manifestPaths: [report.projectPath]
        )
        let contextReport = ResolutionContextReport(
            context: context,
            reports: [report],
            findings: report.findings,
            partialFailures: []
        )

        return workspaceReportAssembler.assemble(
            rootPath: path,
            generatedAt: report.generatedAt,
            analysisMode: analysisMode,
            discoveredManifests: [discovered],
            contextReports: [contextReport],
            aggregateFindings: [],
            partialFailures: []
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
}
