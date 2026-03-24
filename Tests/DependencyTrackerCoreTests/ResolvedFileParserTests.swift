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
