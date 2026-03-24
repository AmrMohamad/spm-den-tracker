import ArgumentParser
import Foundation

enum CLIInput {
    static func resolvedProjectPath(_ path: String) throws -> String {
        let expandedPath = (path as NSString).expandingTildeInPath
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: expandedPath) else {
            throw ExitCode(65)
        }
        return expandedPath
    }
}
