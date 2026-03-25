import Foundation

/// Coordinates the full dependency-audit pipeline from path resolution through report assembly.
public struct TrackerEngine: Sendable {
    /// The runtime settings that control which audit stages execute.
    public let configuration: TrackerConfiguration

    private let locator: XcodeprojLocator
    private let parser: ResolvedFileParser
    private let schemaChecker: SchemaVersionChecker
    private let gitTrackingAuditor: GitTrackingAuditor
    private let strategyAuditor: RequirementStrategyAuditor
    private let declaredRequirementLoader: DeclaredRequirementLoader
    private let declaredConstraintAnalyzer: DeclaredConstraintAnalyzer
    private let outdatedChecker: OutdatedChecker

    /// Builds an engine with shared helpers derived from the supplied configuration.
    public init(configuration: TrackerConfiguration) {
        let gitClient = GitClient(timeout: configuration.timeout)
        let versionCatalog = RemoteVersionCatalog(gitClient: gitClient)
        self.configuration = configuration
        self.locator = XcodeprojLocator()
        self.parser = ResolvedFileParser()
        self.schemaChecker = SchemaVersionChecker()
        self.gitTrackingAuditor = GitTrackingAuditor(gitClient: gitClient)
        self.strategyAuditor = RequirementStrategyAuditor()
        self.declaredRequirementLoader = DeclaredRequirementLoader()
        self.declaredConstraintAnalyzer = DeclaredConstraintAnalyzer(
            versionCatalog: versionCatalog,
            strictConstraints: configuration.strictConstraints,
            concurrentFetchLimit: configuration.concurrentFetchLimit
        )
        self.outdatedChecker = OutdatedChecker(
            versionCatalog: versionCatalog,
            concurrentFetchLimit: configuration.concurrentFetchLimit
        )
    }

    /// Runs the full audit pipeline and returns a report suitable for the CLI or app UI.
    ///
    /// The method first resolves the user-provided path to the expected `Package.resolved`
    /// location, then derives the file's git status, parses dependency pins, classifies the
    /// schema version, audits pinning strategy risk, and optionally performs remote outdated
    /// checks. Each stage feeds a single `DependencyReport` so callers do not need to manually
    /// coordinate partial results.
    ///
    /// - Parameter projectPath: A project bundle path, containing directory, or direct
    ///   `Package.resolved` path provided by the user.
    /// - Returns: A fully assembled dependency report, even when the resolved file is missing.
    /// - Throws: `DependencyTrackerError` when the path cannot be resolved or the file cannot
    ///   be parsed, plus any process-level failures surfaced by the support layer.
    public func analyze(projectPath: String) async throws -> DependencyReport {
        let auditTarget = try locateAuditTarget(at: projectPath)
        let fileStatus = try await resolvedFileStatus(for: auditTarget.resolvedFileURL)

        guard fileStatus != .missing else {
            let findings = makeFindings(
                status: fileStatus,
                schema: nil,
                strategyFindings: [],
                outdatedResults: [],
                constraintAssessments: []
            )

            return DependencyReport(
                projectPath: projectPath,
                generatedAt: Date(),
                resolvedFilePath: auditTarget.resolvedFileURL.path,
                resolvedFileStatus: fileStatus,
                schemaVersion: nil,
                dependencies: [],
                findings: findings
            )
        }

        let pins = try parseResolved(at: auditTarget.resolvedFileURL)
        let schema = try checkSchemaVersion(at: auditTarget.resolvedFileURL)
        let strategyFindings = auditRequirementStrategies(pins)
        let outdated = configuration.checkOutdated ? try await checkOutdated(pins) : []
        let declaredRequirements = configuration.checkDeclaredConstraints
            ? try await loadDeclaredRequirements(from: auditTarget)
            : []
        let constraintAssessments = configuration.checkDeclaredConstraints
            ? try await analyzeDeclaredConstraints(pins: pins, declaredRequirements: declaredRequirements)
            : []

        let outdatedByIdentity = Dictionary(uniqueKeysWithValues: outdated.map { ($0.pin.identity, $0) })
        let riskByIdentity = Dictionary(uniqueKeysWithValues: strategyFindings.map { ($0.pin.identity, $0.risk) })
        let constraintsByIdentity = Dictionary(uniqueKeysWithValues: constraintAssessments.map { ($0.identity, $0) })

        let dependencies = pins.map { pin in
            let constraint = constraintsByIdentity[pin.identity]
            return DependencyAnalysis(
                pin: pin,
                outdated: outdatedByIdentity[pin.identity],
                strategyRisk: riskByIdentity[pin.identity] ?? .normal,
                declaredRequirement: constraint?.declaredRequirement,
                constraintDrift: constraint?.drift ?? .declarationUnavailable,
                latestAllowedVersion: constraint?.latestAllowedVersion
            )
        }.sorted(by: { $0.pin.identity < $1.pin.identity })

        let findings = makeFindings(
            status: fileStatus,
            schema: schema,
            strategyFindings: strategyFindings,
            outdatedResults: outdated,
            constraintAssessments: constraintAssessments
        )

        return DependencyReport(
            projectPath: projectPath,
            generatedAt: Date(),
            resolvedFilePath: auditTarget.resolvedFileURL.path,
            resolvedFileStatus: fileStatus,
            schemaVersion: schema,
            dependencies: dependencies,
            findings: findings
        )
    }

