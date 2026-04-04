import Foundation
import Testing
@testable import DependencyTrackerCore

struct TrackerEngineTests {
    @Test
    func missingResolvedFileProducesStructuredReport() async throws {
        let directory = try temporaryDirectory()
        let projectURL = directory.appendingPathComponent("Sample.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let report = try await TrackerEngine(configuration: TrackerConfiguration(checkOutdated: false, timeout: 2))
            .analyze(projectPath: projectURL.path)

        #expect(report.resolvedFileStatus == .missing)
        #expect(report.schemaVersion == nil)
        #expect(report.dependencies.isEmpty)
        #expect(report.findings.contains { $0.message == "Package.resolved is missing." && $0.severity == .error })
    }

    @Test
    func schemaVersion1ResolvedFileProducesStructuredLegacyReport() async throws {
        let directory = try temporaryDirectory()
        let resolvedURL = directory.appendingPathComponent("Package.resolved")
        try """
        {
          "object": {
            "pins": [
              {
                "package": "alamofire",
                "repositoryURL": "https://github.com/Alamofire/Alamofire.git",
                "state": {
                  "branch": null,
                  "revision": "1111111111111111111111111111111111111111",
                  "version": "5.9.1"
                }
              }
            ]
          },
          "version": 1
        }
        """.write(to: resolvedURL, atomically: true, encoding: .utf8)

        let report = try await TrackerEngine(
            configuration: TrackerConfiguration(
                checkOutdated: false,
                checkDeclaredConstraints: false,
                timeout: 2
            )
        ).analyze(projectPath: resolvedURL.path)

        #expect(report.resolvedFilePath == resolvedURL.path)
        #expect(report.schemaVersion?.version == 1)
        #expect(report.schemaVersion?.compatibility == .legacy)
        #expect(report.dependencies.count == 1)
        #expect(report.dependencies[0].pin.identity == "alamofire")
        #expect(report.findings.contains { $0.category == .schema && $0.message.contains("Schema version 1") })
    }
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
