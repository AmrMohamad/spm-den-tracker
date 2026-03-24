import Foundation
import Version

/// Checks remote version-pinned dependencies for newer stable semantic tags.
struct OutdatedChecker: Sendable {
    /// The git abstraction used to query upstream tags.
    private let gitClient: GitClientProtocol
    /// The maximum number of concurrent remote lookups allowed in one run.
    private let concurrentFetchLimit: Int

    /// Creates an outdated checker with a bounded lookup fan-out.
    init(gitClient: GitClientProtocol, concurrentFetchLimit: Int) {
        self.gitClient = gitClient
        self.concurrentFetchLimit = max(1, concurrentFetchLimit)
    }

    /// Evaluates all eligible pins and preserves deterministic output ordering.
    ///
    /// Only remote dependencies pinned to semantic versions participate in this check. The bounded
    /// task-group fan-out prevents a large lockfile from spawning unbounded remote fetch work while
    /// still allowing the check to make progress in parallel.
    ///
    /// - Parameter pins: The parsed dependency pins from `Package.resolved`.
    /// - Returns: Outdated results sorted by package identity for stable downstream rendering.
    /// - Throws: `CancellationError` when the parent task is cancelled.
    func check(_ pins: [ResolvedPin]) async throws -> [OutdatedResult] {
        let versionPins = pins.filter {
            if case .version = $0.state, $0.kind == .remoteSourceControl {
                return true
            }
            return false
        }

        guard !versionPins.isEmpty else {
            return []
        }

        return try await withThrowingTaskGroup(of: OutdatedResult.self, returning: [OutdatedResult].self) { group in
            var iterator = versionPins.makeIterator()
            var active = 0
            var results: [OutdatedResult] = []

            while active < concurrentFetchLimit, let pin = iterator.next() {
                active += 1
                group.addTask { try await self.evaluate(pin) }
            }

            while let result = try await group.next() {
                results.append(result)
                active -= 1
                if let nextPin = iterator.next(), !Task.isCancelled {
                    active += 1
                    group.addTask { try await self.evaluate(nextPin) }
                }
            }

            return results.sorted { $0.pin.identity < $1.pin.identity }
        }
    }

    /// Computes the update state for a single dependency while preserving structured failure notes.
    ///
    /// The method intentionally converts most remote lookup problems into note-bearing
    /// `OutdatedResult` values rather than throwing, because one flaky upstream should not suppress
    /// the rest of the report. Only cancellation escapes immediately so the caller can stop work
    /// promptly when a newer analysis request supersedes the current one.
    private func evaluate(_ pin: ResolvedPin) async throws -> OutdatedResult {
        guard case .version(let currentVersion, _) = pin.state else {
            return OutdatedResult(pin: pin, latestVersion: nil, updateType: nil, isOutdated: false)
        }

        do {
            let tags = try await gitClient.remoteTags(for: pin.location)
            let versions = tags.compactMap(normalizedVersion(fromTag:))
            guard let latest = versions.sorted().last else {
                return OutdatedResult(
                    pin: pin,
                    latestVersion: nil,
                    updateType: nil,
                    isOutdated: false,
                    noteKind: .noStableSemanticTags,
                    note: "No stable semantic tags found upstream."
                )
            }

            guard let current = Version(tolerant: currentVersion) else {
                return OutdatedResult(
                    pin: pin,
                    latestVersion: latest.description,
                    updateType: nil,
                    isOutdated: false,
                    noteKind: .nonSemanticResolvedVersion,
                    note: "Resolved version is not semantic."
                )
            }

            guard latest > current else {
                return OutdatedResult(pin: pin, latestVersion: latest.description, updateType: nil, isOutdated: false)
            }

            let updateType: UpdateType
            if latest.major != current.major {
                updateType = .major
            } else if latest.minor != current.minor {
                updateType = .minor
            } else {
                updateType = .patch
            }

            return OutdatedResult(pin: pin, latestVersion: latest.description, updateType: updateType, isOutdated: true)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return OutdatedResult(
                pin: pin,
                latestVersion: nil,
                updateType: nil,
                isOutdated: false,
                noteKind: .remoteLookupFailure,
                note: error.localizedDescription
            )
        }
    }

    /// Converts `git ls-remote --tags` refs into stable semantic versions and discards prereleases.
    ///
    /// Annotated refs such as `^{}` are normalized, optional leading `v` prefixes are stripped,
    /// and prerelease identifiers are ignored so the comparison stays focused on stable releases.
    private func normalizedVersion(fromTag tag: String) -> Version? {
        guard let ref = tag.split(separator: "/").last.map(String.init) else {
            return nil
        }

        let cleaned = ref.replacingOccurrences(of: "^{}", with: "")
        let candidate = cleaned.hasPrefix("v") ? String(cleaned.dropFirst()) : cleaned
        guard let version = Version(tolerant: candidate), version.prereleaseIdentifiers.isEmpty else {
            return nil
        }
        return version
    }
}
