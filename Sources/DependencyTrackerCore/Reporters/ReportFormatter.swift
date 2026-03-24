import Foundation

public protocol ReportFormatter: Sendable {
    func format(_ report: DependencyReport) -> String
}
