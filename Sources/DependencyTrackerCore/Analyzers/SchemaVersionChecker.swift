import Foundation

struct SchemaVersionChecker: Sendable {
    private let parser = ResolvedFileParser()

    func check(at url: URL) throws -> SchemaInfo {
        let document = try parser.parseDocument(at: url)
        switch document.version {
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
