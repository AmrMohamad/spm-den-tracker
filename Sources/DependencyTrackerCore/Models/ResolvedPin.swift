import Foundation

public struct ResolvedPin: Codable, Hashable, Sendable {
    public let identity: String
    public let kind: PinKind
    public let location: String
    public let state: PinState

    public init(identity: String, kind: PinKind, location: String, state: PinState) {
        self.identity = identity
        self.kind = kind
        self.location = location
        self.state = state
    }
}

public enum PinKind: String, Codable, Hashable, Sendable {
    case remoteSourceControl
    case localSourceControl
    case fileSystem
}

public enum PinState: Codable, Hashable, Sendable {
    case version(String, revision: String)
    case branch(String, revision: String)
    case revision(String)
    case local

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
