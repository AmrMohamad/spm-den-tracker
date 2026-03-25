import Foundation
import Version

/// Fetches and caches stable upstream versions so outdated checks and constraint drift share the same network results.
actor RemoteVersionCatalog {
    /// The git client used to fetch tag refs from remotes.
    private let gitClient: GitClientProtocol
    /// In-memory cache keyed by dependency location.
    private var cache: [String: [Version]] = [:]

    /// Creates a reusable version catalog backed by git tag lookups.
    init(gitClient: GitClientProtocol) {
        self.gitClient = gitClient
    }

    /// Returns all stable semantic versions known for the supplied location.
    func stableVersions(for location: String) async throws -> [Version] {
        let key = DependencyIdentityNormalizer.canonicalLocation(location)
        if let cached = cache[key] {
            return cached
        }

        let tags = try await gitClient.remoteTags(for: location)
        let versions = tags.compactMap(normalizedVersion(fromTag:)).sorted()
        cache[key] = versions
        return versions
    }

    /// Converts a raw git tag ref into a stable semantic version, discarding prereleases.
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
