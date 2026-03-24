import Foundation

public struct GitIgnoreMatch: Codable, Hashable, Sendable {
    public let sourcePath: String
    public let line: Int
    public let pattern: String

    public init(sourcePath: String, line: Int, pattern: String) {
        self.sourcePath = sourcePath
        self.line = line
        self.pattern = pattern
    }

    public var summary: String {
        "\(pattern) (\(sourcePath):\(line))"
    }
}

public enum ResolvedFileStatus: Codable, Hashable, Sendable {
    case tracked
    case gitignored(match: GitIgnoreMatch)
    case untracked
    case missing

    public var isTracked: Bool {
        if case .tracked = self {
            return true
        }
        return false
    }
}

public enum SchemaCompatibility: String, Codable, Hashable, Sendable {
    case modern
    case legacy
    case unknown
}

public struct SchemaInfo: Codable, Hashable, Sendable {
    public let version: Int
    public let compatibility: SchemaCompatibility
    public let message: String

    public init(version: Int, compatibility: SchemaCompatibility, message: String) {
        self.version = version
        self.compatibility = compatibility
        self.message = message
    }
}

public enum UpdateType: String, Codable, Hashable, Sendable {
    case patch
    case minor
    case major
}

public struct OutdatedResult: Codable, Hashable, Sendable {
    public let pin: ResolvedPin
    public let latestVersion: String?
    public let updateType: UpdateType?
    public let isOutdated: Bool
    public let note: String?

    public init(pin: ResolvedPin, latestVersion: String?, updateType: UpdateType?, isOutdated: Bool, note: String? = nil) {
        self.pin = pin
        self.latestVersion = latestVersion
        self.updateType = updateType
        self.isOutdated = isOutdated
        self.note = note
    }
}

public enum StrategyRisk: String, Codable, Hashable, Sendable {
    case normal
    case elevated
    case environmentSensitive
}

public struct StrategyFinding: Codable, Hashable, Sendable {
    public let pin: ResolvedPin
    public let risk: StrategyRisk
    public let message: String

    public init(pin: ResolvedPin, risk: StrategyRisk, message: String) {
        self.pin = pin
        self.risk = risk
        self.message = message
    }
}

public struct DependencyAnalysis: Codable, Hashable, Sendable {
    public let pin: ResolvedPin
    public let outdated: OutdatedResult?
    public let strategyRisk: StrategyRisk

    public init(pin: ResolvedPin, outdated: OutdatedResult?, strategyRisk: StrategyRisk) {
        self.pin = pin
        self.outdated = outdated
        self.strategyRisk = strategyRisk
    }
}

public enum Severity: String, Codable, Hashable, Sendable {
    case info
    case warning
    case error
}

public enum FindingCategory: String, Codable, Hashable, Sendable {
    case gitTracking
    case schema
    case pinStrategy
    case outdated
}

public struct Finding: Codable, Hashable, Sendable {
    public let severity: Severity
    public let category: FindingCategory
    public let message: String
    public let recommendation: String

    public init(severity: Severity, category: FindingCategory, message: String, recommendation: String) {
        self.severity = severity
        self.category = category
        self.message = message
        self.recommendation = recommendation
    }
}

public struct DependencyReport: Codable, Sendable {
    public let projectPath: String
    public let generatedAt: Date
    public let resolvedFilePath: String
    public let resolvedFileStatus: ResolvedFileStatus
    public let schemaVersion: SchemaInfo
    public let dependencies: [DependencyAnalysis]
    public let findings: [Finding]

    public init(
        projectPath: String,
        generatedAt: Date,
        resolvedFilePath: String,
        resolvedFileStatus: ResolvedFileStatus,
        schemaVersion: SchemaInfo,
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

    public var hasActionableFindings: Bool {
        findings.contains { $0.severity != .info }
    }
}
