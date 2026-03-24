import Foundation

enum CLIOutput {
    static func write(_ text: String) {
        var output = text
        if !output.hasSuffix("\n") {
            output.append("\n")
        }
        FileHandle.standardOutput.write(Data(output.utf8))
    }

    static func writeError(_ text: String) {
        var output = text
        if !output.hasSuffix("\n") {
            output.append("\n")
        }
        FileHandle.standardError.write(Data(output.utf8))
    }

    static func write(_ text: String, to url: URL) throws {
        let directoryURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
