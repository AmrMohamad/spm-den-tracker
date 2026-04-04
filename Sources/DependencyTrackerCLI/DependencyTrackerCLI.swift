import ArgumentParser

@main
/// Entry point for the command-line interface that exposes all audit subcommands.
struct DependencyTrackerCLI: AsyncParsableCommand {
    /// Declares the root command metadata and available subcommands.
    static let configuration = CommandConfiguration(
        commandName: "spm-dep-tracker",
        abstract: "Inspect Xcode-managed Swift Package dependencies for lockfile, pinning, schema, and update risks.",
        discussion: """
        `spm-dep-tracker` works against the `Package.resolved` file managed inside an Xcode project's workspace metadata.
        You can point commands at any of the following:

        - an `.xcodeproj` bundle
        - a directory containing exactly one `.xcodeproj`
        - a direct `Package.resolved` path

        Subcommands:
        - `doctor`: run the full audit and print a terminal summary
        - `report`: generate table, markdown, or JSON output
        - `graph`: render a workspace graph as Mermaid, DOT, or JSON
        - `check-tracking`: quickly verify whether the lockfile is tracked by git

        Typical usage:
          spm-dep-tracker doctor MyApp.xcodeproj
          spm-dep-tracker report MyApp.xcodeproj --format markdown
          spm-dep-tracker graph . --format mermaid
          spm-dep-tracker check-tracking /path/to/Package.resolved
        """,
        subcommands: [
            Doctor.self,
            Report.self,
            Graph.self,
            CheckTracking.self,
        ]
    )
}
