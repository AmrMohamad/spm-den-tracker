import ArgumentParser
import Foundation

/// Validates and normalizes filesystem input before the engine sees it.
enum CLIInput {
    /// Expands tildes, verifies the path exists, and emits a standard CLI validation error otherwise.
    static func resolvedProjectPath(
        _ path: String,
        writeError: (String) -> Void = CLIOutput.writeError
    ) throws -> String {
        let expandedPath = (path as NSString).expandingTildeInPath
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: expandedPath) else {
            writeError("Invalid project path: \(expandedPath)")
            throw ExitCode(65)
        }
        return expandedPath
    }
}
