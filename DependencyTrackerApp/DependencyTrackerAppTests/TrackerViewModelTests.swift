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
        let service = CountingService(mode: .success(sampleWorkspaceReport(rootPath: "/tmp/ignored")))
        let viewModel = TrackerViewModel(service: service)

        viewModel.projectPath = ""
        viewModel.analyze()

        XCTAssertEqual(viewModel.errorMessage, "Select an Xcode project, project directory, or Package.resolved file.")
        XCTAssertNil(viewModel.report)
        XCTAssertFalse(viewModel.isAnalyzing)
        let callCount = await service.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testSuccessfulWorkspaceAnalysisFlattensRowsAndExports() async throws {
        let report = sampleWorkspaceReport(rootPath: "/tmp/AppWorkspace")
        let service = CountingService(mode: .success(report))
        let viewModel = TrackerViewModel(service: service)

        viewModel.projectPath = report.rootPath
        viewModel.analyze()

        try await waitUntil { !viewModel.isAnalyzing }

        XCTAssertEqual(viewModel.report?.rootPath, report.rootPath)
        XCTAssertEqual(viewModel.findingRows, TrackerViewModel.scopedFindings(from: report))
        XCTAssertEqual(viewModel.dependencyRows, TrackerViewModel.scopedDependencies(from: report))
        XCTAssertEqual(viewModel.dependencyRows.count, 2)
        XCTAssertEqual(viewModel.dependencyRows.map(\.scope), ["App", "Tools"])
        XCTAssertEqual(viewModel.findingRows.map(\.scope), [report.rootPath, "App", "Tools"])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.exportMarkdown()?.contains("# SPM Dependency Tracker Workspace Report") == true)
        let json = try XCTUnwrap(viewModel.exportJSON())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(WorkspaceReport.self, from: Data(json.utf8)).rootPath, report.rootPath)
        let graph = try XCTUnwrap(viewModel.exportGraphMermaid())
        XCTAssertTrue(graph.contains("graph TD"))
        XCTAssertTrue(graph.contains("AppWorkspace"))
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
        XCTAssertTrue(viewModel.findingRows.isEmpty)
        XCTAssertTrue(viewModel.dependencyRows.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, TestError.failed.localizedDescription)
    }

    func testLaterAnalysisSupersedesCanceledEarlierTask() async throws {
        let firstReport = sampleWorkspaceReport(rootPath: "/tmp/First")
        let secondReport = sampleWorkspaceReport(rootPath: "/tmp/Second")
        let service = SequencedService(first: firstReport, second: secondReport)
        let viewModel = TrackerViewModel(service: service)

        viewModel.projectPath = firstReport.rootPath
        viewModel.analyze()

        try await Task.sleep(nanoseconds: 100_000_000)

        viewModel.projectPath = secondReport.rootPath
        viewModel.analyze()

        try await waitUntil {
            !viewModel.isAnalyzing && viewModel.report?.rootPath == secondReport.rootPath
        }

        XCTAssertEqual(viewModel.report?.rootPath, secondReport.rootPath)
        XCTAssertEqual(viewModel.dependencyRows, TrackerViewModel.scopedDependencies(from: secondReport))
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
        case success(WorkspaceReport)
        case failure(Error)
    }

    private let mode: Mode
    private(set) var callCount = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func analyze(projectPath: String) async throws -> WorkspaceReport {
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
    private let first: WorkspaceReport
    private let second: WorkspaceReport
    private var callIndex = 0

    init(first: WorkspaceReport, second: WorkspaceReport) {
        self.first = first
        self.second = second
    }

    func analyze(projectPath: String) async throws -> WorkspaceReport {
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

private func sampleWorkspaceReport(rootPath: String) -> WorkspaceReport {
    let appReport = sampleReport(projectPath: "\(rootPath)/App.xcodeproj", identity: "alamofire")
    let toolsReport = sampleReport(projectPath: "\(rootPath)/Tools/Package.swift", identity: "swift-argument-parser")
    let appContext = ResolutionContext(
        key: appReport.resolvedFilePath,
        displayPath: "App",
        resolvedFilePath: appReport.resolvedFilePath,
        manifestPaths: [appReport.projectPath]
    )
    let toolsContext = ResolutionContext(
        key: toolsReport.resolvedFilePath,
        displayPath: "Tools",
        resolvedFilePath: toolsReport.resolvedFilePath,
        manifestPaths: [toolsReport.projectPath]
    )
    let aggregateFinding = Finding(
        severity: .warning,
        category: .declaredConstraint,
        message: "Workspace has dependency drift.",
        recommendation: "Review the workspace contexts."
    )

    return WorkspaceReport(
        rootPath: rootPath,
        generatedAt: Date(timeIntervalSince1970: 0),
        analysisMode: .auto,
        discoveredManifests: [
            DiscoveredManifest(path: appReport.projectPath, kind: .xcodeproj, resolvedFilePath: appReport.resolvedFilePath, ownershipKey: appReport.resolvedFilePath),
            DiscoveredManifest(path: toolsReport.projectPath, kind: .packageManifest, resolvedFilePath: toolsReport.resolvedFilePath, ownershipKey: toolsReport.resolvedFilePath),
        ],
        contexts: [
            ResolutionContextReport(context: appContext, reports: [appReport], findings: appReport.findings, partialFailures: []),
            ResolutionContextReport(context: toolsContext, reports: [toolsReport], findings: toolsReport.findings, partialFailures: []),
        ],
        aggregateFindings: [aggregateFinding],
        partialFailures: [],
        graphSummary: WorkspaceGraphSummary(certainty: .metadataOnly, message: "Topology derived from discovered workspace contexts.")
    )
}

private func sampleReport(projectPath: String, identity: String) -> DependencyReport {
    let pin = ResolvedPin(
        identity: identity,
        kind: .remoteSourceControl,
        location: "https://github.com/example/\(identity).git",
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
