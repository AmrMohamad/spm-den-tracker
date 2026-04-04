import Foundation

/// Groups discovered manifests by their effective resolved-file ownership.
public struct ResolutionContextDetector: Sendable {
    /// Creates a detector for grouping manifest ownership into resolution contexts.
    public init() {}

    /// Collapses discovered manifests into deterministic resolution contexts.
    public func detect(from manifests: [DiscoveredManifest]) -> [ResolutionContext] {
        let grouped = Dictionary(grouping: manifests) { manifest in
            manifest.ownershipKey ?? manifest.path
        }

        return grouped
            .map { key, group -> ResolutionContext in
                let orderedGroup = group.sorted(by: manifestSortOrder)
                let resolvedFilePath = orderedGroup.compactMap(\.resolvedFilePath).first
                let displayPath = orderedGroup.first?.path ?? key
                return ResolutionContext(
                    key: key,
                    displayPath: displayPath,
                    resolvedFilePath: resolvedFilePath,
                    manifestPaths: orderedGroup.map(\.path)
                )
            }
            .sorted { lhs, rhs in
                let lhsPath = lhs.displayPath.lowercased()
                let rhsPath = rhs.displayPath.lowercased()
                if lhsPath != rhsPath {
                    return lhsPath < rhsPath
                }
                return lhs.key < rhs.key
            }
    }

    /// Sorts manifests using the same kind-first ordering as discovery output.
    private func manifestSortOrder(_ lhs: DiscoveredManifest, _ rhs: DiscoveredManifest) -> Bool {
        let lhsPriority = kindPriority(lhs.kind)
        let rhsPriority = kindPriority(rhs.kind)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
    }

    /// Keeps context display paths stable by preferring project/workspace roots before lockfiles.
    private func kindPriority(_ kind: DiscoveredManifestKind) -> Int {
        switch kind {
        case .xcodeproj:
            return 0
        case .xcworkspace:
            return 1
        case .packageManifest:
            return 2
        case .resolvedFile:
            return 3
        }
    }
}
