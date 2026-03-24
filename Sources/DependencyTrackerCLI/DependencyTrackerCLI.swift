import ArgumentParser

@main
struct DependencyTrackerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spm-dep-tracker",
        abstract: "Audit the health of Xcode-managed Swift Package dependencies.",
        discussion: """
        Use doctor for a quick health check, report for structured output, and check-tracking for a fast git-status gate.
        """,
        subcommands: [
            Doctor.self,
            Report.self,
            CheckTracking.self,
        ]
    )
}
