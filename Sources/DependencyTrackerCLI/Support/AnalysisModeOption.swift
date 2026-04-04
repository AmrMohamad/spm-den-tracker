import ArgumentParser
import DependencyTrackerCore

/// CLI-facing analysis modes mapped onto the core tracker configuration.
enum AnalysisModeOption: String, ExpressibleByArgument {
    case auto
    case monorepo
    case singleTarget = "single-target"

    /// Converts the CLI option into the core analysis mode enum.
    var coreValue: AnalysisMode {
        switch self {
        case .auto:
            return .auto
        case .monorepo:
            return .monorepo
        case .singleTarget:
            return .singleTarget
        }
    }
}

