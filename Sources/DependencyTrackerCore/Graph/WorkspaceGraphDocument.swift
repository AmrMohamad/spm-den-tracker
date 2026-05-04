import Foundation

/// Stable graph snapshot used for JSON and the text renderers.
public struct WorkspaceGraphDocument: Codable, Sendable, Equatable, Hashable {
    /// The root path that seeded discovery.
    public let rootPath: String
    /// The timestamp when the workspace graph was assembled.
    public let generatedAt: Date
    /// The graph certainty reported by the workspace analysis.
    public let certainty: WorkspaceGraphCertainty
    /// The short human-readable summary for the graph.
    public let message: String
    /// The graph nodes in traversal order.
    public let nodes: [Node]
    /// The graph edges in traversal order.
    public let edges: [Edge]

    /// Creates a graph snapshot.
    public init(
        rootPath: String,
        generatedAt: Date,
        certainty: WorkspaceGraphCertainty,
        message: String,
        nodes: [Node],
        edges: [Edge]
    ) {
        self.rootPath = rootPath
        self.generatedAt = generatedAt
        self.certainty = certainty
        self.message = message
        self.nodes = nodes
        self.edges = edges
    }

    /// A graph node.
    public struct Node: Codable, Sendable, Equatable, Hashable {
        public let id: String
        public let label: String
        public let kind: String
        public let metadata: [String: String]

        /// Creates a graph node.
        public init(id: String, label: String, kind: String, metadata: [String: String] = [:]) {
            self.id = id
            self.label = label
            self.kind = kind
            self.metadata = metadata
        }
    }

    /// A graph edge.
    public struct Edge: Codable, Sendable, Equatable, Hashable {
        public let from: String
        public let to: String
        public let label: String
        public let provenance: EdgeProvenance

        /// Creates a graph edge.
        public init(from: String, to: String, label: String, provenance: EdgeProvenance) {
            self.from = from
            self.to = to
            self.label = label
            self.provenance = provenance
        }
    }

    /// Explains why a graph edge exists.
    public struct EdgeProvenance: Codable, Sendable, Equatable, Hashable {
        public let source: EdgeProvenanceSource
        public let sourcePath: String?
        public let detail: String

        /// Creates edge provenance for serialized and rendered graph outputs.
        public init(source: EdgeProvenanceSource, sourcePath: String?, detail: String) {
            self.source = source
            self.sourcePath = sourcePath
            self.detail = detail
        }
    }
}

/// Names the source that proved a workspace graph edge.
public enum EdgeProvenanceSource: String, Codable, Sendable, Equatable, Hashable {
    case workspaceDiscovery
    case manifestDiscovery
    case packageResolved
    case packageManifest
    case xcodeProject
}
