import Foundation

/// Recursively discovers auditable SwiftPM and Xcode dependency roots beneath a workspace root.
public struct ManifestIndex: @unchecked Sendable {
    private let fileManager: FileManager
    private let maxDepth: Int
    private let ignoreFileName: String

    /// Creates a manifest index with deterministic recursion and root-level ignore support.
    public init(
        fileManager: FileManager = .default,
        maxDepth: Int = 10,
        ignoreFileName: String = ".spm-dep-tracker-ignore"
    ) {
        self.fileManager = fileManager
        self.maxDepth = maxDepth
        self.ignoreFileName = ignoreFileName
    }

    /// Discovers manifests and lockfiles beneath the supplied path.
    ///
    /// If the root itself is a supported manifest type, the index returns that one item.
    /// Directory roots are scanned depth-first with deterministic ordering, built-in excludes,
    /// and optional root-level ignore rules.
    public func discover(from rootPath: String) throws -> [DiscoveredManifest] {
        let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
            throw DependencyTrackerError.invalidPath(rootPath)
        }

        if let rootKind = manifestKind(for: rootURL) {
            return [makeManifest(for: rootURL, kind: rootKind)]
        }

        guard isDirectory.boolValue else {
            return []
        }

        let ignoreSet = try WorkspaceDiscoveryIgnoreSet(
            rootURL: rootURL,
            fileManager: fileManager,
            ignoreFileName: ignoreFileName
        )

        var discovered: [DiscoveredManifest] = []
        var visitedCanonicalPaths = Set<String>()
        try walk(
            directoryURL: rootURL,
            rootURL: rootURL,
            depth: 0,
            ignoreSet: ignoreSet,
            discovered: &discovered,
            visitedCanonicalPaths: &visitedCanonicalPaths
        )

        return discovered.sorted { DiscoveryOrdering.lessThan($0, $1) }
    }

    private func walk(
        directoryURL: URL,
        rootURL: URL,
        depth: Int,
        ignoreSet: WorkspaceDiscoveryIgnoreSet,
        discovered: inout [DiscoveredManifest],
        visitedCanonicalPaths: inout Set<String>
    ) throws {
        let canonicalDirectory = canonicalPath(for: directoryURL)
        guard visitedCanonicalPaths.insert(canonicalDirectory).inserted else {
            return
        }

        guard depth <= maxDepth else {
            return
        }

        let entries = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ).sorted { DiscoveryOrdering.lessThan($0, $1) }

        for entryURL in entries {
            let resourceValues = try entryURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues.isDirectory ?? false
            let relativePath = relativePath(from: rootURL, to: entryURL)

            if ignoreSet.shouldIgnore(relativePath: relativePath, name: entryURL.lastPathComponent) {
                continue
            }

            if let kind = manifestKind(for: entryURL) {
                let manifest = makeManifest(for: entryURL, kind: kind)
                if !visitedCanonicalPaths.contains(manifest.path) {
                    discovered.append(manifest)
                    visitedCanonicalPaths.insert(manifest.path)
                }
                continue
            }

            guard isDirectory else {
                continue
            }

            guard depth < maxDepth else {
                continue
            }

            try walk(
                directoryURL: entryURL,
                rootURL: rootURL,
                depth: depth + 1,
                ignoreSet: ignoreSet,
                discovered: &discovered,
                visitedCanonicalPaths: &visitedCanonicalPaths
            )
        }
    }

    private func makeManifest(for url: URL, kind: DiscoveredManifestKind) -> DiscoveredManifest {
        let displayPath = canonicalPath(for: url)
        let resolvedFilePath = ownershipPath(for: url, kind: kind)
        return DiscoveredManifest(
            path: displayPath,
            kind: kind,
            resolvedFilePath: resolvedFilePath,
            ownershipKey: resolvedFilePath
        )
    }

    private func manifestKind(for url: URL) -> DiscoveredManifestKind? {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = resourceValues?.isDirectory ?? false

        switch url.lastPathComponent {
        case "Package.swift":
            return .packageManifest
        case "Package.resolved":
            return isDirectory ? nil : .resolvedFile
        default:
            break
        }

        switch url.pathExtension {
        case "xcodeproj":
            return .xcodeproj
        case "xcworkspace":
            return .xcworkspace
        default:
            return nil
        }
    }

    private func ownershipPath(for url: URL, kind: DiscoveredManifestKind) -> String {
        switch kind {
        case .xcodeproj:
            return canonicalPath(
                for: url
                    .appendingPathComponent("project.xcworkspace", isDirectory: true)
                    .appendingPathComponent("xcshareddata", isDirectory: true)
                    .appendingPathComponent("swiftpm", isDirectory: true)
                    .appendingPathComponent("Package.resolved")
            )
        case .xcworkspace:
            return canonicalPath(
                for: url
                    .appendingPathComponent("xcshareddata", isDirectory: true)
                    .appendingPathComponent("swiftpm", isDirectory: true)
                    .appendingPathComponent("Package.resolved")
            )
        case .packageManifest:
            return canonicalPath(for: url.deletingLastPathComponent().appendingPathComponent("Package.resolved"))
        case .resolvedFile:
            return canonicalPath(for: url)
        }
    }

    private func canonicalPath(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func relativePath(from rootURL: URL, to url: URL) -> String {
        let rootPath = canonicalPath(for: rootURL)
        let candidatePath = canonicalPath(for: url)

        guard candidatePath != rootPath else {
            return ""
        }

        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidatePath.hasPrefix(prefix) else {
            return candidatePath
        }

        return String(candidatePath.dropFirst(prefix.count))
    }
}

