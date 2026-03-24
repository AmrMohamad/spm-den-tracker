import Foundation

struct XcodeprojLocator: Sendable {
    func locateResolvedFile(at rawPath: String) throws -> URL {
        let fileManager = FileManager.default
        let inputURL = URL(fileURLWithPath: rawPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            throw DependencyTrackerError.invalidPath(rawPath)
        }

        if inputURL.lastPathComponent == "Package.resolved" {
            return inputURL
        }

        if inputURL.pathExtension == "xcodeproj" {
            return resolvedURL(forProject: inputURL)
        }

        if isDirectory.boolValue {
            let candidates = try xcodeprojCandidates(in: inputURL)
            guard let first = candidates.first else {
                throw DependencyTrackerError.invalidPath(rawPath)
            }
            guard candidates.count == 1 else {
                throw DependencyTrackerError.ambiguousProjectPath(rawPath, candidates: candidates.map(\.path))
            }
            return resolvedURL(forProject: first)
        }

        throw DependencyTrackerError.invalidPath(rawPath)
    }

    private func resolvedURL(forProject projectURL: URL) -> URL {
        projectURL
            .appendingPathComponent("project.xcworkspace", isDirectory: true)
            .appendingPathComponent("xcshareddata", isDirectory: true)
            .appendingPathComponent("swiftpm", isDirectory: true)
            .appendingPathComponent("Package.resolved")
    }

    private func xcodeprojCandidates(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let candidates = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "xcodeproj" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return candidates
    }
}
