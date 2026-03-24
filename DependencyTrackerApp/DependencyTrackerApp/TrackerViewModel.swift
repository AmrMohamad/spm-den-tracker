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

    init(service: DependencyTrackingService) {
        self.service = service
    }

    deinit {
        analysisTask?.cancel()
    }

    func analyze() {
        let expandedPath = (projectPath as NSString).expandingTildeInPath
        guard !expandedPath.isEmpty else {
            errorMessage = "Select an Xcode project, project directory, or Package.resolved file."
            report = nil
            findings = []
            dependencies = []
            return
        }

        analysisTask?.cancel()
        isAnalyzing = true
        errorMessage = nil

        analysisTask = Task { [service] in
            do {
                let report = try await service.analyze(projectPath: expandedPath)
                await MainActor.run {
                    self.report = report
                    self.findings = report.findings
                    self.dependencies = report.dependencies
                    self.errorMessage = nil
                    self.isAnalyzing = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    self.report = nil
                    self.findings = []
                    self.dependencies = []
                    self.errorMessage = error.localizedDescription
                    self.isAnalyzing = false
                }
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
