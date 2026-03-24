import Foundation
import Version

struct OutdatedChecker {
    private let gitClient: GitClientProtocol
    private let concurrentFetchLimit: Int

    init(gitClient: GitClientProtocol, concurrentFetchLimit: Int) {
        self.gitClient = gitClient
        self.concurrentFetchLimit = max(1, concurrentFetchLimit)
    }

    func check(_ pins: [ResolvedPin]) async -> [OutdatedResult] {
        let versionPins = pins.filter {
            if case .version = $0.state, $0.kind == .remoteSourceControl {
                return true
            }
            return false
        }

        guard !versionPins.isEmpty else {
            return []
        }

        return await withTaskGroup(of: OutdatedResult.self, returning: [OutdatedResult].self) { group in
            var iterator = versionPins.makeIterator()
            var active = 0
            var results: [OutdatedResult] = []

            while active < concurrentFetchLimit, let pin = iterator.next() {
                active += 1
                group.addTask { self.evaluate(pin) }
            }

            while let result = await group.next() {
                results.append(result)
                active -= 1
                if let nextPin = iterator.next(), !Task.isCancelled {
                    active += 1
                    group.addTask { self.evaluate(nextPin) }
                }
            }

            return results.sorted { $0.pin.identity < $1.pin.identity }
        }
    }

    private func evaluate(_ pin: ResolvedPin) -> OutdatedResult {
        guard case .version(let currentVersion, _) = pin.state else {
            return OutdatedResult(pin: pin, latestVersion: nil, updateType: nil, isOutdated: false)
        }

        do {
            let tags = try gitClient.remoteTags(for: pin.location)
            let versions = tags.compactMap(normalizedVersion(fromTag:))
            guard let latest = versions.sorted().last else {
                return OutdatedResult(pin: pin, latestVersion: nil, updateType: nil, isOutdated: false, note: "No stable semantic tags found upstream.")
            }

            guard let current = Version(tolerant: currentVersion) else {
                return OutdatedResult(pin: pin, latestVersion: latest.description, updateType: nil, isOutdated: false, note: "Resolved version is not semantic.")
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
        } catch {
            return OutdatedResult(pin: pin, latestVersion: nil, updateType: nil, isOutdated: false, note: error.localizedDescription)
        }
    }

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
