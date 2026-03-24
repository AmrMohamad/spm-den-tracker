import Foundation

public struct JSONReporter: ReportFormatter {
    public init() {}

    public func format(_ report: DependencyReport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(report)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