    /// Resolves a user-supplied path to the expected `Package.resolved` location.
    ///
    /// - Parameter path: A path to a project bundle, containing directory, or lockfile.
    /// - Returns: The canonical `Package.resolved` URL used by the rest of the engine.
    /// - Throws: `DependencyTrackerError.invalidPath` or
    ///   `DependencyTrackerError.ambiguousProjectPath` when the input cannot be mapped safely.
    public func locateResolvedFile(at path: String) throws -> URL {
        try locator.locateResolvedFile(at: path)
    }

    /// Resolves a user-supplied path into the richer audit target used by declared-constraint analysis.
    func locateAuditTarget(at path: String) throws -> AuditTarget {
        try locator.locateAuditTarget(at: path)
    }

    /// Parses the dependencies recorded in a `Package.resolved` file.
    ///
    /// - Parameter url: The resolved file URL returned by `locateResolvedFile(at:)`.
    /// - Returns: Normalized pins that can be consumed by the audit pipeline.
    /// - Throws: Parsing and schema errors when the file contents are malformed.
    public func parseResolved(at url: URL) throws -> [ResolvedPin] {
        try parser.parse(at: url)
    }

    /// Determines whether the resolved file is tracked, ignored, untracked, or missing.
    ///
    /// - Parameter resolvedFileURL: The resolved file location to inspect in git.
    /// - Returns: The structured file status used by findings and CLI exit codes.
    public func auditGitTracking(resolvedFileURL: URL) async throws -> ResolvedFileStatus {
        try await gitTrackingAuditor.audit(resolvedFileURL: resolvedFileURL)
    }

    /// Reads the schema version from a `Package.resolved` file and classifies its compatibility.
    ///
    /// - Parameter url: The resolved file URL to inspect.
    /// - Returns: Schema metadata ready to render directly in the report.
    public func checkSchemaVersion(at url: URL) throws -> SchemaInfo {
        try schemaChecker.check(at: url)
    }

    /// Evaluates whether version-pinned remote dependencies have newer stable releases available.
    ///
    /// - Parameter pins: Parsed dependency pins from the resolved file.
    /// - Returns: One outdated-check result per eligible remote version pin.
    /// - Throws: Cancellation when the parent task is cancelled. Remote lookup failures for
    ///   individual dependencies are converted into notes instead of terminating the entire audit.
    public func checkOutdated(_ pins: [ResolvedPin]) async throws -> [OutdatedResult] {
        try await outdatedChecker.check(pins)
    }

    /// Flags branch, revision, and local-path pins that reduce reproducibility.
    ///
    /// - Parameter pins: Parsed dependency pins from the resolved file.
    /// - Returns: Strategy findings for every dependency, including `.normal` entries.
    public func auditRequirementStrategies(_ pins: [ResolvedPin]) -> [StrategyFinding] {
        strategyAuditor.audit(pins)
    }

