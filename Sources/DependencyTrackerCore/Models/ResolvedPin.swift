import Foundation

/// Represents one dependency entry decoded from `Package.resolved`.
public struct ResolvedPin: Codable, Hashable, Sendable {
    /// The normalized package identity used for sorting and report lookups.
    public let identity: String
    /// The source kind inferred from the resolved file payload.
    public let kind: PinKind
    /// The repository URL or filesystem path recorded by SwiftPM.
    public let location: String
    /// The exact pinning strategy and revision details for the dependency.
    public let state: PinState

    /// Creates a resolved pin from the values extracted from `Package.resolved`.
    public init(identity: String, kind: PinKind, location: String, state: PinState) {
        self.identity = identity
        self.kind = kind
        self.location = location
        self.state = state
    }
}

/// Describes where SwiftPM resolves a package from.
public enum PinKind: String, Codable, Hashable, Sendable {
    /// A dependency fetched from a remote git repository.
    case remoteSourceControl
    /// A dependency resolved from another local git checkout.
    case localSourceControl
    /// A dependency resolved directly from a filesystem path.
    case fileSystem
}

/// Captures how SwiftPM pinned a dependency at resolution time.
public enum PinState: Codable, Hashable, Sendable {
    /// The dependency is pinned to a semantic version plus a backing revision.
    case version(String, revision: String)
    /// The dependency is pinned to a branch plus the currently resolved revision.
    case branch(String, revision: String)
    /// The dependency is pinned to an exact revision without a higher-level label.
    case revision(String)
    /// The dependency resolves from a local path and therefore has no remote revision contract.
    case local

    /// Returns the underlying git revision when the state carries one.
    public var revision: String? {
        switch self {
        case .version(_, let revision), .branch(_, let revision):
            return revision
        case .revision(let revision):
            return revision
        case .local:
            return nil
        }
    }

    /// Returns the most human-readable value for tables and markdown reports.
    public var displayValue: String {
        switch self {
        case .version(let version, _):
            return version
        case .branch(let branch, _):
            return branch
        case .revision(let revision):
            return String(revision.prefix(12))
        case .local:
            return "local"
        }
    }

    /// Returns a compact label describing the pinning strategy.
    public var strategyLabel: String {
        switch self {
        case .version:
            return "version"
        case .branch:
            return "branch"
        case .revision:
            return "revision"
        case .local:
            return "local"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case version
        case branch
        case revision
    }

    /// Decodes the ad-hoc state payload used inside `Package.resolved`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)

        switch kind {
        case "version":
            self = .version(
                try container.decode(String.self, forKey: .version),
                revision: try container.decode(String.self, forKey: .revision)
            )
        case "branch":
            self = .branch(
                try container.decode(String.self, forKey: .branch),
                revision: try container.decode(String.self, forKey: .revision)
            )
        case "revision":
            self = .revision(try container.decode(String.self, forKey: .revision))
        case "local":
            self = .local
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unsupported pin state kind: \(kind)")
        }
    }

    /// Encodes the state back into the flattened format expected by the reporters and tests.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .version(let version, let revision):
            try container.encode("version", forKey: .kind)
            try container.encode(version, forKey: .version)
            try container.encode(revision, forKey: .revision)
        case .branch(let branch, let revision):
            try container.encode("branch", forKey: .kind)
            try container.encode(branch, forKey: .branch)
            try container.encode(revision, forKey: .revision)
        case .revision(let revision):
            try container.encode("revision", forKey: .kind)
            try container.encode(revision, forKey: .revision)
        case .local:
            try container.encode("local", forKey: .kind)
        }
    }
}
