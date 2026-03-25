import Foundation
import Testing
@testable import DependencyTrackerCore

struct ProcessRunnerTests {
    @Test
    func rejectsNegativeTimeout() async throws {
        do {
            _ = try await ProcessRunner().run(
                arguments: ["sh", "-c", "echo ok"],
                currentDirectoryURL: nil,
                timeout: -1
            )
            Issue.record("Expected invalid timeout.")
        } catch let error as DependencyTrackerError {
            guard case .invalidTimeout(let timeout) = error, timeout == -1 else {
                Issue.record("Expected invalidTimeout(-1), got \(error)")
                return
            }
        }
    }

    @Test
    func rejectsZeroTimeout() async throws {
        do {
            _ = try await ProcessRunner().run(
                arguments: ["sh", "-c", "echo ok"],
                currentDirectoryURL: nil,
                timeout: 0
            )
            Issue.record("Expected invalid timeout.")
        } catch let error as DependencyTrackerError {
            guard case .invalidTimeout(let timeout) = error, timeout == 0 else {
                Issue.record("Expected invalidTimeout(0), got \(error)")
                return
            }
        }
    }

    @Test
    func rejectsNaNTimeout() async throws {
        do {
            _ = try await ProcessRunner().run(
                arguments: ["sh", "-c", "echo ok"],
                currentDirectoryURL: nil,
                timeout: .nan
            )
            Issue.record("Expected invalid timeout.")
        } catch let error as DependencyTrackerError {
            guard case .invalidTimeout(let timeout) = error, timeout.isNaN else {
                Issue.record("Expected invalidTimeout(nan), got \(error)")
                return
            }
        }
    }

    @Test
    func rejectsInfiniteTimeout() async throws {
        do {
            _ = try await ProcessRunner().run(
                arguments: ["sh", "-c", "echo ok"],
                currentDirectoryURL: nil,
                timeout: .infinity
            )
            Issue.record("Expected invalid timeout.")
        } catch let error as DependencyTrackerError {
            guard case .invalidTimeout(let timeout) = error, timeout.isInfinite else {
                Issue.record("Expected invalidTimeout(infinity), got \(error)")
                return
            }
        }
    }

    @Test
    func rejectsVeryLargeFiniteTimeouts() async throws {
        do {
            _ = try await ProcessRunner().run(
                arguments: ["sh", "-c", "echo ok"],
                currentDirectoryURL: nil,
                timeout: Double.greatestFiniteMagnitude
            )
            Issue.record("Expected invalid timeout.")
        } catch let error as DependencyTrackerError {
            guard case .invalidTimeout(let timeout) = error, timeout == Double.greatestFiniteMagnitude else {
                Issue.record("Expected invalidTimeout(Double.greatestFiniteMagnitude), got \(error)")
                return
            }
        }
    }

    @Test
    func capturesStdoutAndStderr() async throws {
        let result = try await ProcessRunner().run(
            arguments: ["sh", "-c", "printf 'hello'; printf 'warning' >&2"],
            currentDirectoryURL: nil,
            timeout: 2
        )

        #expect(result.status == 0)
        #expect(result.stdout == "hello")
        #expect(result.stderr == "warning")
    }

    @Test
    func timesOutLongRunningProcesses() async throws {
        do {
            _ = try await ProcessRunner().run(
                arguments: ["sh", "-c", "sleep 2"],
                currentDirectoryURL: nil,
                timeout: 0.1
            )
            Issue.record("Expected command timeout.")
        } catch let error as DependencyTrackerError {
            guard case .commandTimedOut = error else {
                Issue.record("Expected commandTimedOut, got \(error)")
                return
            }
        }
    }

    @Test
    func propagatesCancellation() async throws {
        let task = Task {
            try await ProcessRunner().run(
                arguments: ["sh", "-c", "sleep 5"],
                currentDirectoryURL: nil,
                timeout: 10
            )
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation.")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }
}
