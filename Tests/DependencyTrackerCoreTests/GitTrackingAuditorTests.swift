import Foundation
import Testing
@testable import DependencyTrackerCore

struct GitTrackingAuditorTests {
    @Test
    func locatorResolvesXcodeprojPath() throws {
        let temp = try temporaryDirectory()
        let projectURL = temp.appendingPathComponent("Sample.xcodeproj", isDirectory: true)
        let resolvedURL = projectURL
            .appendingPathComponent("project.xcworkspace", isDirectory: true)
            .appendingPathComponent("xcshareddata", isDirectory: true)
            .appendingPathComponent("swiftpm", isDirectory: true)
            .appendingPathComponent("Package.resolved")
        try FileManager.default.createDirectory(at: resolvedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: resolvedURL.path, contents: Data())

        let located = try XcodeprojLocator().locateResolvedFile(at: projectURL.path)
        #expect(located == resolvedURL)
    }

    @Test
    func locatorResolvesDirectResolvedFilePath() throws {
        let temp = try temporaryDirectory()
        let resolvedURL = temp
            .appendingPathComponent("Sample.xcodeproj", isDirectory: true)
            .appendingPathComponent("project.xcworkspace", isDirectory: true)
            .appendingPathComponent("xcshareddata", isDirectory: true)
            .appendingPathComponent("swiftpm", isDirectory: true)
            .appendingPathComponent("Package.resolved")
        try FileManager.default.createDirectory(at: resolvedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: resolvedURL.path, contents: Data())

        let located = try XcodeprojLocator().locateResolvedFile(at: resolvedURL.path)
        #expect(located == resolvedURL)
    }

    @Test
    func locatorResolvesDirectoryWithSingleProject() throws {
        let temp = try temporaryDirectory()
        let projectURL = temp.appendingPathComponent("Sample.xcodeproj", isDirectory: true)
        let resolvedURL = projectURL
            .appendingPathComponent("project.xcworkspace", isDirectory: true)
            .appendingPathComponent("xcshareddata", isDirectory: true)
            .appendingPathComponent("swiftpm", isDirectory: true)
            .appendingPathComponent("Package.resolved")
        try FileManager.default.createDirectory(at: resolvedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: resolvedURL.path, contents: Data())

        let located = try XcodeprojLocator().locateResolvedFile(at: temp.path)
        #expect(located.standardizedFileURL == resolvedURL.standardizedFileURL)
    }

    @Test
    func locatorResolvesPackageManifestPath() throws {
        let temp = try temporaryDirectory()
        let manifestURL = temp.appendingPathComponent("Package.swift")
        try "import PackageDescription\nlet package = Package(name: \"Sample\")\n".write(
            to: manifestURL,
            atomically: true,
            encoding: .utf8
        )

        let target = try XcodeprojLocator().locateAuditTarget(at: manifestURL.path)

        #expect(target.manifestURL == manifestURL)
        #expect(target.projectFileURL == nil)
        #expect(target.resolvedFileURL == temp.appendingPathComponent("Package.resolved"))
    }

    @Test
    func locatorRejectsAmbiguousDirectory() throws {
        let temp = try temporaryDirectory()
        try FileManager.default.createDirectory(at: temp.appendingPathComponent("One.xcodeproj"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temp.appendingPathComponent("Two.xcodeproj"), withIntermediateDirectories: true)

        #expect(throws: DependencyTrackerError.self) {
            try XcodeprojLocator().locateResolvedFile(at: temp.path)
        }
    }

    @Test
    func trackedFileIsReportedAsTracked() async throws {
        let context = try makeRepositoryContext()
        try runProcess(["git", "add", context.resolvedFile.path], in: context.root)

        let auditor = GitTrackingAuditor(gitClient: GitClient(timeout: 5))
        let status = try await auditor.audit(resolvedFileURL: context.resolvedFile)

        #expect(status.isTracked)
    }

    @Test
    func ignoredFileReportsRuleMetadata() async throws {
        let context = try makeRepositoryContext()
        try "*.xcworkspace\n".write(to: context.root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        let auditor = GitTrackingAuditor(gitClient: GitClient(timeout: 5))
        let status = try await auditor.audit(resolvedFileURL: context.resolvedFile)

        guard case .gitignored(let match) = status else {
            Issue.record("Expected gitignored status, got \(status)")
            return
        }

        #expect(match.pattern == "*.xcworkspace")
    }

    @Test
    func existingButUntrackedFileIsReportedAsUntracked() async throws {
        let context = try makeRepositoryContext()

        let auditor = GitTrackingAuditor(gitClient: GitClient(timeout: 5))
        let status = try await auditor.audit(resolvedFileURL: context.resolvedFile)

        #expect(status == .untracked)
    }

    @Test
    func missingFileIsReportedAsMissing() async throws {
        let temp = try temporaryDirectory()
        let missing = temp.appendingPathComponent("Missing.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")

        let auditor = GitTrackingAuditor(gitClient: GitClient(timeout: 5))
        let status = try await auditor.audit(resolvedFileURL: missing)

        #expect(status == .missing)
    }
}

private struct RepositoryContext {
    let root: URL
    let resolvedFile: URL
}

private func makeRepositoryContext() throws -> RepositoryContext {
    let root = try temporaryDirectory()
    try runProcess(["git", "init", "-b", "main"], in: root)
    let resolvedFile = root
        .appendingPathComponent("Sample.xcodeproj", isDirectory: true)
        .appendingPathComponent("project.xcworkspace", isDirectory: true)
        .appendingPathComponent("xcshareddata", isDirectory: true)
        .appendingPathComponent("swiftpm", isDirectory: true)
        .appendingPathComponent("Package.resolved")
    try FileManager.default.createDirectory(at: resolvedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    let payload = """
    {"version":3,"pins":[]}
    """
    try payload.write(to: resolvedFile, atomically: true, encoding: .utf8)
    return RepositoryContext(root: root, resolvedFile: resolvedFile)
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
private func runProcess(_ arguments: [String], in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = directory

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(process.terminationStatus == 0, Comment(rawValue: "Command failed: \(arguments.joined(separator: " "))\n\(error)"))
    return output
}
