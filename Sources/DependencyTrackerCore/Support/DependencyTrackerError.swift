import Foundation

/// Enumerates the user-facing failures the tracker can emit.
public enum DependencyTrackerError: LocalizedError, Sendable {
    /// The supplied path did not exist or could not be interpreted as a supported input.
    case invalidPath(String)
    /// A directory path contained multiple candidate projects and therefore could not be resolved safely.
    case ambiguousProjectPath(String, candidates: [String])
    /// The resolved file uses a schema version the parser does not understand.
    case unsupportedSchema(Int)
    /// The resolved file was present but malformed.
    case malformedResolvedFile(String)
    /// An external command finished with a non-zero exit status.
    case commandFailed(command: [String], status: Int32, stderr: String)
    /// An external command exceeded its allowed runtime.
    case commandTimedOut(command: [String], timeout: TimeInterval)

    /// Returns the localized description surfaced by the CLI and app UI.
    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Invalid project path: \(path)"
        case .ambiguousProjectPath(let path, let candidates):
            return "Multiple .xcodeproj bundles found under \(path): \(candidates.joined(separator: ", "))"
        case .unsupportedSchema(let version):
            return "Unsupported Package.resolved schema version \(version)"
        case .malformedResolvedFile(let message):
            return "Malformed Package.resolved: \(message)"
        case .commandFailed(let command, let status, let stderr):
            let detail = stderr.isEmpty ? "no stderr" : stderr
            return "Command failed (\(status)): \(command.joined(separator: " ")) — \(detail)"
        case .commandTimedOut(let command, let timeout):
            return "Command timed out after \(Int(timeout))s: \(command.joined(separator: " "))"
        }
    }
}
