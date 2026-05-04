import Foundation

/// Summarizes dependency nodes that affect more than one workspace context.
public struct BlastRadiusAnalyzer: Sendable {
    public init() {}

    /// Finds dependency identities that appear across multiple contexts.
    public func analyze(_ document: WorkspaceGraphDocument) -> [Finding] {
        let dependencyNodes = document.nodes.filter { $0.kind == "dependency" }
        let grouped = Dictionary(grouping: dependencyNodes) { node in
            node.metadata["identity"] ?? node.label
        }

        return grouped.compactMap { identity, nodes in
            let contexts = Set(nodes.compactMap { $0.metadata["context"] })
            guard contexts.count > 1 else { return nil }
            let contextList = contexts.sorted().joined(separator: ", ")
            return Finding(
                severity: .info,
                category: .graph,
                message: "\"\(identity)\" appears in \(contexts.count) workspace contexts: \(contextList).",
                recommendation: "When changing or updating this dependency, validate every listed context because the graph shows shared blast radius."
            )
        }
        .sorted { $0.message < $1.message }
    }
}
