import Foundation
import Testing
@testable import DependencyTrackerCore

struct ReporterTests {
    @Test
    func markdownReporterIncludesFindingsAndDependencyTable() {
        let report = sampleReport()

        let output = MarkdownReporter().format(report)

        #expect(output.contains("# SPM Dependency Report"))
        #expect(output.contains("## Findings"))
        #expect(output.contains("| Package | Current | Declared | Allowed | Latest | Update | Pin State |"))
    }

    @Test
    func tableReporterDoesNotTruncateLongPackageNames() {
        let output = TableReporter().format(sampleReport())

        #expect(output.contains("swift-package-with-a-very-long-identity"))
    }

    @Test
    func jsonReporterEmitsCodablePayload() throws {
        let report = sampleReport()

        let output = JSONReporter().format(report)
        let data = Data(output.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DependencyReport.self, from: data)

        #expect(decoded.projectPath == report.projectPath)
        #expect(decoded.dependencies.count == 1)
    }

    @Test
    func xcodeReporterFormatsCompilerStyleLines() {
        let output = XcodeReporter().format(actionableReport())

        #expect(output.contains(": warning: [declaredConstraint]"))
        #expect(output.contains("can update from 5.9.1 to 5.10.0"))
    }

    @Test
    func junitReporterEmitsFailuresForActionableFindings() {
        let output = JUnitReporter().format(actionableReport())

        #expect(output.contains("<testsuite"))
        #expect(output.contains("<failure message="))
        #expect(output.contains("spm-dep-tracker.declaredConstraint"))
    }
}

private func sampleReport() -> DependencyReport {
    let pin = ResolvedPin(identity: "swift-package-with-a-very-long-identity", kind: .remoteSourceControl, location: "https://github.com/Alamofire/Alamofire.git", state: .version("5.9.1", revision: "abc"))
    let outdated = OutdatedResult(pin: pin, latestVersion: "5.10.0", updateType: .minor, isOutdated: true)
    return DependencyReport(
        projectPath: "/tmp/App.xcodeproj",
        generatedAt: Date(timeIntervalSince1970: 0),
        resolvedFilePath: "/tmp/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        resolvedFileStatus: .tracked,
        schemaVersion: SchemaInfo(version: 3, compatibility: .modern, message: "Schema version 3 is the modern Xcode 15+ format."),
        dependencies: [DependencyAnalysis(pin: pin, outdated: outdated, strategyRisk: .normal)],
        findings: [Finding(severity: .info, category: .outdated, message: "1 dependency has an update.", recommendation: "Review the dependency table.")]
    )
}

private func actionableReport() -> DependencyReport {
    let pin = ResolvedPin(identity: "alamofire", kind: .remoteSourceControl, location: "https://github.com/Alamofire/Alamofire.git", state: .version("5.9.1", revision: "abc"))
    let outdated = OutdatedResult(pin: pin, latestVersion: "5.10.0", updateType: .minor, isOutdated: true)
    return DependencyReport(
        projectPath: "/tmp/App.xcodeproj",
        generatedAt: Date(timeIntervalSince1970: 0),
        resolvedFilePath: "/tmp/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        resolvedFileStatus: .tracked,
        schemaVersion: SchemaInfo(version: 3, compatibility: .modern, message: "Schema version 3 is the modern Xcode 15+ format."),
        dependencies: [
            DependencyAnalysis(
                pin: pin,
                outdated: outdated,
                strategyRisk: .normal,
                declaredRequirement: DeclaredRequirement(
                    identity: "alamofire",
                    source: .xcodeProject,
                    kind: .upToNextMajor,
                    lowerBound: "5.9.1",
                    location: "https://github.com/Alamofire/Alamofire.git",
                    description: "from 5.9.1"
                ),
                constraintDrift: .newerAllowedAvailable,
                latestAllowedVersion: "5.10.0"
            )
        ],
        findings: [
            Finding(
                severity: .warning,
                category: .declaredConstraint,
                message: "\"alamofire\" can update from 5.9.1 to 5.10.0 without changing the declared requirement.",
                recommendation: "Run an update and commit the refreshed Package.resolved if you want the newest version already allowed by policy.",
                isActionable: true
            )
        ]
    )
}
