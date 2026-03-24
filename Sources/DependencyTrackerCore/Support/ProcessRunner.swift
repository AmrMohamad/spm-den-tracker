import Foundation

struct ProcessResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

protocol ProcessRunning: Sendable {
    func run(arguments: [String], currentDirectoryURL: URL?, timeout: TimeInterval) async throws -> ProcessResult
}

struct ProcessRunner: ProcessRunning {
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

    private func collect(from stream: AsyncThrowingStream<Data, Error>) async throws -> Data {
        var data = Data()
        for try await chunk in stream {
            data.append(chunk)
        }
        return data
    }

    private func timeoutNanoseconds(for timeout: TimeInterval) -> UInt64 {
        UInt64((timeout * 1_000_000_000).rounded(.up))
    }
}
