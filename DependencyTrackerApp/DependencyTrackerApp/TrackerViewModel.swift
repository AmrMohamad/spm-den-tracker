import Combine
import DependencyTrackerCore
import Foundation

/// Centralizes the open-panel contract so the GUI picker matches the engine's accepted inputs.
enum ProjectSelectionValidator {
    static let selectionDescription = "Choose an Xcode project, a folder containing one Xcode project, or a Package.resolved file."

    /// Accepts direct `.xcodeproj` packages, direct `Package.resolved` files, and directories.
    static func isSupported(url: URL, fileManager: FileManager = .default) -> Bool {
        guard url.isFileURL else { return false }
        if url.pathExtension == "xcodeproj" || url.lastPathComponent == "Package.resolved" {
            return true
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    static func validationError() -> NSError {
        NSError(
            domain: "DependencyTrackerApp.ProjectSelectionValidator",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: selectionDescription]
        )
    }
}

/// Finding row plus the workspace scope that produced it.
struct ScopedFindingRow: Equatable {
    let scope: String
    let finding: Finding
}

/// Dependency row plus the workspace scope that produced it.
struct ScopedDependencyRow: Equatable {
    let scope: String
    let dependency: DependencyAnalysis
}

@MainActor
/// Main-window view model that coordinates user input, analysis state, and export actions.
final class TrackerViewModel: ObservableObject {
    /// The project path currently shown in the text field.
    @Published var projectPath: String = ""
    /// The most recent successful report, used to power exports and UI tables.
    @Published private(set) var report: WorkspaceReport?
    /// The finding rows currently displayed in the UI.
    @Published private(set) var findingRows: [ScopedFindingRow] = []
    /// The dependency rows currently displayed in the UI.
    @Published private(set) var dependencyRows: [ScopedDependencyRow] = []
    /// Indicates whether an analysis is actively running.
    @Published private(set) var isAnalyzing = false
    /// The latest user-visible error, if the last run failed validation or execution.
    @Published private(set) var errorMessage: String?
    /// Short summary string shown above the findings and dependencies tables.
    @Published private(set) var summaryText = "No report loaded."

    /// Injectable service boundary used by production code and tests.
    private let service: DependencyTrackingService
    /// Formatter reused for markdown export.
    private let markdownFormatter = MarkdownReporter()
    /// Formatter reused for JSON export.
    private let jsonFormatter = JSONReporter()
    /// Formatter reused for graph export.
    private let graphRenderer = WorkspaceGraphRenderer()
    /// The currently running analysis task so it can be cancelled before a new run starts.
    private var analysisTask: Task<Void, Never>?
    /// Identifies the latest requested analysis so stale task completions cannot overwrite newer UI state.
    private var activeAnalysisID: UUID?

    /// Creates a view model backed by the supplied analysis service.
    init(service: DependencyTrackingService) {
        self.service = service
    }

    /// Cancels any in-flight analysis when the view model is torn down.
    deinit {
        analysisTask?.cancel()
    }

    /// Starts a new analysis, cancels any previous one, and ignores stale completions via `activeAnalysisID`.
    ///
    /// The extra `activeAnalysisID` guard matters because cancelling a task does not guarantee that
    /// its asynchronous work will stop before it produces a value. By tagging each request, the
    /// view model prevents an older analysis from racing a newer one and overwriting the UI with
    /// stale findings after the user has already kicked off another run.
    func analyze() {
        let expandedPath = (projectPath as NSString).expandingTildeInPath
        analysisTask?.cancel()

        guard !expandedPath.isEmpty else {
            activeAnalysisID = nil
            analysisTask = nil
            isAnalyzing = false
            errorMessage = "Select an Xcode project, project directory, or Package.resolved file."
            report = nil
            findingRows = []
            dependencyRows = []
            summaryText = "No report loaded."
            return
        }

        let analysisID = UUID()
        activeAnalysisID = analysisID
        isAnalyzing = true
        errorMessage = nil

        analysisTask = Task { [weak self, service] in
            do {
                let report = try await service.analyze(projectPath: expandedPath)
                guard let self, self.activeAnalysisID == analysisID else { return }
                self.activeAnalysisID = nil
                self.report = report
                self.findingRows = Self.scopedFindings(from: report)
                self.dependencyRows = Self.scopedDependencies(from: report)
                self.summaryText = Self.makeSummaryText(report: report)
                self.errorMessage = nil
                self.isAnalyzing = false
            } catch is CancellationError {
                guard let self, self.activeAnalysisID == analysisID else { return }
                self.activeAnalysisID = nil
                self.isAnalyzing = false
            } catch {
                guard let self, self.activeAnalysisID == analysisID else { return }
                self.activeAnalysisID = nil
                self.report = nil
                self.findingRows = []
                self.dependencyRows = []
                self.summaryText = "No report loaded."
                self.errorMessage = error.localizedDescription
                self.isAnalyzing = false
            }
        }
    }

    /// Returns the current report formatted as markdown, or `nil` when no report is loaded.
    ///
    /// The export path is intentionally side-effect free so the window controller can decide when
    /// and where the rendered content should be saved.
    func exportMarkdown() -> String? {
        guard let report else { return nil }
        return markdownFormatter.format(report)
    }

    /// Returns the current report formatted as JSON, or `nil` when no report is loaded.
    ///
    /// Keeping JSON generation here ensures the app and CLI stay aligned on formatter behavior.
    func exportJSON() -> String? {
        guard let report else { return nil }
        return jsonFormatter.format(report)
    }

    /// Returns the current workspace graph as Mermaid text, or `nil` when no report is loaded.
    func exportGraphMermaid() -> String? {
        guard let report else { return nil }
        return graphRenderer.render(report, format: .mermaid)
    }

    /// Builds the summary string shown above the split tables.
    static func makeSummaryText(report: WorkspaceReport) -> String {
        let dependencies = scopedDependencies(from: report).map(\.dependency)
        let findings = scopedFindings(from: report).map(\.finding)
        let dependencyCount = dependencies.count
        let outdatedCount = dependencies.filter { $0.outdated?.isOutdated == true }.count
        let actionableCount = findings.filter(\.isActionable).count
        let partialFailureCount = report.partialFailures.count + report.contexts.flatMap(\.partialFailures).count
        return "\(report.contexts.count) contexts · \(report.discoveredManifests.count) manifests · \(dependencyCount) deps · \(outdatedCount) outdated · \(actionableCount) actionable · \(partialFailureCount) partial failures"
    }

    /// Flattens workspace and context findings while preserving their source scope.
    static func scopedFindings(from report: WorkspaceReport) -> [ScopedFindingRow] {
        let aggregate = report.aggregateFindings.map { finding in
            ScopedFindingRow(scope: report.rootPath, finding: finding)
        }
        let contextual = report.contexts.flatMap { context in
            context.findings.map { finding in
                ScopedFindingRow(scope: context.context.displayPath, finding: finding)
            }
        }
        return aggregate + contextual
    }

    /// Flattens all dependency rows from all context reports while preserving their source scope.
    static func scopedDependencies(from report: WorkspaceReport) -> [ScopedDependencyRow] {
        report.contexts.flatMap { context in
            context.reports.flatMap { dependencyReport in
                dependencyReport.dependencies.map { dependency in
                    ScopedDependencyRow(scope: context.context.displayPath, dependency: dependency)
                }
            }
        }
    }
}
