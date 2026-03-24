import Foundation

public enum DependencyTrackerError: LocalizedError, Sendable {
    case invalidPath(String)
    case ambiguousProjectPath(String, candidates: [String])
    case unsupportedSchema(Int)
    case malformedResolvedFile(String)
    case commandFailed(command: [String], status: Int32, stderr: String)
    case commandTimedOut(command: [String], timeout: TimeInterval)

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
