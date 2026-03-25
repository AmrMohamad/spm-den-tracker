import Foundation

/// Resolves user input into the canonical `Package.resolved` path used by Xcode projects.
struct XcodeprojLocator: Sendable {
    /// Accepts a project bundle, project directory, manifest, or resolved file path and returns the audit target.
    func locateAuditTarget(at rawPath: String) throws -> AuditTarget {
        let fileManager = FileManager.default
        let inputURL = URL(fileURLWithPath: rawPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            throw DependencyTrackerError.invalidPath(rawPath)
        }

        if inputURL.lastPathComponent == "Package.resolved" {
            return AuditTarget(
                inputPath: rawPath,
                resolvedFileURL: inputURL,
                projectFileURL: discoverProject(near: inputURL),
                manifestURL: discoverManifest(near: inputURL),
                repositoryRootURL: discoverRepositoryRoot(from: inputURL)
            )
        }

        if inputURL.lastPathComponent == "Package.swift" {
            return AuditTarget(
                inputPath: rawPath,
                resolvedFileURL: inputURL.deletingLastPathComponent().appendingPathComponent("Package.resolved"),
                projectFileURL: nil,
                manifestURL: inputURL,
                repositoryRootURL: inputURL.deletingLastPathComponent()
            )
        }

        if inputURL.pathExtension == "xcodeproj" {
            return AuditTarget(
                inputPath: rawPath,
                resolvedFileURL: resolvedURL(forProject: inputURL),
                projectFileURL: inputURL,
                manifestURL: discoverManifest(near: inputURL),
                repositoryRootURL: inputURL.deletingLastPathComponent()
            )
        }

        if isDirectory.boolValue {
            let candidates = try xcodeprojCandidates(in: inputURL)
            if candidates.count > 1 {
                throw DependencyTrackerError.ambiguousProjectPath(rawPath, candidates: candidates.map(\.path))
            }

            if let first = candidates.first {
                return AuditTarget(
                    inputPath: rawPath,
                    resolvedFileURL: resolvedURL(forProject: first),
                    projectFileURL: first,
                    manifestURL: discoverManifest(near: first),
                    repositoryRootURL: inputURL
                )
            }

            let manifestURL = inputURL.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: manifestURL.path) {
                return AuditTarget(
                    inputPath: rawPath,
                    resolvedFileURL: inputURL.appendingPathComponent("Package.resolved"),
                    projectFileURL: nil,
                    manifestURL: manifestURL,
                    repositoryRootURL: inputURL
                )
            }

            throw DependencyTrackerError.invalidPath(rawPath)
        }

        throw DependencyTrackerError.invalidPath(rawPath)
    }

    /// Preserves the existing convenience for callers that only need the resolved-file URL.
    func locateResolvedFile(at rawPath: String) throws -> URL {
        try locateAuditTarget(at: rawPath).resolvedFileURL
    }

    /// Builds the conventional Xcode workspace path for a project's resolved file.
    private func resolvedURL(forProject projectURL: URL) -> URL {
        projectURL
            .appendingPathComponent("project.xcworkspace", isDirectory: true)
            .appendingPathComponent("xcshareddata", isDirectory: true)
            .appendingPathComponent("swiftpm", isDirectory: true)
            .appendingPathComponent("Package.resolved")
    }

    /// Scans one directory level for `.xcodeproj` bundles so repo roots stay predictable.
    private func xcodeprojCandidates(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        // Directory inputs intentionally scan only immediate children so the tool
        // behaves predictably for repo roots with multiple project bundles.
        let candidates = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "xcodeproj" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return candidates
    }

    /// Searches ancestors for the nearest `.xcodeproj` bundle.
    private func discoverProject(near url: URL) -> URL? {
        var currentPath = startingAncestorPath(for: url)

        while true {
            let currentURL = URL(fileURLWithPath: currentPath, isDirectory: true)
            if currentURL.pathExtension == "xcodeproj" {
                return currentURL
            }
            if currentPath == "/" {
                return nil
            }
            currentPath = parentPath(of: currentPath)
        }
    }

    /// Searches ancestors for the nearest package manifest.
    private func discoverManifest(near url: URL) -> URL? {
        let fileManager = FileManager.default
        var currentPath = startingAncestorPath(for: url)

        while true {
            let candidate = URL(fileURLWithPath: currentPath, isDirectory: true)
                .appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            if currentPath == "/" {
                return nil
            }
            currentPath = parentPath(of: currentPath)
        }
    }

    /// Chooses the directory that best represents the audit root.
    private func discoverRepositoryRoot(from url: URL) -> URL {
        if url.lastPathComponent == "Package.swift" {
            return url.deletingLastPathComponent()
        }
        if url.pathExtension == "xcodeproj" {
            return url.deletingLastPathComponent()
        }
        return url.hasDirectoryPath ? url : url.deletingLastPathComponent()
    }

    /// Chooses the first ancestor directory to inspect for manifests or project bundles.
    private func startingAncestorPath(for url: URL) -> String {
        let basePath = url.hasDirectoryPath ? url.path : url.deletingLastPathComponent().path
        return basePath.isEmpty ? "/" : basePath
    }

    /// Returns the immediate parent path, stopping cleanly at the filesystem root.
    private func parentPath(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }
}
