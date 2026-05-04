import AppKit
import DependencyTrackerCore

@MainActor
/// Scrollable table view that renders scoped findings from a workspace report.
final class FindingsTableView: NSScrollView {
    /// Backing AppKit table responsible for row rendering and selection behavior.
    private let tableView = NSTableView()
    /// The current finding rows displayed by the table.
    private var findingRows: [ScopedFindingRow] = []

    /// Builds the scroll view and configures the embedded table.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .bezelBorder
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        let tableWidth = setupColumns()
        tableView.frame = NSRect(x: 0, y: 0, width: tableWidth, height: 1)
        documentView = tableView
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.delegate = self
        tableView.dataSource = self
    }

    @available(*, unavailable)
    /// Storyboard/XIB initialization is unsupported because the view is configured in code.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Replaces the displayed finding rows and reloads the table.
    func update(findingRows: [ScopedFindingRow]) {
        self.findingRows = findingRows
        tableView.reloadData()
    }

    /// Installs the fixed column set used by the findings table.
    @discardableResult
    private func setupColumns() -> CGFloat {
        var totalWidth: CGFloat = 0
        addColumn(identifier: "scope", title: "Scope", width: 180)
        totalWidth += 180
        addColumn(identifier: "severity", title: "Severity", width: 80)
        totalWidth += 80
        addColumn(identifier: "category", title: "Category", width: 110)
        totalWidth += 110
        addColumn(identifier: "message", title: "Message", width: 360)
        totalWidth += 360
        addColumn(identifier: "recommendation", title: "Recommendation", width: 360)
        totalWidth += 360
        return totalWidth
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
        findingRows.count
    }

    /// Builds the label view for one finding cell based on the selected column.
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let findingRow = findingRows[row]
        let finding = findingRow.finding
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let text: String

        switch identifier.rawValue {
        case "scope":
            text = findingRow.scope
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
