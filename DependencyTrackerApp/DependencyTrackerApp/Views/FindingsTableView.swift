import AppKit
import DependencyTrackerCore

@MainActor
final class FindingsTableView: NSScrollView {
    private let tableView = NSTableView()
    private var findings: [Finding] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .bezelBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        documentView = tableView
        setupColumns()
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.delegate = self
        tableView.dataSource = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(findings: [Finding]) {
        self.findings = findings
        tableView.reloadData()
    }

    private func setupColumns() {
        addColumn(identifier: "severity", title: "Severity", width: 80)
        addColumn(identifier: "category", title: "Category", width: 110)
        addColumn(identifier: "message", title: "Message", width: 360)
        addColumn(identifier: "recommendation", title: "Recommendation", width: 360)
    }

    private func addColumn(identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }
}

extension FindingsTableView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        findings.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let finding = findings[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let text: String

        switch identifier.rawValue {
        case "severity":
            text = finding.severity.rawValue.uppercased()
        case "category":
            text = finding.category.rawValue
        case "recommendation":
            text = finding.recommendation
        default:
            text = finding.message
        }

        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingTail
        if identifier.rawValue == "severity" {
            cell.textColor = color(for: finding.severity)
        }
        return cell
    }

    private func color(for severity: Severity) -> NSColor {
        switch severity {
        case .info:
            return .labelColor
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }
}
