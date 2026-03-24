import Foundation

public struct TrackerConfiguration: Codable, Sendable, Equatable, Hashable {
    public var checkOutdated: Bool
    public var checkGitTracking: Bool
    public var concurrentFetchLimit: Int
    public var timeout: TimeInterval

    public init(
        checkOutdated: Bool = true,
        checkGitTracking: Bool = true,
        concurrentFetchLimit: Int = 8,
        timeout: TimeInterval = 30
    ) {
        self.checkOutdated = checkOutdated
        self.checkGitTracking = checkGitTracking
        self.concurrentFetchLimit = concurrentFetchLimit
        self.timeout = timeout
    }
}
