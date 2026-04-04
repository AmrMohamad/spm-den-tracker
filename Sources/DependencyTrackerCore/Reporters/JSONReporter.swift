import Foundation

/// Serializes reports into stable, human-readable JSON.
public struct JSONReporter: ReportFormatter {
    /// Creates a JSON reporter with default encoder settings.
    public init() {}

    /// Encodes the report using sorted keys and ISO 8601 dates.
    public func format(_ report: DependencyReport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(report)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Encodes aggregate workspace reports using the same stable JSON settings.
    public func format(_ report: WorkspaceReport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(report)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
