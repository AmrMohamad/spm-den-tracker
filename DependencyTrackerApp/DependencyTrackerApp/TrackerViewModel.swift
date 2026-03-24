import Combine
import DependencyTrackerCore
import Foundation

@MainActor
final class TrackerViewModel: ObservableObject {
    @Published var projectPath: String = ""
    @Published private(set) var report: DependencyReport?
    @Published private(set) var findings: [Finding] = []
    @Published private(set) var dependencies: [DependencyAnalysis] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var errorMessage: String?

    private let service: DependencyTrackingService
    private let markdownFormatter = MarkdownReporter()
    private let jsonFormatter = JSONReporter()
    private var analysisTask: Task<Void, Never>?
    private var activeAnalysisID: UUID?

    init(service: DependencyTrackingService) {
        self.service = service
    }

    deinit {
        analysisTask?.cancel()
    }

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

    func exportMarkdown() -> String? {
        guard let report else { return nil }
        return markdownFormatter.format(report)
    }

    func exportJSON() -> String? {
        guard let report else { return nil }
        return jsonFormatter.format(report)
    }
}
