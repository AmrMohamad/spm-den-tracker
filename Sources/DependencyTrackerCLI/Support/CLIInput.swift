import ArgumentParser
import Foundation

enum CLIInput {
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
