import Foundation
import Version

/// Compares resolved pins across different resolution contexts.
public struct CrossContextResolvedDriftAnalyzer: Sendable {
    public init() {}

    /// Returns workspace findings when the same package resolves differently across contexts.
    public func analyze(_ contexts: [ResolutionContextReport]) -> [Finding] {
        let occurrences: [ResolvedOccurrence] = contexts.flatMap { contextReport in
            contextReport.reports.flatMap { report in
                report.dependencies.map { dependency -> ResolvedOccurrence in
                    ResolvedOccurrence(
                        identity: dependency.pin.identity,
                        contextKey: contextReport.context.key,
                        contextPath: contextReport.context.displayPath,
                        reportPath: report.projectPath,
                        resolvedFilePath: report.resolvedFilePath,
                        pin: dependency.pin
                    )
                }
            }
        }

        let groupedByIdentity = Dictionary(grouping: occurrences, by: { $0.identity })
        return groupedByIdentity.values.compactMap { analyzeOccurrences(for: $0) }
            .sorted(by: findingSortOrder)
    }

    /// Analyzes one package identity across multiple resolution contexts.
    private func analyzeOccurrences(for occurrences: [ResolvedOccurrence]) -> Finding? {
        let representativeByContext = Dictionary(grouping: occurrences, by: \.contextKey)
            .compactMapValues { $0.first }

        guard representativeByContext.count > 1 else {
            return nil
        }

        let representatives = Array(representativeByContext.values)
        let profiles = representatives.map(\.profile)
        let uniqueProfiles = Array(Set(profiles))
        guard uniqueProfiles.count > 1 else {
            return nil
        }

        let severity = severity(for: uniqueProfiles)
        let identity = representatives.first?.identity ?? "unknown"
        let details = representatives
            .sorted(by: { $0.contextPath < $1.contextPath })
            .map { "\($0.contextPath) [\($0.reportPath)]: \($0.pin.state.strategyLabel) \($0.pin.state.displayValue) (\($0.resolvedFilePath))" }
            .joined(separator: "; ")

        return Finding(
            severity: severity,
            category: .pinStrategy,
            message: "\"\(identity)\" resolves differently across contexts: \(details).",
            recommendation: recommendation(for: severity)
        )
    }

    /// Chooses severity from the resolved-pin mix.
    private func severity(for profiles: [ResolvedProfile]) -> Severity {
        if profiles.contains(where: \.isMalformedVersion) {
            return .error
        }
        if profiles.contains(where: \.isLocal) {
            return .error
        }

        let families = Set(profiles.map(\.family))
        if families.count > 1 {
            return .error
        }

        guard let family = families.first else {
            return .info
        }

        switch family {
        case .version:
            let majors = Set(profiles.compactMap(\.major))
            if majors.count > 1 {
                return .error
            }
            return .warning
        case .branch:
            let branches = Set(profiles.compactMap(\.branch))
            if branches.count > 1 {
                return .error
            }
            return .warning
        case .revision:
            return .warning
        case .local:
            return .error
        }
    }

    /// Returns a recommendation tailored to the drift severity.
    private func recommendation(for severity: Severity) -> String {
        switch severity {
        case .error:
            return "Make every resolution context converge on the same package source and version, or split the dependency so the contexts are no longer coupled."
        case .warning:
            return "Align the contexts on one version or revision so workspace builds stop drifting silently."
        case .info:
            return "No action needed."
        }
    }

    /// Sorts findings deterministically for reporters and tests.
    private func findingSortOrder(_ lhs: Finding, _ rhs: Finding) -> Bool {
        if lhs.severity != rhs.severity {
            return severityRank(lhs.severity) < severityRank(rhs.severity)
        }
        if lhs.category != rhs.category {
            return lhs.category.rawValue < rhs.category.rawValue
        }
        return lhs.message < rhs.message
    }

    /// Maps severities to a stable sort order.
    private func severityRank(_ severity: Severity) -> Int {
        switch severity {
        case .error: return 0
        case .warning: return 1
        case .info: return 2
        }
    }
}

/// Captures one resolved-pin occurrence for drift analysis.
private struct ResolvedOccurrence: Hashable {
    /// The normalized package identity.
    let identity: String
    /// The workspace resolution context key.
    let contextKey: String
    /// The user-facing context label.
    let contextPath: String
    /// The report path used to resolve this pin.
    let reportPath: String
    /// The resolved lockfile path used for this report.
    let resolvedFilePath: String
    /// The resolved pin itself.
    let pin: ResolvedPin

    /// Returns a normalized profile used for drift comparisons.
    var profile: ResolvedProfile {
        ResolvedProfile(pin: pin)
    }
}

/// Reduces resolved pins to the shape needed for drift severity decisions.
private struct ResolvedProfile: Hashable {
    /// The pin family used by the resolver.
    enum Family: Hashable {
        case version
        case branch
        case revision
        case local
    }

    /// The pin family.
    let family: Family
    /// The semantic version when one exists.
    let version: Version?
    /// The branch name when one exists.
    let branch: String?
    /// The revision or local reference when one exists.
    let reference: String?

    /// Creates a profile from a resolved pin.
    init(pin: ResolvedPin) {
        switch pin.state {
        case .version(let versionString, let revision):
            self.family = .version
            self.version = Version(tolerant: versionString)
            self.branch = nil
            self.reference = revision
        case .branch(let branch, let revision):
            self.family = .branch
            self.version = nil
            self.branch = branch
            self.reference = revision
        case .revision(let revision):
            self.family = .revision
            self.version = nil
            self.branch = nil
            self.reference = revision
        case .local:
            self.family = .local
            self.version = nil
            self.branch = nil
            self.reference = nil
        }
    }

    /// Indicates whether the pin resolves from a local path.
    var isLocal: Bool {
        family == .local
    }

    /// Indicates whether the pin claims to be version-based but could not be parsed.
    var isMalformedVersion: Bool {
        family == .version && version == nil
    }

    /// Returns the major version when the pin is version-based.
    var major: Int? {
        version?.major
    }
}
