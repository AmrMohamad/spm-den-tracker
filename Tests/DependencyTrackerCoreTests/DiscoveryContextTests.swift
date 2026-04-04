import Foundation
import Testing
@testable import DependencyTrackerCore

struct DiscoveryContextTests {
    @Test
    func manifestIndexDiscoversManifestsAndAppliesIgnoreRules() throws {
        let root = try temporaryDirectory()
        try writeFixtureIgnoreFile(into: root)

        let xcodeproj = root.appendingPathComponent("App.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)

        let workspace = root.appendingPathComponent("Shared.xcworkspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let packageRoot = root.appendingPathComponent("Feature", isDirectory: true)
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        try "import PackageDescription\nlet package = Package(name: \"Feature\")\n".write(
            to: packageRoot.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "{\"version\":3,\"pins\":[]}".write(
            to: packageRoot.appendingPathComponent("Package.resolved"),
            atomically: true,
            encoding: .utf8
        )

        let ignoredWorkspace = root.appendingPathComponent("Ignored.xcworkspace", isDirectory: true)
        try FileManager.default.createDirectory(at: ignoredWorkspace, withIntermediateDirectories: true)

        let ignoredDirectory = root.appendingPathComponent("DerivedData", isDirectory: true)
        try FileManager.default.createDirectory(at: ignoredDirectory, withIntermediateDirectories: true)
        try "import PackageDescription\nlet package = Package(name: \"Ignored\")\n".write(
            to: ignoredDirectory.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let alias = root.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            atPath: alias.path,
            withDestinationPath: packageRoot.path
        )

        let index = ManifestIndex(maxDepth: 10)
        let discovered = try index.discover(from: root.path)

        let discoveredKinds = discovered.map(\.kind)
        #expect(discoveredKinds == [.xcodeproj, .xcworkspace, .packageManifest, .resolvedFile])
        #expect(discovered.map(\.path).contains(packageRoot.appendingPathComponent("Package.swift").standardizedFileURL.resolvingSymlinksInPath().path))
        #expect(discovered.map(\.path).contains(packageRoot.appendingPathComponent("Package.resolved").standardizedFileURL.resolvingSymlinksInPath().path))
        #expect(!discovered.map(\.path).contains(ignoredWorkspace.standardizedFileURL.resolvingSymlinksInPath().path))
        #expect(!discovered.map(\.path).contains(ignoredDirectory.appendingPathComponent("Package.swift").standardizedFileURL.resolvingSymlinksInPath().path))

        let packageEntries = discovered.filter { $0.kind == .packageManifest }
        #expect(packageEntries.count == 1)
        #expect(packageEntries.first?.ownershipKey == packageRoot.appendingPathComponent("Package.resolved").standardizedFileURL.resolvingSymlinksInPath().path)

        let resolvedEntries = discovered.filter { $0.kind == .resolvedFile }
        #expect(resolvedEntries.count == 1)
        #expect(resolvedEntries.first?.ownershipKey == packageRoot.appendingPathComponent("Package.resolved").standardizedFileURL.resolvingSymlinksInPath().path)

        let xcodeprojEntry = discovered.first { $0.kind == .xcodeproj }
        #expect(
            xcodeprojEntry?.resolvedFilePath?.hasSuffix(
                "/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            ) == true
        )
    }

    @Test
    func manifestIndexHonorsDepthLimits() throws {
        let root = try temporaryDirectory()
        let nested = root.appendingPathComponent("A/B/C", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "import PackageDescription\nlet package = Package(name: \"Deep\")\n".write(
            to: nested.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let index = ManifestIndex(maxDepth: 1)
        let discovered = try index.discover(from: root.path)

        #expect(discovered.isEmpty)
    }

    @Test
    func resolutionContextDetectorGroupsByOwnershipKey() throws {
        let appResolved = "/tmp/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved".canonical
        let featureResolved = "/tmp/Feature/Package.resolved".canonical

        let manifests: [DiscoveredManifest] = [
            DiscoveredManifest(
                path: "/tmp/App.xcodeproj".canonical,
                kind: .xcodeproj,
                resolvedFilePath: appResolved,
                ownershipKey: appResolved
            ),
            DiscoveredManifest(
                path: "/tmp/Feature/Package.swift".canonical,
                kind: .packageManifest,
                resolvedFilePath: featureResolved,
                ownershipKey: featureResolved
            ),
            DiscoveredManifest(
                path: "/tmp/Feature/Package.resolved".canonical,
                kind: .resolvedFile,
                resolvedFilePath: featureResolved,
                ownershipKey: featureResolved
            )
        ]

        let detector = ResolutionContextDetector()
        let contexts = detector.detect(from: manifests)

        #expect(contexts.count == 2)

        let featureContext = contexts.first { $0.key == featureResolved }
        #expect(featureContext?.manifestPaths == ["/tmp/Feature/Package.swift".canonical, "/tmp/Feature/Package.resolved".canonical])
        #expect(featureContext?.resolvedFilePath == featureResolved)
        #expect(featureContext?.displayPath == "/tmp/Feature/Package.swift".canonical)

        let appContext = contexts.first { $0.key == appResolved }
        #expect(appContext?.manifestPaths == ["/tmp/App.xcodeproj".canonical])
        #expect(appContext?.resolvedFilePath == appResolved)
    }
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func writeFixtureIgnoreFile(into directory: URL) throws {
    let source = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/WorkspaceDiscovery/root-ignore.txt")
    let contents = try String(contentsOf: source, encoding: .utf8)
    try contents.write(to: directory.appendingPathComponent(".spm-dep-tracker-ignore"), atomically: true, encoding: .utf8)
}

private extension String {
    var canonical: String {
        URL(fileURLWithPath: self).standardizedFileURL.resolvingSymlinksInPath().path
    }

}
