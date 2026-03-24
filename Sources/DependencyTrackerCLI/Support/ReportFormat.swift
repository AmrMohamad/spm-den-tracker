import ArgumentParser

enum ReportFormat: String, ExpressibleByArgument, CaseIterable {
    case table
    case markdown
    case json
}
