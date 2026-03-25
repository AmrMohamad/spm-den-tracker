import Foundation
import PathKit
import XcodeProj

/// Carries the normalized set of files that can contribute to one audit run.
struct AuditTarget: Sendable {
    /// The original user-provided input path.
    let inputPath: String
    /// The resolved lockfile path used for the main analysis.
    let resolvedFileURL: URL
    /// The Xcode project bundle when one was supplied or discovered.
    let projectFileURL: URL?
    /// The Swift package manifest when one was supplied or discovered.
    let manifestURL: URL?
    /// The nearest containing directory that anchors the audit target.
    let repositoryRootURL: URL?
}

/// Loads declared dependency requirements from whichever source best matches the current audit target.
struct DeclaredRequirementLoader: Sendable {
    /// The process runner used for `swift package dump-package`.
    private let processRunner: ProcessRunning

    /// Creates a loader with injectable process execution for tests.
    init(processRunner: ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
    }

    /// Loads declared requirements from an Xcode project or Swift package manifest.
    func load(from target: AuditTarget, timeout: TimeInterval) async throws -> [DeclaredRequirement] {
        if let projectURL = target.projectFileURL {
            return try XcodeProjectRequirementLoader().load(from: projectURL)
        }
        if let manifestURL = target.manifestURL {
            return try await DumpPackageRequirementLoader(processRunner: processRunner).load(from: manifestURL, timeout: timeout)
        }
        return []
    }
}

/// Reads requirement declarations from `swift package dump-package`.
private struct DumpPackageRequirementLoader: Sendable {
    /// The process runner used to invoke SwiftPM.
    private let processRunner: ProcessRunning

    /// Creates a dump-package loader with injectable command execution.
    init(processRunner: ProcessRunning) {
        self.processRunner = processRunner
    }

    /// Extracts requirement declarations from a Swift package manifest.
    func load(from manifestURL: URL, timeout: TimeInterval) async throws -> [DeclaredRequirement] {
        let packageRoot = manifestURL.deletingLastPathComponent()
        let result = try await processRunner.run(
            arguments: ["swift", "package", "dump-package"],
            currentDirectoryURL: packageRoot,
            timeout: timeout
        )

        guard result.status == 0 else {
            throw DependencyTrackerError.commandFailed(
                command: ["swift", "package", "dump-package"],
                status: result.status,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let data = Data(result.stdout.utf8)
        let package = try JSONDecoder().decode(DumpPackage.self, from: data)

        return package.dependencies.compactMap { dependency in
            if let sourceControl = dependency.sourceControl?.first {
                let identity = sourceControl.identity ?? DependencyIdentityNormalizer.normalizeIdentity(from: sourceControl.location.urlString)
                return sourceControl.requirement.makeDeclaredRequirement(
                    identity: identity,
                    source: .packageManifest,
                    location: sourceControl.location.urlString
                )
            }

            if let fileSystem = dependency.fileSystem?.first {
                let path = fileSystem.path
                return DeclaredRequirement(
                    identity: DependencyIdentityNormalizer.normalizeIdentity(from: path),
                    source: .packageManifest,
                    kind: .local,
                    reference: path,
                    location: path,
                    description: "local \(path)"
                )
            }

            return nil
        }
        .sorted { $0.identity < $1.identity }
    }
}

/// Reads package requirement declarations from an Xcode project using XcodeProj.
private struct XcodeProjectRequirementLoader: Sendable {
    /// Extracts remote and local package requirements from a project bundle.
    func load(from projectURL: URL) throws -> [DeclaredRequirement] {
        let xcodeproj = try XcodeProj(path: Path(projectURL.path))
        guard let project = try xcodeproj.pbxproj.rootProject() else {
            throw DependencyTrackerError.invalidPath(projectURL.path)
        }

        let remoteRequirements = project.remotePackages.compactMap { package -> DeclaredRequirement? in
            let location = package.repositoryURL ?? ""
            let identity = DependencyIdentityNormalizer.normalizeIdentity(from: location)
            switch package.versionRequirement {
            case .none:
                return nil
            case .exact(let version):
                return DeclaredRequirement(
                    identity: identity,
                    source: .xcodeProject,
                    kind: .exact,
                    lowerBound: version,
                    upperBound: version,
                    location: location,
                    description: "exact \(version)"
                )
            case .upToNextMajorVersion(let version):
                return DeclaredRequirement(
                    identity: identity,
                    source: .xcodeProject,
                    kind: .upToNextMajor,
                    lowerBound: version,
                    location: location,
                    description: "from \(version)"
                )
            case .upToNextMinorVersion(let version):
                return DeclaredRequirement(
                    identity: identity,
                    source: .xcodeProject,
                    kind: .upToNextMinor,
                    lowerBound: version,
                    location: location,
                    description: "upToNextMinor \(version)"
                )
            case .range(let lower, let upper):
                return DeclaredRequirement(
                    identity: identity,
                    source: .xcodeProject,
                    kind: .range,
                    lowerBound: lower,
                    upperBound: upper,
                    location: location,
                    description: "\(lower)..<\(upper)"
                )
            case .branch(let branch):
                return DeclaredRequirement(
                    identity: identity,
                    source: .xcodeProject,
                    kind: .branch,
                    reference: branch,
                    location: location,
                    description: "branch \(branch)"
                )
            case .revision(let revision):
                return DeclaredRequirement(
                    identity: identity,
                    source: .xcodeProject,
                    kind: .revision,
                    reference: revision,
                    location: location,
                    description: "revision \(revision)"
                )
            }
        }

        let localRequirements = project.localPackages.map { package in
            let path = package.relativePath
            return DeclaredRequirement(
                identity: DependencyIdentityNormalizer.normalizeIdentity(from: path),
                source: .xcodeProject,
                kind: .local,
                reference: path,
                location: path,
                description: "local \(path)"
            )
        }

        return (remoteRequirements + localRequirements).sorted(by: { $0.identity < $1.identity })
    }
}

/// Minimal decode model for the subset of `swift package dump-package` output the tracker needs.
private struct DumpPackage: Decodable {
    /// The dependency entries declared by the package manifest.
    let dependencies: [DumpPackageDependency]
}

/// Represents one dependency declaration from dump-package output.
private struct DumpPackageDependency: Decodable {
    /// Source-control dependency declarations.
    let sourceControl: [SourceControlDependency]?
    /// Filesystem dependency declarations.
    let fileSystem: [FileSystemDependency]?
}

/// Represents a manifest dependency fetched from source control.
private struct SourceControlDependency: Decodable {
    /// The package identity as emitted by SwiftPM.
    let identity: String?
    /// The location wrapper holding the remote URL.
    let location: SourceControlLocation
    /// The requirement declaration payload.
    let requirement: DumpRequirement
}

/// Represents a manifest dependency resolved from the local filesystem.
private struct FileSystemDependency: Decodable {
    /// The dependency path relative to the package root.
    let path: String
}

/// Represents the nested remote URL location object from dump-package output.
private struct SourceControlLocation: Decodable {
    /// The canonical URL string for the dependency.
    let urlString: String

    /// Decodes the first remote URL from the source-control location wrapper.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let remotes = try container.decode([RemoteURL].self, forKey: .remote)
        guard let remote = remotes.first else {
            throw DecodingError.dataCorruptedError(forKey: .remote, in: container, debugDescription: "Missing remote location.")
        }
        self.urlString = remote.urlString
    }

    /// Coding keys used by the location wrapper.
    private enum CodingKeys: String, CodingKey {
        case remote
    }

    /// The nested remote URL object.
    private struct RemoteURL: Decodable {
        let urlString: String
    }
}

/// Represents the requirement payload emitted by dump-package.
private struct DumpRequirement: Decodable {
    /// The normalized kind of requirement.
    let kind: DeclaredRequirementKind
    /// The lower bound for version-based rules.
    let lowerBound: String?
    /// The upper bound for explicit ranges.
    let upperBound: String?
    /// The reference string for branch or revision requirements.
    let reference: String?

