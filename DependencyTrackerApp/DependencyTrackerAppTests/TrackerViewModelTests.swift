import XCTest
import DependencyTrackerCore

@MainActor
final class TrackerViewModelTests: XCTestCase {
    func testProjectSelectionValidatorAcceptsSupportedInputShapes() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folderURL = temp.appendingPathComponent("RepoRoot", isDirectory: true)
        let projectURL = temp.appendingPathComponent("Sample.xcodeproj", isDirectory: true)
        let resolvedURL = temp.appendingPathComponent("Package.resolved")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try "{}".write(to: resolvedURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(ProjectSelectionValidator.isSupported(url: folderURL))
        XCTAssertTrue(ProjectSelectionValidator.isSupported(url: projectURL))
        XCTAssertTrue(ProjectSelectionValidator.isSupported(url: resolvedURL))
    }

    func testProjectSelectionValidatorRejectsUnsupportedFiles() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temp.appendingPathComponent("notes.txt")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertFalse(ProjectSelectionValidator.isSupported(url: fileURL))
    }

    func testEmptyInputSetsValidationErrorWithoutCallingService() async throws {
        let service = CountingService(mode: .success(sampleReport(projectPath: "/tmp/ignored.xcodeproj")))
        let viewModel = TrackerViewModel(service: service)

        viewModel.projectPath = ""
        viewModel.analyze()

        XCTAssertEqual(viewModel.errorMessage, "Select an Xcode project, project directory, or Package.resolved file.")
        XCTAssertNil(viewModel.report)
        XCTAssertFalse(viewModel.isAnalyzing)
        let callCount = await service.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testSuccessfulAnalysisPopulatesReportAndExports() async throws {
        let report = sampleReport(projectPath: "/tmp/App.xcodeproj")
        let service = CountingService(mode: .success(report))
        let viewModel = TrackerViewModel(service: service)

        viewModel.projectPath = report.projectPath
        viewModel.analyze()

        try await waitUntil { !viewModel.isAnalyzing }

        XCTAssertEqual(viewModel.report?.projectPath, report.projectPath)
        XCTAssertEqual(viewModel.findings, report.findings)
        XCTAssertEqual(viewModel.dependencies, report.dependencies)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.exportMarkdown()?.contains("# SPM Dependency Report") == true)
        let json = try XCTUnwrap(viewModel.exportJSON())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(DependencyReport.self, from: Data(json.utf8)).projectPath, report.projectPath)
        let callCount = await service.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testFailedAnalysisClearsReportAndShowsError() async throws {
        let service = CountingService(mode: .failure(TestError.failed))
        let viewModel = TrackerViewModel(service: service)

        viewModel.projectPath = "/tmp/App.xcodeproj"
        viewModel.analyze()

        try await waitUntil { !viewModel.isAnalyzing }

        XCTAssertNil(viewModel.report)
        XCTAssertTrue(viewModel.findings.isEmpty)
        XCTAssertTrue(viewModel.dependencies.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, TestError.failed.localizedDescription)
    }

    func testLaterAnalysisSupersedesCanceledEarlierTask() async throws {
        let firstReport = sampleReport(projectPath: "/tmp/First.xcodeproj")
        let secondReport = sampleReport(projectPath: "/tmp/Second.xcodeproj")
        let service = SequencedService(first: firstReport, second: secondReport)
        let viewModel = TrackerViewModel(service: service)

        viewModel.projectPath = firstReport.projectPath
        viewModel.analyze()

        try await Task.sleep(nanoseconds: 100_000_000)

        viewModel.projectPath = secondReport.projectPath
        viewModel.analyze()

        try await waitUntil {
            !viewModel.isAnalyzing && viewModel.report?.projectPath == secondReport.projectPath
        }

        XCTAssertEqual(viewModel.report?.projectPath, secondReport.projectPath)
        XCTAssertEqual(viewModel.dependencies, secondReport.dependencies)
        XCTAssertNil(viewModel.errorMessage)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds > deadline {
                XCTFail("Timed out waiting for condition.")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private actor CountingService: DependencyTrackingService {
    enum Mode {
        case success(DependencyReport)
        case failure(Error)
    }

    private let mode: Mode
    private(set) var callCount = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func analyze(projectPath: String) async throws -> DependencyReport {
        callCount += 1
        switch mode {
        case .success(let report):
            return report
        case .failure(let error):
            throw error
        }
    }
}

private actor SequencedService: DependencyTrackingService {
    private let first: DependencyReport
    private let second: DependencyReport
    private var callIndex = 0

    init(first: DependencyReport, second: DependencyReport) {
        self.first = first
        self.second = second
    }

    func analyze(projectPath: String) async throws -> DependencyReport {
        callIndex += 1
        if callIndex == 1 {
            try await Task.sleep(nanoseconds: 500_000_000)
            return first
        }
        return second
    }
}

private enum TestError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Analysis failed."
    }
}

private func sampleReport(projectPath: String) -> DependencyReport {
    let pin = ResolvedPin(
        identity: "alamofire",
        kind: .remoteSourceControl,
        location: "https://github.com/Alamofire/Alamofire.git",
        state: .version("5.9.1", revision: "abc")
    )
    let outdated = OutdatedResult(pin: pin, latestVersion: "5.10.0", updateType: .minor, isOutdated: true)
    return DependencyReport(
        projectPath: projectPath,
        generatedAt: Date(timeIntervalSince1970: 0),
        resolvedFilePath: "\(projectPath)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        resolvedFileStatus: .tracked,
        schemaVersion: SchemaInfo(version: 3, compatibility: .modern, message: "Schema version 3 is the modern Xcode 15+ format."),
        dependencies: [DependencyAnalysis(pin: pin, outdated: outdated, strategyRisk: .normal)],
        findings: [Finding(severity: .info, category: .outdated, message: "1 dependency has an update.", recommendation: "Review the dependency table.")]
    )
}
