import Foundation

/// Normalizes dependency identities and locations across Package.resolved, Package.swift, and .pbxproj sources.
enum DependencyIdentityNormalizer {
    /// Returns a stable lowercase identity for a remote URL or local path.
    static func normalizeIdentity(from location: String) -> String {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        if let url = URL(string: trimmed), let host = url.host {
            let component = url.deletingPathExtension().lastPathComponent
            return component.isEmpty ? host.lowercased() : component.lowercased()
        }

        let component = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
        if !component.isEmpty {
            return component.lowercased()
        }

        return trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    /// Returns a canonicalized location string so manifest and resolved-file entries can be matched reliably.
    static func canonicalLocation(_ location: String) -> String {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return trimmed.lowercased().replacingOccurrences(of: ".git", with: "")
        }

        return URL(fileURLWithPath: trimmed).standardizedFileURL.path.lowercased()
    }
}