    /// Decodes the ad-hoc SwiftPM requirement object.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let exact = try container.decodeIfPresent(String.self, forKey: .exact) {
            kind = .exact
            lowerBound = exact
            upperBound = exact
            reference = nil
            return
        }

        if let branches = try container.decodeIfPresent([String].self, forKey: .branch), let branch = branches.first {
            kind = .branch
            lowerBound = nil
            upperBound = nil
            reference = branch
            return
        }

        if let revisions = try container.decodeIfPresent([String].self, forKey: .revision), let revision = revisions.first {
            kind = .revision
            lowerBound = nil
            upperBound = nil
            reference = revision
            return
        }

        if let range = try container.decodeIfPresent([RangeBound].self, forKey: .range), let bounds = range.first {
            lowerBound = bounds.lowerBound
            upperBound = bounds.upperBound
            reference = nil

            if let lower = bounds.lowerBound, let upper = bounds.upperBound {
                let lowerMajor = lower.split(separator: ".").first.map(String.init)
                let upperMajor = upper.split(separator: ".").first.map(String.init)
                let lowerMinor = lower.split(separator: ".").dropFirst().first.map(String.init)
                let upperMinor = upper.split(separator: ".").dropFirst().first.map(String.init)

                if lowerMajor != nil, lowerMajor == upperMajor, lowerMinor != nil, lowerMinor == upperMinor {
                    kind = .upToNextMinor
                } else if lowerMajor != nil, upperMajor != nil, lowerMajor != upperMajor {
                    kind = .upToNextMajor
                } else {
                    kind = .range
                }
            } else {
                kind = .range
            }
            return
        }

        throw DecodingError.dataCorruptedError(forKey: .range, in: container, debugDescription: "Unsupported dependency requirement.")
    }

    /// Converts the dump-package requirement into the shared report model.
    func makeDeclaredRequirement(identity: String, source: DeclaredRequirementSource, location: String?) -> DeclaredRequirement {
        let description: String
        switch kind {
        case .exact:
            description = "exact \(lowerBound ?? "")"
        case .upToNextMajor:
            description = "from \(lowerBound ?? "")"
        case .upToNextMinor:
            description = "upToNextMinor \(lowerBound ?? "")"
        case .range:
            description = "\(lowerBound ?? "")..<\(upperBound ?? "")"
        case .branch:
            description = "branch \(reference ?? "")"
        case .revision:
            description = "revision \(reference ?? "")"
        case .local:
            description = "local \(reference ?? "")"
        }

        return DeclaredRequirement(
            identity: identity,
            source: source,
            kind: kind,
            lowerBound: lowerBound,
            upperBound: upperBound,
            reference: reference,
            location: location,
            description: description
        )
    }

    /// Coding keys used by the requirement payload.
    private enum CodingKeys: String, CodingKey {
        case exact
        case range
        case branch
        case revision
    }

    /// Represents the single range object emitted inside the requirement payload.
    private struct RangeBound: Decodable {
        let lowerBound: String?
        let upperBound: String?
    }
}
