import Foundation

/// Defines a formatter that turns a dependency report into a user-facing string.
public protocol ReportFormatter: Sendable {
    /// Renders the supplied report into the formatter's output format.
    func format(_ report: DependencyReport) -> String
}
