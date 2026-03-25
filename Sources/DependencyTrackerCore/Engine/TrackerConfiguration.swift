import Foundation

/// Controls which audits run and how aggressively external checks execute.
public struct TrackerConfiguration: Codable, Sendable, Equatable, Hashable {
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

    /// Creates a configuration for a dependency audit run.
    public init(
        checkOutdated: Bool = true,
        checkGitTracking: Bool = true,
        checkDeclaredConstraints: Bool = true,
        strictConstraints: Bool = false,
        concurrentFetchLimit: Int = 8,
        timeout: TimeInterval = 30
    ) {
        self.checkOutdated = checkOutdated
        self.checkGitTracking = checkGitTracking
        self.checkDeclaredConstraints = checkDeclaredConstraints
        self.strictConstraints = strictConstraints
        self.concurrentFetchLimit = concurrentFetchLimit
        self.timeout = timeout
    }
}
