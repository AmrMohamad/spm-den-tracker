import Foundation

/// Builds a workspace graph from aggregate analysis metadata and resolved dependency reports.
public struct WorkspaceGraphBuilder: Sendable {
    /// Creates a workspace graph builder.
    public init() {}

    /// Produces a graph snapshot that can be serialized or rendered.
    public func makeDocument(from report: WorkspaceReport) -> WorkspaceGraphDocument {
        var nodes: [WorkspaceGraphDocument.Node] = []
        var edges: [WorkspaceGraphDocument.Edge] = []
        var seenNodes = Set<String>()
        var seenEdges = Set<WorkspaceGraphDocument.Edge>()
        let includeDependencyEdges = report.graphSummary.map { $0.certainty != .metadataOnly } ?? false

        let rootID = identifier("root")
        appendNode(.init(id: rootID, label: report.rootPath, kind: "workspace"), to: &nodes, seen: &seenNodes)

        for (contextIndex, contextReport) in report.contexts.enumerated() {
            let contextID = identifier("context-\(contextIndex)-\(contextReport.context.key)")
            appendNode(
                .init(
                    id: contextID,
                    label: contextReport.context.displayPath,
                    kind: "context",
                    metadata: contextMetadata(contextReport.context)
                ),
                to: &nodes,
                seen: &seenNodes
            )
            appendEdge(
                .init(
                    from: rootID,
                    to: contextID,
                    label: analysisModeLabel(report.analysisMode),
                    provenance: .init(
                        source: .workspaceDiscovery,
                        sourcePath: report.rootPath,
                        detail: "Resolution context discovered during \(analysisModeLabel(report.analysisMode)) analysis."
                    )
                ),
                to: &edges,
                seen: &seenEdges
            )

            var manifestIDsByPath: [String: String] = [:]

            for (manifestIndex, manifestPath) in contextReport.context.manifestPaths.enumerated() {
                let manifestID = identifier("manifest-\(contextIndex)-\(manifestIndex)-\(manifestPath)")
                manifestIDsByPath[manifestPath] = manifestID
                appendNode(
                    .init(id: manifestID, label: manifestPath, kind: "manifest", metadata: ["path": manifestPath]),
                    to: &nodes,
                    seen: &seenNodes
                )
                appendEdge(
                    .init(
                        from: contextID,
                        to: manifestID,
                        label: "contains",
                        provenance: .init(
                            source: .manifestDiscovery,
                            sourcePath: manifestPath,
                            detail: "Manifest or project belongs to this resolution context."
                        )
                    ),
                    to: &edges,
                    seen: &seenEdges
                )
            }

            guard includeDependencyEdges else {
                continue
            }

            for dependencyReport in contextReport.reports {
                for dependency in dependencyReport.dependencies.sorted(by: { $0.pin.identity < $1.pin.identity }) {
                    let dependencyID = identifier("dependency-\(contextIndex)-\(dependency.pin.identity)")
                    appendNode(
                        .init(
                            id: dependencyID,
                            label: dependency.pin.identity,
                            kind: "dependency",
                            metadata: dependencyMetadata(dependency, context: contextReport.context)
                        ),
                        to: &nodes,
                        seen: &seenNodes
                    )
                    appendEdge(
                        .init(
                            from: contextID,
                            to: dependencyID,
                            label: "resolves \(dependency.pin.state.displayValue)",
                            provenance: .init(
                                source: .packageResolved,
                                sourcePath: dependencyReport.resolvedFilePath,
                                detail: "Pin read from Package.resolved for this resolution context."
                            )
                        ),
                        to: &edges,
                        seen: &seenEdges
                    )

                    guard let requirement = dependency.declaredRequirement else {
                        continue
                    }

                    let sourceID = manifestSourceID(
                        for: requirement,
                        manifestIDsByPath: manifestIDsByPath,
                        fallbackContextID: contextID
                    )
                    appendEdge(
                        .init(
                            from: sourceID,
                            to: dependencyID,
                            label: "declares \(requirement.kind.rawValue)",
                            provenance: .init(
                                source: provenanceSource(for: requirement.source),
                                sourcePath: sourcePath(for: requirement, manifestPaths: contextReport.context.manifestPaths),
                                detail: requirement.description
                            )
                        ),
                        to: &edges,
                        seen: &seenEdges
                    )
                }
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

    /// Appends a node once, keeping graph output stable when multiple reports mention the same package.
    private func appendNode(
        _ node: WorkspaceGraphDocument.Node,
        to nodes: inout [WorkspaceGraphDocument.Node],
        seen: inout Set<String>
    ) {
        guard seen.insert(node.id).inserted else { return }
        nodes.append(node)
    }

    /// Appends a unique edge while preserving traversal order.
    private func appendEdge(
        _ edge: WorkspaceGraphDocument.Edge,
        to edges: inout [WorkspaceGraphDocument.Edge],
        seen: inout Set<WorkspaceGraphDocument.Edge>
    ) {
        guard seen.insert(edge).inserted else { return }
        edges.append(edge)
    }

    /// Converts arbitrary strings into graph-safe identifiers.
    private func identifier(_ value: String) -> String {
        let encoded = value.unicodeScalars
            .map { String($0.value, radix: 16, uppercase: true) }
            .joined(separator: "_")
        return encoded.isEmpty ? "node" : "n_\(encoded)"
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

    /// Metadata used by JSON consumers and graph-aware analyzers.
    private func contextMetadata(_ context: ResolutionContext) -> [String: String] {
        var metadata = [
            "key": context.key,
            "displayPath": context.displayPath,
            "manifestCount": String(context.manifestPaths.count),
        ]
        if let resolvedFilePath = context.resolvedFilePath {
            metadata["resolvedFilePath"] = resolvedFilePath
        }
        return metadata
    }

    /// Metadata used by JSON consumers and graph-aware analyzers.
    private func dependencyMetadata(_ dependency: DependencyAnalysis, context: ResolutionContext) -> [String: String] {
        var metadata = [
            "identity": dependency.pin.identity,
            "kind": dependency.pin.kind.rawValue,
            "location": dependency.pin.location,
            "current": dependency.pin.state.displayValue,
            "pinStrategy": dependency.pin.state.strategyLabel,
            "strategyRisk": dependency.strategyRisk.rawValue,
            "context": context.displayPath,
            "declared": String(dependency.declaredRequirement != nil),
        ]
        if let revision = dependency.pin.state.revision {
            metadata["revision"] = revision
        }
        if let requirement = dependency.declaredRequirement {
            metadata["declaredRequirement"] = requirement.description
            metadata["declaredRequirementSource"] = requirement.source.rawValue
        }
        return metadata
    }

    /// Chooses the most specific graph source currently known for a declared requirement edge.
    private func manifestSourceID(
        for requirement: DeclaredRequirement,
        manifestIDsByPath: [String: String],
        fallbackContextID: String
    ) -> String {
        if let sourcePath = requirement.sourcePath, let exactMatch = manifestIDsByPath[sourcePath] {
            return exactMatch
        }
        let suffix = requirement.source == .packageManifest ? "Package.swift" : ".xcodeproj"
        let matches = manifestIDsByPath.filter { $0.key.hasSuffix(suffix) }
        if matches.count == 1, let match = matches.first {
            return match.value
        }
        return fallbackContextID
    }

    /// Uses a best-effort source path for human-readable provenance.
    private func sourcePath(for requirement: DeclaredRequirement, manifestPaths: [String]) -> String? {
        if let sourcePath = requirement.sourcePath {
            return sourcePath
        }
        switch requirement.source {
        case .packageManifest:
            let matches = manifestPaths.filter { $0.hasSuffix("Package.swift") }
            return matches.count == 1 ? matches.first : nil
        case .xcodeProject:
            let matches = manifestPaths.filter { $0.hasSuffix(".xcodeproj") }
            return matches.count == 1 ? matches.first : nil
        }
    }

    /// Maps requirement parser sources onto graph provenance sources.
    private func provenanceSource(for source: DeclaredRequirementSource) -> EdgeProvenanceSource {
        switch source {
        case .packageManifest:
            return .packageManifest
        case .xcodeProject:
            return .xcodeProject
        }
    }
}
