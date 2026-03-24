import Foundation

struct ResolvedFileDocument: Sendable {
    let version: Int
    let pins: [ResolvedPin]
}

struct ResolvedFileParser: Sendable {
    func parse(at url: URL) throws -> [ResolvedPin] {
        try parseDocument(at: url).pins
    }

    func parseDocument(at url: URL) throws -> ResolvedFileDocument {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw DependencyTrackerError.malformedResolvedFile("Top-level JSON is not a dictionary")
        }

        guard let version = root["version"] as? Int else {
            throw DependencyTrackerError.malformedResolvedFile("Missing version field")
        }

        guard [2, 3].contains(version) else {
            throw DependencyTrackerError.unsupportedSchema(version)
        }

        let rawPins = (root["pins"] as? [[String: Any]]) ?? ((root["object"] as? [String: Any])?["pins"] as? [[String: Any]]) ?? []
        let pins = try rawPins.map(parsePin(_:))
        return ResolvedFileDocument(version: version, pins: pins)
    }

    private func parsePin(_ rawPin: [String: Any]) throws -> ResolvedPin {
        let location = (rawPin["location"] as? String) ?? (rawPin["repositoryURL"] as? String) ?? ""
        let identity = ((rawPin["identity"] as? String) ?? (rawPin["package"] as? String) ?? inferredIdentity(from: location)).lowercased()

        let kind: PinKind
        if let rawKind = rawPin["kind"] as? String, let parsedKind = PinKind(rawValue: rawKind) {
            kind = parsedKind
        } else if location.hasPrefix("/") {
            kind = .fileSystem
        } else {
            kind = .remoteSourceControl
        }

        let stateDictionary = rawPin["state"] as? [String: Any] ?? [:]
        let state = try parseState(stateDictionary, kind: kind)

        return ResolvedPin(identity: identity, kind: kind, location: location, state: state)
    }

    private func parseState(_ rawState: [String: Any], kind: PinKind) throws -> PinState {
        if kind == .fileSystem || kind == .localSourceControl, rawState.isEmpty {
            return .local
        }

        let revision = rawState["revision"] as? String ?? ""
        if let version = rawState["version"] as? String {
            return .version(version, revision: revision)
        }

        if let branch = rawState["branch"] as? String {
            return .branch(branch, revision: revision)
        }

        if !revision.isEmpty {
            return .revision(revision)
        }

        if kind == .fileSystem || kind == .localSourceControl {
            return .local
        }

        throw DependencyTrackerError.malformedResolvedFile("Unsupported pin state payload")
    }

    private func inferredIdentity(from location: String) -> String {
        let url = URL(string: location)
        let lastPath = url?.deletingPathExtension().lastPathComponent ?? URL(fileURLWithPath: location).deletingPathExtension().lastPathComponent
        return lastPath.isEmpty ? "unknown" : lastPath
    }
}
