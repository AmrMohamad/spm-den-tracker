import Combine
import DependencyTrackerCore
import Foundation

@MainActor
/// Main-window view model that coordinates user input, analysis state, and export actions.
final class TrackerViewModel: ObservableObject {
    /// The project path currently shown in the text field.
    @Published var projectPath: String = ""
    /// The most recent successful report, used to power exports and UI tables.
    @Published private(set) var report: DependencyReport?
    /// The finding rows currently displayed in the UI.
    @Published private(set) var findings: [Finding] = []
    /// The dependency rows currently displayed in the UI.
    @Published private(set) var dependencies: [DependencyAnalysis] = []
    /// Indicates whether an analysis is actively running.
    @Published private(set) var isAnalyzing = false
    /// The latest user-visible error, if the last run failed validation or execution.
    @Published private(set) var errorMessage: String?

    /// Injectable service boundary used by production code and tests.
    private let service: DependencyTrackingService
    /// Formatter reused for markdown export.
    private let markdownFormatter = MarkdownReporter()
    /// Formatter reused for JSON export.
    private let jsonFormatter = JSONReporter()
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
            findings = []
            dependencies = []
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
                self.findings = report.findings
                self.dependencies = report.dependencies
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
                self.findings = []
                self.dependencies = []
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
}
