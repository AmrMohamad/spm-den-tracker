import ArgumentParser

/// The structured output formats supported by the `report` command.
enum ReportFormat: String, ExpressibleByArgument, CaseIterable {
    case table
    case markdown
    case json
    case xcode
    case junit
}
