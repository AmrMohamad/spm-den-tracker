import Foundation

public struct TrackerEngine: Sendable {
    public let configuration: TrackerConfiguration

    private let locator: XcodeprojLocator
    private let parser: ResolvedFileParser
    private let schemaChecker: SchemaVersionChecker
    private let gitTrackingAuditor: GitTrackingAuditor
    private let strategyAuditor: RequirementStrategyAuditor
    private let outdatedChecker: OutdatedChecker

    public init(configuration: TrackerConfiguration) {
        let gitClient = GitClient(timeout: configuration.timeout)
        self.configuration = configuration
        self.locator = XcodeprojLocator()
        self.parser = ResolvedFileParser()
        self.schemaChecker = SchemaVersionChecker()
        self.gitTrackingAuditor = GitTrackingAuditor(gitClient: gitClient)
        self.strategyAuditor = RequirementStrategyAuditor()
        self.outdatedChecker = OutdatedChecker(gitClient: gitClient, concurrentFetchLimit: configuration.concurrentFetchLimit)
    }

    public func analyze(projectPath: String) async throws -> DependencyReport {
        let resolvedFileURL = try await locateResolvedFile(at: projectPath)
        let pins = try parseResolved(at: resolvedFileURL)
        let fileStatus = configuration.checkGitTracking ? try await auditGitTracking(resolvedFileURL: resolvedFileURL) : .tracked
        let schema = try checkSchemaVersion(at: resolvedFileURL)
        let strategyFindings = auditRequirementStrategies(pins)
        let outdated = configuration.checkOutdated ? await checkOutdated(pins) : []

        let outdatedByIdentity = Dictionary(uniqueKeysWithValues: outdated.map { ($0.pin.identity, $0) })
        let riskByIdentity = Dictionary(uniqueKeysWithValues: strategyFindings.map { ($0.pin.identity, $0.risk) })

        let dependencies = pins.map { pin in
            DependencyAnalysis(
                pin: pin,
                outdated: outdatedByIdentity[pin.identity],
                strategyRisk: riskByIdentity[pin.identity] ?? .normal
            )
        }.sorted { $0.pin.identity < $1.pin.identity }

        let findings = makeFindings(
            status: fileStatus,
            schema: schema,
            strategyFindings: strategyFindings,
            outdatedResults: outdated
        )

        return DependencyReport(
            projectPath: projectPath,
            generatedAt: Date(),
            resolvedFilePath: resolvedFileURL.path,
            resolvedFileStatus: fileStatus,
            schemaVersion: schema,
            dependencies: dependencies,
            findings: findings
        )
    }

    public func locateResolvedFile(at path: String) async throws -> URL {
        try locator.locateResolvedFile(at: path)
    }

    public func parseResolved(at url: URL) throws -> [ResolvedPin] {
        try parser.parse(at: url)
    }

    public func auditGitTracking(resolvedFileURL: URL) async throws -> ResolvedFileStatus {
        try gitTrackingAuditor.audit(resolvedFileURL: resolvedFileURL)
    }

    public func checkSchemaVersion(at url: URL) throws -> SchemaInfo {
        try schemaChecker.check(at: url)
    }

    public func checkOutdated(_ pins: [ResolvedPin]) async -> [OutdatedResult] {
        await outdatedChecker.check(pins)
    }

    public func auditRequirementStrategies(_ pins: [ResolvedPin]) -> [StrategyFinding] {
        strategyAuditor.audit(pins)
    }

    private func makeFindings(
        status: ResolvedFileStatus,
        schema: SchemaInfo,
        strategyFindings: [StrategyFinding],
        outdatedResults: [OutdatedResult]
    ) -> [Finding] {
        var findings: [Finding] = []

        switch status {
        case .tracked:
            break
        case .missing:
            findings.append(Finding(
                severity: .error,
                category: .gitTracking,
                message: "Package.resolved is missing.",
                recommendation: "Open the project in Xcode and resolve packages, then commit the file."
            ))
        case .untracked:
            findings.append(Finding(
                severity: .warning,
                category: .gitTracking,
                message: "Package.resolved exists but is not tracked by git.",
                recommendation: "Add the file to git so CI and developers build against the same dependency lock."
            ))
        case .gitignored(let match):
            findings.append(Finding(
                severity: .error,
                category: .gitTracking,
                message: "Package.resolved is gitignored by rule \"\(match.pattern)\" on line \(match.line).",
                recommendation: "Add an exception for the resolved file path or stop ignoring the containing workspace metadata."
            ))
        }

        if schema.compatibility == .legacy {
            findings.append(Finding(
                severity: .warning,
                category: .schema,
                message: schema.message,
                recommendation: "Verify whether your CI and developer machines intentionally support older Xcode schema output."
            ))
        } else {
            findings.append(Finding(
                severity: .info,
                category: .schema,
                message: schema.message,
                recommendation: "Keep Xcode versions aligned across local development and CI."
            ))
        }

        for strategyFinding in strategyFindings where strategyFinding.risk != .normal {
            findings.append(Finding(
                severity: strategyFinding.risk == .environmentSensitive ? .warning : .warning,
                category: .pinStrategy,
                message: strategyFinding.message,
                recommendation: recommendation(for: strategyFinding.risk)
            ))
        }

        let outdatedCount = outdatedResults.filter(\.isOutdated).count
        if outdatedCount > 0 {
            findings.append(Finding(
                severity: .info,
                category: .outdated,
                message: "\(outdatedCount) dependencies have newer upstream versions available.",
                recommendation: "Review the dependency table and schedule upgrades based on semantic-version impact."
            ))
        }

        for result in outdatedResults where result.note != nil {
            findings.append(Finding(
                severity: .warning,
                category: .outdated,
                message: "Unable to fully assess updates for \"\(result.pin.identity)\": \(result.note ?? "unknown reason").",
                recommendation: "Verify the remote repository is reachable and publishes stable semantic tags."
            ))
        }

        return findings.sorted(by: findingSort)
    }

    private func recommendation(for risk: StrategyRisk) -> String {
        switch risk {
        case .normal:
            return "No action needed."
        case .elevated:
            return "Prefer semantic version requirements where possible, and rely on Package.resolved for reproducibility."
        case .environmentSensitive:
            return "Avoid local path dependencies for shared or CI builds unless the same path layout exists everywhere."
        }
    }

    private func findingSort(lhs: Finding, rhs: Finding) -> Bool {
        let severityOrder: [Severity: Int] = [.error: 0, .warning: 1, .info: 2]
        let categoryOrder: [FindingCategory: Int] = [.gitTracking: 0, .schema: 1, .pinStrategy: 2, .outdated: 3]
        let lhsSeverity = severityOrder[lhs.severity] ?? 99
        let rhsSeverity = severityOrder[rhs.severity] ?? 99
        if lhsSeverity != rhsSeverity {
            return lhsSeverity < rhsSeverity
        }
        let lhsCategory = categoryOrder[lhs.category] ?? 99
        let rhsCategory = categoryOrder[rhs.category] ?? 99
        if lhsCategory != rhsCategory {
            return lhsCategory < rhsCategory
        }
        return lhs.message < rhs.message
    }
}
