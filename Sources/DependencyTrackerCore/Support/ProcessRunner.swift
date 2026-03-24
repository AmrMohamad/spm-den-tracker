import Foundation

/// Contains the exit status and collected output of a child process.
struct ProcessResult: Sendable {
    /// The process termination status reported by `Process`.
    let status: Int32
    /// The full standard-output payload collected during execution.
    let stdout: String
    /// The full standard-error payload collected during execution.
    let stderr: String
}

/// Abstracts async process execution so command-oriented code stays testable.
protocol ProcessRunning: Sendable {
    /// Runs a command in an optional working directory and either returns collected output or throws.
    ///
    /// - Parameters:
    ///   - arguments: The command and its arguments, passed through `/usr/bin/env`.
    ///   - currentDirectoryURL: The working directory for the process, or `nil` to inherit.
    ///   - timeout: Maximum allowed runtime before the command is terminated.
    /// - Returns: The exit status plus the fully collected stdout and stderr payloads.
    func run(arguments: [String], currentDirectoryURL: URL?, timeout: TimeInterval) async throws -> ProcessResult
}

/// Runs shell commands asynchronously while supporting timeouts and cooperative cancellation.
struct ProcessRunner: ProcessRunning {
    /// Executes a command, streams both output channels concurrently, and terminates on timeout or cancellation.
    ///
    /// The implementation uses streaming reads instead of `waitUntilExit()` plus blocking file
    /// reads so long-running commands cannot deadlock on full pipes. Cancellation and timeout both
    /// terminate the child process, which keeps higher-level audit tasks from leaking subprocesses.
    ///
    /// - Parameters:
    ///   - arguments: The command and arguments to launch through `/usr/bin/env`.
    ///   - currentDirectoryURL: The working directory to run in, if one is required.
    ///   - timeout: Maximum process lifetime in seconds.
    /// - Returns: A `ProcessResult` containing the exit status and full collected output.
    /// - Throws: `DependencyTrackerError.commandTimedOut`, `CancellationError`, or the underlying
    ///   `Process.run()` failure when launch itself fails.
    func run(arguments: [String], currentDirectoryURL: URL?, timeout: TimeInterval) async throws -> ProcessResult {
        precondition(!arguments.isEmpty, "Process arguments must not be empty")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutStream = makeStream(for: stdoutPipe.fileHandleForReading)
        let stderrStream = makeStream(for: stderrPipe.fileHandleForReading)

        return try await withTaskCancellationHandler {
            try process.run()

            async let stdoutData = collect(from: stdoutStream)
            async let stderrData = collect(from: stderrStream)
            let status = try await waitForExit(of: process, command: arguments, timeout: timeout)
            let stdout = String(decoding: try await stdoutData, as: UTF8.self)
            let stderr = String(decoding: try await stderrData, as: UTF8.self)

            return ProcessResult(status: status, stdout: stdout, stderr: stderr)
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    /// Waits for either process termination or the timeout, whichever happens first.
    ///
    /// The task group races a termination callback against a timed sleep. Whichever finishes first
    /// wins, and the other branch is cancelled so the caller gets a single, well-defined outcome.
    private func waitForExit(of process: Process, command: [String], timeout: TimeInterval) async throws -> Int32 {
        let terminationStream = AsyncStream<Int32> { continuation in
            process.terminationHandler = { process in
                continuation.yield(process.terminationStatus)
                continuation.finish()
            }
        }

        return try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                for await status in terminationStream {
                    return status
                }
                throw CancellationError()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds(for: timeout))
                throw DependencyTrackerError.commandTimedOut(command: command, timeout: timeout)
            }

            do {
                let status = try await group.next() ?? 0
                group.cancelAll()
                return status
            } catch {
                group.cancelAll()
                if case DependencyTrackerError.commandTimedOut = error, process.isRunning {
                    process.terminate()
                }
                throw error
            }
        }
    }

    /// Bridges `FileHandle.readabilityHandler` into an async byte stream.
    ///
    /// This adapter keeps stdout and stderr consumable with `for try await` without exposing the
    /// rest of the process runner to callback-style file handling.
    private func makeStream(for handle: FileHandle) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                if data.isEmpty {
                    fileHandle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                continuation.yield(data)
            }

            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }

    /// Collects all chunks from one output stream into a single buffer.
    ///
    /// Output is accumulated after launch so callers can still reason about complete stdout/stderr
    /// strings while the implementation preserves non-blocking reads internally.
    private func collect(from stream: AsyncThrowingStream<Data, Error>) async throws -> Data {
        var data = Data()
        for try await chunk in stream {
            data.append(chunk)
        }
        return data
    }

    /// Converts a timeout interval into the nanoseconds expected by `Task.sleep`.
    ///
    /// The timeout rounds up so fractional seconds never produce a zero-duration sleep.
    private func timeoutNanoseconds(for timeout: TimeInterval) -> UInt64 {
        UInt64((timeout * 1_000_000_000).rounded(.up))
    }
}
