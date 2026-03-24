import Foundation

struct ProcessResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

protocol ProcessRunning: Sendable {
    func run(arguments: [String], currentDirectoryURL: URL?, timeout: TimeInterval) throws -> ProcessResult
}

struct ProcessRunner: ProcessRunning {
    func run(arguments: [String], currentDirectoryURL: URL?, timeout: TimeInterval) throws -> ProcessResult {
        precondition(!arguments.isEmpty, "Process arguments must not be empty")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let start = Date()
        while process.isRunning {
            if Date().timeIntervalSince(start) > timeout {
                process.terminate()
                throw DependencyTrackerError.commandTimedOut(command: arguments, timeout: timeout)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        return ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
