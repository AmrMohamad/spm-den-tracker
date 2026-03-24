import Foundation
import Testing
@testable import DependencyTrackerCore

struct ResolvedFileParserTests {
    private let parser = ResolvedFileParser()

    @Test
    func parsesVersion2Fixture() throws {
        let document = try parser.parseDocument(at: fixtureURL(named: "Package.resolved.v2.json"))

        #expect(document.version == 2)
        #expect(document.pins.count == 2)
        #expect(document.pins[0].identity == "alamofire")
        #expect(document.pins[0].state.displayValue == "5.9.1")
        #expect(document.pins[1].state.strategyLabel == "branch")
    }

    @Test
    func parsesVersion3Fixture() throws {
        let document = try parser.parseDocument(at: fixtureURL(named: "Package.resolved.v3.json"))

        #expect(document.version == 3)
        #expect(document.pins.count == 2)
        #expect(document.pins[0].identity == "kingfisher")
        #expect(document.pins[1].kind == .fileSystem)
        #expect(document.pins[1].state == .local)
    }

    @Test
    func parsesRevisionOnlyPins() throws {
        let url = try writeTemporaryResolvedFile("""
        {
          "version": 3,
          "pins": [
            {
              "identity": "revision-only",
              "location": "https://example.com/revision-only.git",
              "state": {
                "revision": "1234567890abcdef"
              }
            }
          ]
        }
        """)

        let document = try parser.parseDocument(at: url)

        #expect(document.pins.count == 1)
        #expect(document.pins[0].state == .revision("1234567890abcdef"))
    }

    @Test
    func rejectsMalformedJSON() throws {
        let url = try writeTemporaryResolvedFile("{")

        #expect(throws: Error.self) {
            try parser.parseDocument(at: url)
        }
    }

    @Test
    func rejectsUnsupportedSchemaVersion() throws {
        let url = try writeTemporaryResolvedFile("""
        {
          "version": 4,
          "pins": []
        }
        """)

        #expect(throws: DependencyTrackerError.self) {
            try parser.parseDocument(at: url)
        }
    }

    @Test
    func schemaCheckerReturnsLegacyForVersion2() throws {
        let info = try SchemaVersionChecker().check(at: fixtureURL(named: "Package.resolved.v2.json"))

        #expect(info.version == 2)
        #expect(info.compatibility == .legacy)
    }

    @Test
    func schemaCheckerReturnsModernForVersion3() throws {
        let info = try SchemaVersionChecker().check(at: fixtureURL(named: "Package.resolved.v3.json"))

        #expect(info.version == 3)
        #expect(info.compatibility == .modern)
    }
}

private func fixtureURL(named name: String) -> URL {
    Bundle.module.resourceURL!
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent(name)
}

private func writeTemporaryResolvedFile(_ contents: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("Package.resolved")
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
}
