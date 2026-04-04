import ArgumentParser

/// The graph output formats supported by the `graph` command.
enum GraphFormat: String, ExpressibleByArgument, CaseIterable {
    case mermaid
    case dot
    case json
}

