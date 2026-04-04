import Foundation

/// Controls which audits run and how aggressively external checks execute.
public struct TrackerConfiguration: Codable, Sendable, Equatable, Hashable {
    /// Controls whether inputs are treated as one target or a recursively discovered workspace.
    public var analysisMode: AnalysisMode
    /// Enables upstream tag lookups to detect available dependency updates.
    public var checkOutdated: Bool
    /// Enables git tracking checks for `Package.resolved`.
    public var checkGitTracking: Bool
    /// Enables declared requirement parsing and drift analysis.
    public var checkDeclaredConstraints: Bool
    /// Promotes declared-constraint findings into actionable failures when enabled.
    public var strictConstraints: Bool
    /// Caps the number of concurrent remote tag lookups.
    public var concurrentFetchLimit: Int
    /// Sets the per-process timeout for git commands.
    public var timeout: TimeInterval
    /// Caps recursive workspace discovery depth for monorepo analysis.
    public var maxDiscoveryDepth: Int
    /// Names the repo-root ignore file that augments built-in discovery excludes.
    public var ignoreFileName: String
    /// Enables graph enrichment work such as show-dependencies loading.
    public var enableGraphEnrichment: Bool
    /// Controls whether aggregate analysis records non-fatal failures instead of aborting early.
    public var continueOnPartialFailure: Bool

    /// Creates a configuration for a dependency audit run.
    public init(
        analysisMode: AnalysisMode = .singleTarget,
        checkOutdated: Bool = true,
        checkGitTracking: Bool = true,
        checkDeclaredConstraints: Bool = true,
        strictConstraints: Bool = false,
        concurrentFetchLimit: Int = 8,
        timeout: TimeInterval = 30,
        maxDiscoveryDepth: Int = 10,
        ignoreFileName: String = ".spm-dep-tracker-ignore",
        enableGraphEnrichment: Bool = true,
        continueOnPartialFailure: Bool = true
    ) {
        self.analysisMode = analysisMode
        self.checkOutdated = checkOutdated
        self.checkGitTracking = checkGitTracking
        self.checkDeclaredConstraints = checkDeclaredConstraints
        self.strictConstraints = strictConstraints
        self.concurrentFetchLimit = concurrentFetchLimit
        self.timeout = timeout
        self.maxDiscoveryDepth = maxDiscoveryDepth
        self.ignoreFileName = ignoreFileName
        self.enableGraphEnrichment = enableGraphEnrichment
        self.continueOnPartialFailure = continueOnPartialFailure
    }
}
