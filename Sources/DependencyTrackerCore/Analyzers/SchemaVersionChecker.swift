import Foundation

/// Interprets the schema version stored in `Package.resolved`.
struct SchemaVersionChecker: Sendable {
    /// The parser used to extract the schema version from disk.
    private let parser = ResolvedFileParser()

    /// Returns schema metadata that can be rendered directly in findings and reports.
    func check(at url: URL) throws -> SchemaInfo {
        let document = try parser.parseDocument(at: url)
        switch document.version {
        case 1:
            return SchemaInfo(
                version: 1,
                compatibility: .legacy,
                message: "Schema version 1 is an older Xcode/SwiftPM format. Verify CI and developer toolchains."
            )
        case 3:
            return SchemaInfo(
                version: 3,
                compatibility: .modern,
                message: "Schema version 3 is the modern Xcode 15+ format."
            )
        case 2:
            return SchemaInfo(
                version: 2,
                compatibility: .legacy,
                message: "Schema version 2 is older than the modern Xcode 15+/16+ default. Verify CI and developer toolchains."
            )
        default:
            return SchemaInfo(
                version: document.version,
                compatibility: .unknown,
                message: "Unknown Package.resolved schema version."
            )
        }
    }
}
