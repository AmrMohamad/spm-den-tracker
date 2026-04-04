import DependencyTrackerCore
import Foundation

/// Builds a lightweight workspace graph from aggregate analysis metadata.
struct WorkspaceGraphRenderer: Sendable {
    /// Renders the graph as Mermaid, DOT, or JSON.
    func render(_ report: WorkspaceReport, format: GraphFormat) -> String {
        let document = makeDocument(from: report)

        switch format {
        case .mermaid:
            return renderMermaid(document)
        case .dot:
            return renderDOT(document)
        case .json:
            return renderJSON(document)
        }
    }

    /// Produces a graph snapshot that can be serialized or rendered.
    private func makeDocument(from report: WorkspaceReport) -> WorkspaceGraphDocument {
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

    /// Renders the graph document to Mermaid syntax.
    private func renderMermaid(_ document: WorkspaceGraphDocument) -> String {
        var lines: [String] = []
        lines.append("graph TD")
        lines.append("  root[\"\(escapeLabel(document.rootPath))\"]")

        for node in document.nodes where node.id != "root" {
            lines.append("  \(node.id)[\"\(escapeLabel(node.label))\"]")
        }

        for edge in document.edges {
            lines.append("  \(edge.from) -->|\(escapeLabel(edge.label))| \(edge.to)")
        }

        return lines.joined(separator: "\n")
    }

    /// Renders the graph document to Graphviz DOT.
    private func renderDOT(_ document: WorkspaceGraphDocument) -> String {
        var lines: [String] = []
        lines.append("digraph WorkspaceGraph {")
        lines.append("  rankdir=TD;")
        lines.append("  root [label=\"\(escapeDOT(document.rootPath))\", shape=box];")

        for node in document.nodes where node.id != "root" {
            let shape = node.kind == "context" ? "ellipse" : "box"
            lines.append("  \(node.id) [label=\"\(escapeDOT(node.label))\", shape=\(shape)];")
        }

        for edge in document.edges {
            lines.append("  \(edge.from) -> \(edge.to) [label=\"\(escapeDOT(edge.label))\"];")
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// Renders the graph document as stable JSON.
    private func renderJSON(_ document: WorkspaceGraphDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(document)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
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

    /// Escapes a Mermaid label.
    private func escapeLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Escapes a DOT label.
    private func escapeDOT(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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

/// Stable graph snapshot used for JSON and the text renderers.
private struct WorkspaceGraphDocument: Codable, Sendable {
    /// The root path that seeded discovery.
    let rootPath: String
    /// The timestamp when the workspace graph was assembled.
    let generatedAt: Date
    /// The graph certainty reported by the workspace analysis.
    let certainty: WorkspaceGraphCertainty
    /// The short human-readable summary for the graph.
    let message: String
    /// The graph nodes in traversal order.
    let nodes: [Node]
    /// The graph edges in traversal order.
    let edges: [Edge]

    /// A graph node.
    struct Node: Codable, Sendable {
        let id: String
        let label: String
        let kind: String
    }

    /// A graph edge.
    struct Edge: Codable, Sendable {
        let from: String
        let to: String
        let label: String
    }
}
