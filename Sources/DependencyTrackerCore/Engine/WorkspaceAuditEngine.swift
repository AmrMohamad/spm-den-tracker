import Foundation

/// Coordinates aggregate workspace analysis while preserving the existing single-target engine.
public struct WorkspaceAuditEngine: Sendable {
    /// Shared configuration used to select discovery and audit behavior.
    public let configuration: TrackerConfiguration

    private let trackerEngine: TrackerEngine
    /// Creates a workspace engine backed by the supplied single-target engine.
    public init(
        configuration: TrackerConfiguration,
        trackerEngine: TrackerEngine? = nil
    ) {
        self.configuration = configuration
        self.trackerEngine = trackerEngine ?? TrackerEngine(configuration: configuration)
    }

    /// Builds a workspace report for the supplied root path.
    public func analyze(rootPath: String) async throws -> WorkspaceReport {
        if shouldUseSingleTargetPath(for: rootPath) {
            return try await wrapSingleTarget(path: rootPath, analysisMode: configuration.analysisMode)
        }
        throw DependencyTrackerError.invalidPath(rootPath)
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

        return WorkspaceReport(
            rootPath: path,
            generatedAt: report.generatedAt,
            analysisMode: analysisMode,
            discoveredManifests: [discovered],
            contexts: [contextReport],
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