enum DiscoveryOrdering {
    static func lessThan(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsName = lhs.lastPathComponent.lowercased()
        let rhsName = rhs.lastPathComponent.lowercased()
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        return lhs.path.lowercased() < rhs.path.lowercased()
    }

    static func lessThan(_ lhs: DiscoveredManifest, _ rhs: DiscoveredManifest) -> Bool {
        let lhsPriority = priority(for: lhs.kind)
        let rhsPriority = priority(for: rhs.kind)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.path.lowercased() < rhs.path.lowercased()
    }

    private static func priority(for kind: DiscoveredManifestKind) -> Int {
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

private struct WorkspaceDiscoveryIgnoreSet {
    private let rules: [WorkspaceDiscoveryIgnoreRule]

    init(rootURL: URL, fileManager: FileManager, ignoreFileName: String) throws {
        var parsedRules = WorkspaceDiscoveryIgnoreRule.builtInRules

        let ignoreFileURL = rootURL.appendingPathComponent(ignoreFileName)
        if fileManager.fileExists(atPath: ignoreFileURL.path) {
            let contents = try String(contentsOf: ignoreFileURL, encoding: .utf8)
            parsedRules.append(contentsOf: contents.split(whereSeparator: \.isNewline).compactMap { WorkspaceDiscoveryIgnoreRule(line: String($0)) })
        }

        rules = parsedRules
    }

    func shouldIgnore(relativePath: String, name: String) -> Bool {
        !relativePath.isEmpty && rules.contains { $0.matches(relativePath: relativePath, name: name) }
    }
}

private struct WorkspaceDiscoveryIgnoreRule {
    let rawValue: String

    static let builtInRules: [WorkspaceDiscoveryIgnoreRule] = [
        ".git",
        "DerivedData",
        "Pods",
        "Carthage",
        ".build",
        "build",
        "node_modules"
    ].map { WorkspaceDiscoveryIgnoreRule(rawValue: $0) }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init?(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
            return nil
        }
        rawValue = trimmed
    }

    func matches(relativePath: String, name: String) -> Bool {
        let normalizedPath = relativePath.lowercased()
        let normalizedName = name.lowercased()
        let pattern = rawValue.lowercased()

        if pattern.hasSuffix("/") {
            let prefix = pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return normalizedPath == prefix || normalizedPath.hasPrefix(prefix + "/") || normalizedName == prefix
        }

        if pattern.contains("*") || pattern.contains("?") {
            return globMatches(pattern: pattern, value: normalizedPath) || globMatches(pattern: pattern, value: normalizedName)
        }

        if pattern.contains("/") {
            return normalizedPath == pattern || normalizedPath.hasPrefix(pattern + "/")
        }

        return normalizedName == pattern || normalizedPath.split(separator: "/").contains(where: { $0 == pattern })
    }

    private func globMatches(pattern: String, value: String) -> Bool {
        let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else {
            return false
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }
}
