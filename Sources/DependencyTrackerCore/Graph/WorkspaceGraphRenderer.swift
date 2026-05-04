import Foundation

/// Renders workspace graph snapshots as Mermaid, DOT, or JSON.
public struct WorkspaceGraphRenderer: Sendable {
    /// Shared builder that keeps document construction separate from output formatting.
    private let builder: WorkspaceGraphBuilder

    /// Creates a workspace graph renderer.
    public init(builder: WorkspaceGraphBuilder = WorkspaceGraphBuilder()) {
        self.builder = builder
    }

    /// Renders the graph as Mermaid, DOT, or JSON.
    public func render(_ report: WorkspaceReport, format: WorkspaceGraphFormat) -> String {
        let document = builder.makeDocument(from: report)
        return render(document, format: format)
    }

    /// Renders an already-built graph document as Mermaid, DOT, or JSON.
    public func render(_ document: WorkspaceGraphDocument, format: WorkspaceGraphFormat) -> String {
        switch format {
        case .mermaid:
            return renderMermaid(document)
        case .dot:
            return renderDOT(document)
        case .json:
            return renderJSON(document)
        }
    }

    /// Renders the graph document to Mermaid syntax.
    public func renderMermaid(_ document: WorkspaceGraphDocument) -> String {
        var lines: [String] = []
        lines.append("graph TD")
        lines.append("  root[\"\(escapeLabel(document.rootPath))\"]")

        for node in document.nodes where node.id != "root" {
            lines.append("  \(node.id)[\"\(escapeLabel(node.label))\"]")
        }

        for edge in document.edges {
            lines.append("  \(edge.from) -->|\(escapeLabel(edgeLabel(edge)))| \(edge.to)")
        }

        return lines.joined(separator: "\n")
    }

    /// Renders the graph document to Graphviz DOT.
    public func renderDOT(_ document: WorkspaceGraphDocument) -> String {
        var lines: [String] = []
        lines.append("digraph WorkspaceGraph {")
        lines.append("  rankdir=TB;")
        lines.append("  root [label=\"\(escapeDOT(document.rootPath))\", shape=box];")

        for node in document.nodes where node.id != "root" {
            let shape = shape(for: node.kind)
            lines.append("  \(node.id) [label=\"\(escapeDOT(node.label))\", shape=\(shape)];")
        }

        for edge in document.edges {
            lines.append("  \(edge.from) -> \(edge.to) [label=\"\(escapeDOT(edgeLabel(edge)))\"];")
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// Renders the graph document as stable JSON.
    public func renderJSON(_ document: WorkspaceGraphDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(document)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
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

    /// Includes provenance in text graph labels without changing the graph structure.
    private func edgeLabel(_ edge: WorkspaceGraphDocument.Edge) -> String {
        "\(edge.label) [\(edge.provenance.source.rawValue)]"
    }

    /// Keeps graph shapes predictable for common node types.
    private func shape(for kind: String) -> String {
        switch kind {
        case "workspace":
            return "box"
        case "context":
            return "ellipse"
        case "dependency":
            return "component"
        default:
            return "box"
        }
    }
}
