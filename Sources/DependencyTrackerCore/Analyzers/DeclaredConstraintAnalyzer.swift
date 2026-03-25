import Foundation
import Version

/// Records the declared-constraint assessment for one dependency.
struct ConstraintAssessment: Sendable {
    /// The dependency identity associated with the assessment.
    let identity: String
    /// The normalized requirement declaration when one was discovered.
    let declaredRequirement: DeclaredRequirement
    /// The drift classification derived from the requirement and available versions.
    let drift: ConstraintDriftStatus
    /// The newest stable version already allowed by the declaration, if any.
    let latestAllowedVersion: String?
    /// The optional user-visible finding associated with the assessment.
    let finding: Finding?
}

/// Compares declared requirements against resolved pins and stable upstream versions.
struct DeclaredConstraintAnalyzer: Sendable {
    /// Shared version catalog used to inspect stable upstream releases.
    private let versionCatalog: RemoteVersionCatalog
    /// Whether policy findings should affect exit codes.
    private let strictConstraints: Bool

    /// Creates an analyzer backed by the shared version catalog.
    init(versionCatalog: RemoteVersionCatalog, strictConstraints: Bool) {
        self.versionCatalog = versionCatalog
        self.strictConstraints = strictConstraints
    }

    /// Evaluates all declared requirements against the current resolved pins.
    func analyze(pins: [ResolvedPin], declared: [DeclaredRequirement]) async throws -> [ConstraintAssessment] {
        let pinsByIdentity = Dictionary(uniqueKeysWithValues: pins.map { ($0.identity.lowercased(), $0) })
        let pinsByLocation = Dictionary(uniqueKeysWithValues: pins.map {
            (DependencyIdentityNormalizer.canonicalLocation($0.location), $0)
        })

        return try await withThrowingTaskGroup(of: ConstraintAssessment.self, returning: [ConstraintAssessment].self) { group in
            for requirement in declared {
                guard let pin = resolvePin(for: requirement, pinsByIdentity: pinsByIdentity, pinsByLocation: pinsByLocation) else {
                    continue
                }
                group.addTask { try await self.assess(pin: pin, requirement: requirement) }
            }

            var results: [ConstraintAssessment] = []
            while let result = try await group.next() {
                results.append(result)
            }
            return results.sorted { $0.identity < $1.identity }
        }
    }

    /// Finds the resolved pin that best matches the declared requirement.
    private func resolvePin(
        for requirement: DeclaredRequirement,
        pinsByIdentity: [String: ResolvedPin],
        pinsByLocation: [String: ResolvedPin]
    ) -> ResolvedPin? {
        if let pin = pinsByIdentity[requirement.identity.lowercased()] {
            return pin
        }
        if let location = requirement.location {
            return pinsByLocation[DependencyIdentityNormalizer.canonicalLocation(location)]
        }
        return nil
    }

    /// Computes the policy and drift result for one resolved pin / declaration pair.
    private func assess(pin: ResolvedPin, requirement: DeclaredRequirement) async throws -> ConstraintAssessment {
        switch requirement.kind {
        case .branch:
            return ConstraintAssessment(
                identity: pin.identity,
                declaredRequirement: requirement,
                drift: .notApplicable,
                latestAllowedVersion: nil,
                finding: Finding(
                    severity: .warning,
                    category: .declaredConstraint,
                    message: "\"\(pin.identity)\" declares branch-based updates (\(requirement.description)).",
                    recommendation: "Prefer a tagged version requirement to keep upgrades auditable and reproducible.",
                    isActionable: strictConstraints
                )
            )
        case .revision:
            return ConstraintAssessment(
                identity: pin.identity,
                declaredRequirement: requirement,
                drift: .notApplicable,
                latestAllowedVersion: nil,
                finding: Finding(
                    severity: .warning,
                    category: .declaredConstraint,
                    message: "\"\(pin.identity)\" declares revision-based updates (\(requirement.description)).",
                    recommendation: "Prefer a tagged version requirement unless you intentionally need an unpublished commit.",
                    isActionable: strictConstraints
                )
            )
        case .local:
            return ConstraintAssessment(
                identity: pin.identity,
                declaredRequirement: requirement,
                drift: .notApplicable,
                latestAllowedVersion: nil,
                finding: Finding(
                    severity: .warning,
                    category: .declaredConstraint,
                    message: "\"\(pin.identity)\" is declared as a local package (\(requirement.description)).",
                    recommendation: "Document local-only dependencies clearly or replace them with a tagged remote package before CI distribution.",
                    isActionable: strictConstraints
                )
            )
        case .exact, .upToNextMajor, .upToNextMinor, .range:
            break
        }

        guard case .version(let currentVersion, _) = pin.state, let current = Version(tolerant: currentVersion) else {
            return ConstraintAssessment(
                identity: pin.identity,
                declaredRequirement: requirement,
                drift: .notApplicable,
                latestAllowedVersion: nil,
                finding: nil
            )
        }

        let versions = try await versionCatalog.stableVersions(for: pin.location)
        let allowedVersions = versions.filter { requirement.contains($0) }
        let latestAllowedVersion = allowedVersions.last?.description

        if let latestAllowed = allowedVersions.last, latestAllowed > current {
            return ConstraintAssessment(
                identity: pin.identity,
                declaredRequirement: requirement,
                drift: .newerAllowedAvailable,
                latestAllowedVersion: latestAllowed.description,
                finding: Finding(
                    severity: .warning,
                    category: .declaredConstraint,
                    message: "\"\(pin.identity)\" can update from \(currentVersion) to \(latestAllowed.description) without changing the declared requirement.",
                    recommendation: "Run an update and commit the refreshed Package.resolved if you want the newest version already allowed by policy.",
                    isActionable: strictConstraints
                )
            )
        }

        if let latest = versions.last, latest > current {
            return ConstraintAssessment(
                identity: pin.identity,
                declaredRequirement: requirement,
                drift: .newerExistsOutsideDeclaredRange,
                latestAllowedVersion: latestAllowedVersion,
                finding: nil
            )
        }

        return ConstraintAssessment(
            identity: pin.identity,
            declaredRequirement: requirement,
            drift: .currentIsLatestAllowed,
            latestAllowedVersion: latestAllowedVersion,
            finding: nil
        )
    }
}

/// Evaluates whether a semantic version satisfies a declared requirement.
private extension DeclaredRequirement {
    func contains(_ version: Version) -> Bool {
        switch kind {
        case .exact:
            guard let exact = lowerBound.flatMap(Version.init(tolerant:)) else {
                return false
            }
            return version == exact
        case .upToNextMajor:
            guard let lower = lowerBound.flatMap(Version.init(tolerant:)) else {
                return false
            }
            return version >= lower && version.major == lower.major
        case .upToNextMinor:
            guard let lower = lowerBound.flatMap(Version.init(tolerant:)) else {
                return false
            }
            return version >= lower && version.major == lower.major && version.minor == lower.minor
        case .range:
            guard
                let lower = lowerBound.flatMap(Version.init(tolerant:)),
                let upper = upperBound.flatMap(Version.init(tolerant:))
            else {
                return false
            }
            return version >= lower && version < upper
        case .branch, .revision, .local:
            return false
        }
    }
}
