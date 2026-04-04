import Foundation
import Version

/// Compares declared requirements across manifests that participate in the same workspace report.
public struct CrossManifestConstraintDriftAnalyzer: Sendable {
    public init() {}

    /// Returns workspace findings when the same package identity is declared with incompatible rules.
    public func analyze(_ contexts: [ResolutionContextReport]) -> [Finding] {
        let occurrences: [RequirementOccurrence] = contexts.flatMap { contextReport in
            contextReport.reports.flatMap { report in
                report.dependencies.compactMap { dependency -> RequirementOccurrence? in
                    guard let requirement = dependency.declaredRequirement else {
                        return nil
                    }

                    return RequirementOccurrence(
                        identity: dependency.pin.identity,
                        manifestPath: report.projectPath,
                        contextPath: contextReport.context.displayPath,
                        requirement: requirement
                    )
                }
            }
        }

        let grouped = Dictionary(grouping: occurrences, by: { $0.identity })
        return grouped.values.compactMap { analyzeOccurrences(for: $0) }
            .sorted(by: findingSortOrder)
    }

    /// Analyzes one package identity across all manifests.
    private func analyzeOccurrences(for occurrences: [RequirementOccurrence]) -> Finding? {
        guard occurrences.count > 1 else {
            return nil
        }

        let profiles = occurrences.map(\.profile)
        let uniqueProfiles = Array(Set(profiles))
        guard uniqueProfiles.count > 1 else {
            return nil
        }

        let severity = severity(for: uniqueProfiles)
        let identity = occurrences.first?.identity ?? "unknown"
        let details = occurrences
            .sorted(by: { $0.manifestPath < $1.manifestPath })
            .map { "\($0.contextPath) [\($0.manifestPath)]: \($0.requirement.description)" }
            .joined(separator: "; ")

        return Finding(
            severity: severity,
            category: .declaredConstraint,
            message: "\"\(identity)\" is declared with different requirements across manifests: \(details).",
            recommendation: recommendation(for: severity)
        )
    }

    /// Chooses severity from the requirement mix.
    private func severity(for profiles: [RequirementProfile]) -> Severity {
        if profiles.contains(where: \.isNonVersion) {
            return .error
        }

        let majors = Set(profiles.compactMap(\.major))
        if majors.count > 1 {
            return .error
        }

        return .warning
    }

    /// Returns a recommendation tailored to the drift severity.
    private func recommendation(for severity: Severity) -> String {
        switch severity {
        case .error:
            return "Align the manifests on one shared requirement shape so the workspace has one declared contract for this package."
        case .warning:
            return "Align the manifests on one version line or lower bound so they stop drifting inside the same major release family."
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

/// Captures one declared requirement occurrence for drift analysis.
private struct RequirementOccurrence: Hashable {
    /// The normalized package identity.
    let identity: String
    /// The manifest or project path that declared the requirement.
    let manifestPath: String
    /// The workspace context path used for grouping.
    let contextPath: String
    /// The requirement itself.
    let requirement: DeclaredRequirement

    /// Returns a normalized profile used for drift comparisons.
    var profile: RequirementProfile {
        RequirementProfile(requirement: requirement)
    }
}

/// Reduces declared requirements to the shape needed for drift severity decisions.
private struct RequirementProfile: Hashable {
    /// The declaration kind.
    let kind: DeclaredRequirementKind
    /// The optional semantic version used by version-based declarations.
    let version: Version?
    /// The lower bound text as declared.
    let lowerBound: String?
    /// The upper bound text as declared.
    let upperBound: String?
    /// The branch, revision, or local reference as declared.
    let reference: String?

    /// Creates a requirement profile from a declaration.
    init(requirement: DeclaredRequirement) {
        self.kind = requirement.kind
        self.lowerBound = requirement.lowerBound
        self.upperBound = requirement.upperBound
        self.reference = requirement.reference
        switch requirement.kind {
        case .exact, .upToNextMajor, .upToNextMinor, .range:
            self.version = requirement.lowerBound.flatMap(Version.init(tolerant:))
        case .branch, .revision, .local:
            self.version = nil
        }
    }

    /// Indicates whether the declaration is not version-based.
    var isNonVersion: Bool {
        version == nil
    }

    /// Returns the major version when the declaration is version-based.
    var major: Int? {
        version?.major
    }
}
