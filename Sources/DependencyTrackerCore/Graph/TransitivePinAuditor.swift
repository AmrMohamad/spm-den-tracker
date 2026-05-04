import Foundation

/// Emits graph-aware findings for pins that are resolved without direct declaration provenance.
public struct TransitivePinAuditor: Sendable {
    public init() {}

    /// Finds resolved dependency nodes that are present only through `Package.resolved` provenance.
    public func analyze(_ document: WorkspaceGraphDocument) -> [Finding] {
        document.nodes
            .filter { $0.kind == "dependency" && $0.metadata["declared"] == "false" }
            .sorted { dependencySortKey($0) < dependencySortKey($1) }
            .map { node in
                let identity = node.metadata["identity"] ?? node.label
                let context = node.metadata["context"] ?? document.rootPath
                return Finding(
                    severity: .info,
                    category: .graph,
                    message: "\"\(identity)\" is resolved in \(context) without direct declaration provenance.",
                    recommendation: "Treat this as transitive or metadata-only graph evidence until a manifest or Xcode project declaration proves the edge."
                )
            }
    }

    private func dependencySortKey(_ node: WorkspaceGraphDocument.Node) -> String {
        "\(node.metadata["context"] ?? "")/\(node.metadata["identity"] ?? node.label)"
    }
}
