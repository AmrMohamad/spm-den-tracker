import DependencyTrackerCore
import Foundation

protocol DependencyTrackingService: Sendable {
    func analyze(projectPath: String) async throws -> DependencyReport
}

struct LiveDependencyTrackingService: DependencyTrackingService, Sendable {
    private let engine: TrackerEngine

    init(engine: TrackerEngine = TrackerEngine(configuration: TrackerConfiguration())) {
        self.engine = engine
    }

    func analyze(projectPath: String) async throws -> DependencyReport {
        try await engine.analyze(projectPath: projectPath)
    }
}
