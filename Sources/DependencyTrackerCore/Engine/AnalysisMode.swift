import Foundation

/// Selects whether the tracker should treat an input as one audit target or a workspace root.
public enum AnalysisMode: String, Codable, Sendable, Equatable, Hashable {
    /// Resolves files as single targets and inspects directory inputs before choosing a mode.
    case auto
    /// Preserves the current single-target audit behavior.
    case singleTarget
    /// Forces recursive workspace discovery and aggregate reporting.
    case monorepo
}
