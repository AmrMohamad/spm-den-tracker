import ArgumentParser
import Foundation
import Testing
@testable import DependencyTrackerCLI

struct CLITests {
    @Test
    func invalidPathWritesToStandardError() async throws {
        var errors: [String] = []

        do {
            _ = try await Doctor.execute(
                projectPath: "/tmp/does-not-exist.xcodeproj",
                write: { _ in },
                writeError: { errors.append($0) }
            )
            Issue.record("Expected invalid-path exit code.")
        } catch let error as ExitCode {
            #expect(error == ExitCode(65))
        }

        #expect(errors == ["Invalid project path: /tmp/does-not-exist.xcodeproj"])
    }

    @Test
    func doctorReportsMissingResolvedFile() async throws {
        let projectURL = try makeProjectDirectory()
        var outputs: [String] = []

        let exitCode = try await Doctor.execute(
            projectPath: projectURL.path,
            write: { outputs.append($0) },
            writeError: { _ in }
        )

        #expect(exitCode == ExitCode(1))
        #expect(outputs.joined(separator: "\n").contains("Package.resolved is missing."))
    }

    @Test
    func reportWritesStructuredOutputToDisk() async throws {
        let projectURL = try makeProjectDirectory()
        let outputURL = projectURL.deletingLastPathComponent()
            .appendingPathComponent("Reports", isDirectory: true)
            .appendingPathComponent("dependency-report.json")

        let exitCode = try await Report.execute(
            projectPath: projectURL.path,
            format: .json,
            output: outputURL.path,
            write: { _ in },
            writeError: { _ in }
        )

        let contents = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(exitCode == ExitCode(1))
        #expect(contents.contains("\"resolvedFileStatus\""))
        #expect(contents.contains("\"missing\""))
    }

    @Test
    func checkTrackingRendersMissingStatus() async throws {
        let projectURL = try makeProjectDirectory()
        var outputs: [String] = []

        let exitCode = try await CheckTracking.execute(
            projectPath: projectURL.path,
            write: { outputs.append($0) },
            writeError: { _ in }
        )

        #expect(exitCode == ExitCode(2))
        #expect(outputs == ["\(projectURL.path)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved: missing"])
    }
}

private func makeProjectDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let projectURL = directory.appendingPathComponent("Sample.xcodeproj", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
    return projectURL
}
