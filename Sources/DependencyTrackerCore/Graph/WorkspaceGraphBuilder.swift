import Foundation

/// Builds a lightweight workspace graph from aggregate analysis metadata.
public struct WorkspaceGraphBuilder: Sendable {
    /// Creates a workspace graph builder.
    public init() {}

    /// Produces a graph snapshot that can be serialized or rendered.
    public func makeDocument(from report: WorkspaceReport) -> WorkspaceGraphDocument {
        var nodes: [WorkspaceGraphDocument.Node] = []
        var edges: [WorkspaceGraphDocument.Edge] = []

        let rootID = identifier("root")
        nodes.append(.init(id: rootID, label: report.rootPath, kind: "workspace"))

        for (contextIndex, contextReport) in report.contexts.enumerated() {
            let contextID = identifier("context-\(contextIndex)-\(contextReport.context.key)")
            nodes.append(.init(id: contextID, label: contextReport.context.displayPath, kind: "context"))
            edges.append(.init(from: rootID, to: contextID, label: analysisModeLabel(report.analysisMode)))

            for (manifestIndex, manifestPath) in contextReport.context.manifestPaths.enumerated() {
                let manifestID = identifier("manifest-\(contextIndex)-\(manifestIndex)-\(manifestPath)")
                nodes.append(.init(id: manifestID, label: manifestPath, kind: "manifest"))
                edges.append(.init(from: contextID, to: manifestID, label: "contains"))
            }
        }

        return WorkspaceGraphDocument(
            rootPath: report.rootPath,
            generatedAt: report.generatedAt,
            certainty: report.graphSummary?.certainty ?? .metadataOnly,
            message: report.graphSummary?.message ?? "Workspace topology derived from discovered manifests and contexts.",
            nodes: nodes,
            edges: edges
        )
    }

    /// Converts arbitrary strings into graph-safe identifiers.
    private func identifier(_ value: String) -> String {
        let raw = value.unicodeScalars.reduce(into: "") { result, scalar in
            result.append(CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_")
        }
        guard !raw.isEmpty else {
            return "node"
        }
        return raw.first?.isLetter == true ? raw : "n_\(raw)"
    }

    /// Human-readable analysis mode label used in graph edges.
    private func analysisModeLabel(_ mode: AnalysisMode) -> String {
        switch mode {
        case .auto:
            return "auto"
        case .singleTarget:
            return "single-target"
        case .monorepo:
            return "monorepo"
        }
    }
}
