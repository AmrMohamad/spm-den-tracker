import Foundation

/// The graph output formats supported by the workspace graph renderer.
public enum WorkspaceGraphFormat: String, Codable, Sendable, Equatable, Hashable {
    case mermaid
    case dot
    case json
}