    /// Loads declared dependency requirements from the best available source for the audit target.
    func loadDeclaredRequirements(from auditTarget: AuditTarget) async throws -> [DeclaredRequirement] {
        try await declaredRequirementLoader.load(from: auditTarget, timeout: configuration.timeout)
    }

    /// Compares declared requirements with resolved pins and stable upstream versions.
    func analyzeDeclaredConstraints(
        pins: [ResolvedPin],
        declaredRequirements: [DeclaredRequirement]
    ) async throws -> [ConstraintAssessment] {
        try await declaredConstraintAnalyzer.analyze(pins: pins, declared: declaredRequirements)
    }

    /// Converts raw audit outputs into sorted, user-facing findings.
    ///
    /// The engine intentionally centralizes finding assembly here so the CLI, markdown reporter,
    /// JSON reporter, and macOS app all stay aligned on severity, wording, and recommendation
    /// text instead of re-encoding policy at each presentation layer.
    private func makeFindings(
        status: ResolvedFileStatus,
        schema: SchemaInfo?,
        strategyFindings: [StrategyFinding],
        outdatedResults: [OutdatedResult],
        constraintAssessments: [ConstraintAssessment]
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

        if let schema {
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
        }

        for strategyFinding in strategyFindings where strategyFinding.risk != .normal {
            findings.append(Finding(
                severity: .warning,
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

        for result in outdatedResults {
            if let finding = finding(for: result) {
                findings.append(finding)
            }
        }

        findings.append(contentsOf: constraintAssessments.compactMap(\.finding))

        return findings.sorted(by: findingSort)
    }

    /// Chooses between the git-aware status audit and a simple existence check.
    ///
    /// This split exists so callers can disable repository inspection while still getting a
    /// sensible answer for tools or environments where only file existence matters.
    private func resolvedFileStatus(for resolvedFileURL: URL) async throws -> ResolvedFileStatus {
        if configuration.checkGitTracking {
            return try await auditGitTracking(resolvedFileURL: resolvedFileURL)
        }
        return FileManager.default.fileExists(atPath: resolvedFileURL.path) ? .tracked : .missing
    }

    /// Builds an additional finding when an outdated check completed only partially.
    ///
    /// Instead of losing nuance by flattening all lookup problems into "not outdated," the
    /// engine emits explicit findings that explain whether the problem came from network access,
    /// upstream tagging strategy, or a non-semantic resolved version.
    private func finding(for result: OutdatedResult) -> Finding? {
        guard let noteKind = result.noteKind, let note = result.note else {
            return nil
        }

        switch noteKind {
        case .remoteLookupFailure:
            return Finding(
                severity: .warning,
                category: .outdated,
                message: "Unable to fully assess updates for \"\(result.pin.identity)\": \(note)",
                recommendation: "Verify the remote repository is reachable and publishes stable semantic tags."
            )
        case .noStableSemanticTags:
            return Finding(
                severity: .warning,
                category: .outdated,
                message: "Unable to fully assess updates for \"\(result.pin.identity)\": \(note)",
                recommendation: "Verify the upstream repository publishes stable semantic tags or disable outdated checks for this dependency."
            )
        case .nonSemanticResolvedVersion:
            return Finding(
                severity: .info,
                category: .outdated,
                message: "Unable to fully assess updates for \"\(result.pin.identity)\": \(note)",
                recommendation: "Pin the dependency to a semantic version tag if you want outdated checks to compare it against upstream releases."
            )
        }
    }

    /// Maps strategy risk levels to the recommendation text shown in reports.
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

    /// Keeps findings ordered by severity first, category second, and message last.
    ///
    /// The sort is deterministic so tests, CLI output, exported reports, and UI snapshots remain
    /// stable across runs with the same underlying data.
    private func findingSort(lhs: Finding, rhs: Finding) -> Bool {
        let severityOrder: [Severity: Int] = [.error: 0, .warning: 1, .info: 2]
        let categoryOrder: [FindingCategory: Int] = [.gitTracking: 0, .schema: 1, .pinStrategy: 2, .declaredConstraint: 3, .outdated: 4]
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
