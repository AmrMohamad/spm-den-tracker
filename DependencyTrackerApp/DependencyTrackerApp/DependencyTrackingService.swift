import DependencyTrackerCore
import Foundation

/// Abstracts report generation away from the view model so the UI can be tested without real git/process work.
protocol DependencyTrackingService: Sendable {
    /// Runs the dependency audit for the supplied project path.
    func analyze(projectPath: String) async throws -> DependencyReport
}

/// Production service that forwards requests to the core engine.
struct LiveDependencyTrackingService: DependencyTrackingService, Sendable {
    /// The core engine used to execute the audit pipeline.
    private let engine: TrackerEngine

    /// Creates a live service with the default tracker configuration unless a custom engine is injected.
    init(engine: TrackerEngine = TrackerEngine(configuration: TrackerConfiguration())) {
        self.engine = engine
    }

    /// Runs the audit through the shared engine.
    func analyze(projectPath: String) async throws -> DependencyReport {
        try await engine.analyze(projectPath: projectPath)
    }
}
