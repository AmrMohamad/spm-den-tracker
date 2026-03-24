import Foundation

/// Centralizes terminal and file output so commands stay easy to test.
enum CLIOutput {
    /// Writes a line of text to standard output, ensuring a trailing newline.
    static func write(_ text: String) {
        var output = text
        if !output.hasSuffix("\n") {
            output.append("\n")
        }
        FileHandle.standardOutput.write(Data(output.utf8))
    }

    /// Writes a line of text to standard error, ensuring a trailing newline.
    static func writeError(_ text: String) {
        var output = text
        if !output.hasSuffix("\n") {
            output.append("\n")
        }
        FileHandle.standardError.write(Data(output.utf8))
    }

    /// Writes text to disk, creating intermediate directories as needed for nested report paths.
    static func write(_ text: String, to url: URL) throws {
        let directoryURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
