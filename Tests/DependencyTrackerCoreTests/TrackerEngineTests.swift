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
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
