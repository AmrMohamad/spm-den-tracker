import AppKit
import DependencyTrackerCore

@MainActor
/// Scrollable table view that renders findings from a `DependencyReport`.
final class FindingsTableView: NSScrollView {
    /// Backing AppKit table responsible for row rendering and selection behavior.
    private let tableView = NSTableView()
    /// The current finding rows displayed by the table.
    private var findings: [Finding] = []

    /// Builds the scroll view and configures the embedded table.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .bezelBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        documentView = tableView
        setupColumns()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.delegate = self
        tableView.dataSource = self
    }

    @available(*, unavailable)
    /// Storyboard/XIB initialization is unsupported because the view is configured in code.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Replaces the displayed finding rows and reloads the table.
    func update(findings: [Finding]) {
        self.findings = findings
        tableView.reloadData()
    }

    /// Installs the fixed column set used by the findings table.
    private func setupColumns() {
        addColumn(identifier: "severity", title: "Severity", width: 80)
        addColumn(identifier: "category", title: "Category", width: 110)
        addColumn(identifier: "message", title: "Message", width: 360)
        addColumn(identifier: "recommendation", title: "Recommendation", width: 360)
    }

    /// Adds one configured column to the backing table view.
    private func addColumn(identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }
}

extension FindingsTableView: NSTableViewDataSource, NSTableViewDelegate {
    /// Returns the number of finding rows currently displayed.
    func numberOfRows(in tableView: NSTableView) -> Int {
        findings.count
    }

    /// Builds the label view for one finding cell based on the selected column.
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

    /// Maps finding severities to the colors used in the first column.
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
