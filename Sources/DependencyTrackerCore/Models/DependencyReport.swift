import Foundation

/// Describes the `.gitignore` rule that matched `Package.resolved`.
public struct GitIgnoreMatch: Codable, Hashable, Sendable {
    /// The ignore file that contributed the matching rule.
    public let sourcePath: String
    /// The one-based line number of the matching rule.
    public let line: Int
    /// The raw ignore pattern reported by `git check-ignore -v`.
    public let pattern: String

    /// Creates a gitignore match record from the parsed command output.
    public init(sourcePath: String, line: Int, pattern: String) {
        self.sourcePath = sourcePath
        self.line = line
        self.pattern = pattern
    }

    /// Returns a single-line summary suitable for CLI output.
    public var summary: String {
        "\(pattern) (\(sourcePath):\(line))"
    }
}

/// Records how the resolved lockfile relates to the current git repository.
public enum ResolvedFileStatus: Codable, Hashable, Sendable {
    /// The file exists and is tracked by git.
    case tracked
    /// The file exists but is ignored by a specific gitignore rule.
    case gitignored(match: GitIgnoreMatch)
    /// The file exists but is not tracked or ignored.
    case untracked
    /// The file does not exist at the expected location.
    case missing

    /// Indicates whether the status represents the desired tracked state.
    public var isTracked: Bool {
        if case .tracked = self {
            return true
        }
        return false
    }
}

/// Groups schema versions into stability and tooling-compatibility buckets.
public enum SchemaCompatibility: String, Codable, Hashable, Sendable {
    case modern
    case legacy
    case unknown
}

/// Summarizes the detected `Package.resolved` schema version.
public struct SchemaInfo: Codable, Hashable, Sendable {
    /// The raw schema version integer stored in the file.
    public let version: Int
    /// The compatibility class inferred from the schema version.
    public let compatibility: SchemaCompatibility
    /// The human-readable explanation shown in findings and reports.
    public let message: String

    /// Creates schema metadata for a resolved file.
    public init(version: Int, compatibility: SchemaCompatibility, message: String) {
        self.version = version
        self.compatibility = compatibility
        self.message = message
    }
}

/// Describes the semantic-version impact of an available update.
public enum UpdateType: String, Codable, Hashable, Sendable {
    case patch
    case minor
    case major
}

/// Explains why an outdated check produced an informational note instead of a clean comparison.
public enum OutdatedNoteKind: String, Codable, Hashable, Sendable {
    case remoteLookupFailure
    case noStableSemanticTags
    case nonSemanticResolvedVersion
}

/// Captures the latest-version assessment for a single dependency pin.
public struct OutdatedResult: Codable, Hashable, Sendable {
    /// The dependency that was evaluated.
    public let pin: ResolvedPin
    /// The latest stable upstream version when one could be inferred.
    public let latestVersion: String?
    /// The major/minor/patch classification when an update is available.
    public let updateType: UpdateType?
    /// Indicates whether the dependency is behind the latest stable semantic tag.
    public let isOutdated: Bool
    /// The structured reason a comparison was partial or informational.
    public let noteKind: OutdatedNoteKind?
    /// The human-readable note paired with `noteKind`.
    public let note: String?

    /// Creates the outdated-check result for a dependency.
    public init(
        pin: ResolvedPin,
        latestVersion: String?,
        updateType: UpdateType?,
        isOutdated: Bool,
        noteKind: OutdatedNoteKind? = nil,
        note: String? = nil
    ) {
        self.pin = pin
        self.latestVersion = latestVersion
        self.updateType = updateType
        self.isOutdated = isOutdated
        self.noteKind = noteKind
        self.note = note
    }
}

/// Classifies how risky a pinning strategy is for reproducible shared builds.
public enum StrategyRisk: String, Codable, Hashable, Sendable {
    case normal
    case elevated
    case environmentSensitive
}

/// Records the strategy audit outcome for one dependency.
public struct StrategyFinding: Codable, Hashable, Sendable {
    /// The dependency that was assessed.
    public let pin: ResolvedPin
    /// The risk level assigned to the pinning strategy.
    public let risk: StrategyRisk
    /// The human-readable explanation used in reports.
    public let message: String

    /// Creates a strategy finding for a dependency pin.
    public init(pin: ResolvedPin, risk: StrategyRisk, message: String) {
        self.pin = pin
        self.risk = risk
        self.message = message
    }
}

/// Merges the raw pin with its derived audit outputs.
public struct DependencyAnalysis: Codable, Hashable, Sendable {
    /// The dependency pin read from `Package.resolved`.
    public let pin: ResolvedPin
    /// The optional update assessment for the dependency.
    public let outdated: OutdatedResult?
    /// The risk class of the dependency's pinning strategy.
    public let strategyRisk: StrategyRisk

    /// Creates the combined analysis row shown by reporters and the app.
    public init(pin: ResolvedPin, outdated: OutdatedResult?, strategyRisk: StrategyRisk) {
        self.pin = pin
        self.outdated = outdated
        self.strategyRisk = strategyRisk
    }
}

/// Defines the user-visible severity ordering for findings.
public enum Severity: String, Codable, Hashable, Sendable {
    case info
    case warning
    case error
}

/// Groups findings by the subsystem that produced them.
public enum FindingCategory: String, Codable, Hashable, Sendable {
    case gitTracking
    case schema
    case pinStrategy
    case outdated
}

/// Represents one actionable or informational audit finding.
public struct Finding: Codable, Hashable, Sendable {
    /// The severity used for sorting and rendering emphasis.
    public let severity: Severity
    /// The subsystem that emitted the finding.
    public let category: FindingCategory
    /// The issue summary shown to users.
    public let message: String
    /// The recommended follow-up action for the issue.
    public let recommendation: String

    /// Creates a finding to include in the final report.
    public init(severity: Severity, category: FindingCategory, message: String, recommendation: String) {
        self.severity = severity
        self.category = category
        self.message = message
        self.recommendation = recommendation
    }
}

/// The complete output of a dependency audit run.
public struct DependencyReport: Codable, Sendable {
    /// The user-provided project path that seeded the audit.
    public let projectPath: String
    /// The timestamp at which the report was assembled.
    public let generatedAt: Date
    /// The resolved file path the engine targeted.
    public let resolvedFilePath: String
    /// The git-tracking state of the resolved file.
    public let resolvedFileStatus: ResolvedFileStatus
    /// The parsed schema metadata when the resolved file exists.
    public let schemaVersion: SchemaInfo?
    /// The per-dependency analysis rows sorted for output.
    public let dependencies: [DependencyAnalysis]
    /// The aggregated findings derived from the audit passes.
    public let findings: [Finding]

    /// Creates a report from the outputs of the audit pipeline.
    public init(
        projectPath: String,
        generatedAt: Date,
        resolvedFilePath: String,
        resolvedFileStatus: ResolvedFileStatus,
        schemaVersion: SchemaInfo?,
        dependencies: [DependencyAnalysis],
        findings: [Finding]
    ) {
        self.projectPath = projectPath
        self.generatedAt = generatedAt
        self.resolvedFilePath = resolvedFilePath
        self.resolvedFileStatus = resolvedFileStatus
        self.schemaVersion = schemaVersion
        self.dependencies = dependencies
        self.findings = findings
    }

    /// Indicates whether the report contains warnings or errors that should influence exit codes.
    public var hasActionableFindings: Bool {
        findings.contains { $0.severity != .info }
    }
}
