import Foundation

/// Records one non-fatal failure that occurred while building an aggregate workspace report.
public struct PartialFailure: Codable, Sendable, Equatable, Hashable {
    /// The stage that produced the failure.
    public let stage: PartialFailureStage
    /// The path or logical subject associated with the failure.
    public let subjectPath: String
    /// The user-visible failure summary.
    public let message: String
    /// The severity used when surfacing the partial failure in aggregate output.
    public let severity: Severity

    /// Creates a partial-failure record.
    public init(stage: PartialFailureStage, subjectPath: String, message: String, severity: Severity) {
        self.stage = stage
        self.subjectPath = subjectPath
        self.message = message
        self.severity = severity
    }
}

/// Classifies the pipeline stage that produced a partial failure.
public enum PartialFailureStage: String, Codable, Sendable, Equatable, Hashable {
    case discovery
    case ownership
    case contextDetection
    case audit
    case declaredRequirements
    case graphEnrichment
    case reporting
}

/// Describes one auditable manifest or resolved-file source discovered beneath a workspace root.
public struct DiscoveredManifest: Codable, Sendable, Equatable, Hashable {
    /// The canonical path to the discovered item.
    public let path: String
    /// The source kind found on disk.
    public let kind: DiscoveredManifestKind
    /// The resolved file path that owns the discovered item when available.
    public let resolvedFilePath: String?
    /// The canonical ownership key used to deduplicate equivalent sources.
    public let ownershipKey: String?

    /// Creates a discovered-manifest record.
    public init(path: String, kind: DiscoveredManifestKind, resolvedFilePath: String?, ownershipKey: String?) {
        self.path = path
        self.kind = kind
        self.resolvedFilePath = resolvedFilePath
        self.ownershipKey = ownershipKey
    }
}

/// Enumerates the source kinds the workspace scanner can discover.
public enum DiscoveredManifestKind: String, Codable, Sendable, Equatable, Hashable {
    case xcodeproj
    case xcworkspace
    case packageManifest
    case resolvedFile
}

/// Groups discovered manifests that share one effective dependency resolution outcome.
public struct ResolutionContext: Codable, Sendable, Equatable, Hashable {
    /// A stable key for joining manifests, reports, and drift findings within this context.
    public let key: String
    /// The path that best describes the context to users.
    public let displayPath: String
    /// The resolved-file path that anchors the context when one exists.
    public let resolvedFilePath: String?
    /// The manifests or sources that belong to this context.
    public let manifestPaths: [String]

    /// Creates a resolution-context description.
    public init(key: String, displayPath: String, resolvedFilePath: String?, manifestPaths: [String]) {
        self.key = key
        self.displayPath = displayPath
        self.resolvedFilePath = resolvedFilePath
        self.manifestPaths = manifestPaths
    }
}

/// Summarizes whether graph output is complete, partial, or metadata-only.
public struct WorkspaceGraphSummary: Codable, Sendable, Equatable, Hashable {
    /// The certainty level for the current graph payload.
    public let certainty: WorkspaceGraphCertainty
    /// A short description suitable for CLI and app summary surfaces.
    public let message: String

    /// Creates a graph summary.
    public init(certainty: WorkspaceGraphCertainty, message: String) {
        self.certainty = certainty
        self.message = message
    }
}

/// Describes how trustworthy the current workspace graph is.
public enum WorkspaceGraphCertainty: String, Codable, Sendable, Equatable, Hashable {
    case metadataOnly
    case partiallyEnriched
    case complete
}

/// Carries the report and derived findings for one resolution context.
public struct ResolutionContextReport: Codable, Sendable {
    /// The context being described.
    public let context: ResolutionContext
    /// The single-target reports produced for this context.
    public let reports: [DependencyReport]
    /// Context-specific aggregate findings.
    public let findings: [Finding]
    /// Non-fatal failures encountered while evaluating this context.
    public let partialFailures: [PartialFailure]

    /// Creates a context report.
    public init(
        context: ResolutionContext,
        reports: [DependencyReport],
        findings: [Finding],
        partialFailures: [PartialFailure]
    ) {
        self.context = context
        self.reports = reports
        self.findings = findings
        self.partialFailures = partialFailures
    }
}

/// The aggregate output of a workspace-level dependency audit.
public struct WorkspaceReport: Codable, Sendable {
    /// The root path used to seed workspace discovery.
    public let rootPath: String
    /// The timestamp at which the aggregate report was assembled.
    public let generatedAt: Date
    /// The analysis mode used to construct the report.
    public let analysisMode: AnalysisMode
    /// The manifests and sources discovered beneath the root.
    public let discoveredManifests: [DiscoveredManifest]
    /// The inferred resolution contexts.
    public let contexts: [ResolutionContextReport]
    /// Findings that apply to the workspace as a whole.
    public let aggregateFindings: [Finding]
    /// Non-fatal failures encountered across the workspace pipeline.
    public let partialFailures: [PartialFailure]
    /// Summary metadata for graph outputs when graph enrichment ran.
    public let graphSummary: WorkspaceGraphSummary?

    /// Creates a workspace report from discovery, context, and aggregate outputs.
    public init(
        rootPath: String,
        generatedAt: Date,
        analysisMode: AnalysisMode,
        discoveredManifests: [DiscoveredManifest],
        contexts: [ResolutionContextReport],
        aggregateFindings: [Finding],
        partialFailures: [PartialFailure],
        graphSummary: WorkspaceGraphSummary? = nil
    ) {
        self.rootPath = rootPath
        self.generatedAt = generatedAt
        self.analysisMode = analysisMode
        self.discoveredManifests = discoveredManifests
        self.contexts = contexts
        self.aggregateFindings = aggregateFindings
        self.partialFailures = partialFailures
        self.graphSummary = graphSummary
    }

    /// Indicates whether the workspace report contains warnings or errors that should affect exits.
    public var hasActionableFindings: Bool {
        aggregateFindings.contains(where: \.isActionable)
            || contexts.contains(where: { $0.findings.contains(where: \.isActionable) })
            || partialFailures.contains(where: { $0.severity != .info })
            || contexts.contains(where: { $0.partialFailures.contains(where: { $0.severity != .info }) })
    }
}
