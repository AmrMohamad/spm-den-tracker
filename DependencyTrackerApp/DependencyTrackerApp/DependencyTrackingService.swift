import DependencyTrackerCore
import Foundation

/// Abstracts report generation away from the view model so the UI can be tested without real git/process work.
protocol DependencyTrackingService: Sendable {
    /// Runs the dependency audit for the supplied project path.
    func analyze(projectPath: String) async throws -> WorkspaceReport
}

/// Production service that forwards requests to the core engine.
struct LiveDependencyTrackingService: DependencyTrackingService, Sendable {
    /// The core engine used to execute the audit pipeline.
    private let engine: WorkspaceAuditEngine

    /// Creates a live service with the default workspace tracker configuration unless a custom engine is injected.
    init(engine: WorkspaceAuditEngine = WorkspaceAuditEngine(configuration: TrackerConfiguration(analysisMode: .auto))) {
        self.engine = engine
    }

    /// Runs the audit through the shared engine.
    func analyze(projectPath: String) async throws -> WorkspaceReport {
        try await engine.analyze(rootPath: projectPath)
    }
}
