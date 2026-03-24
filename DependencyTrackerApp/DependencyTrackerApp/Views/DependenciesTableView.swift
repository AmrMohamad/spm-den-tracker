import AppKit
import DependencyTrackerCore

@MainActor
/// Scrollable table view that renders dependency rows from a `DependencyReport`.
final class DependenciesTableView: NSScrollView {
    /// Backing AppKit table responsible for row rendering and selection behavior.
    private let tableView = NSTableView()
    /// The current dependency rows displayed by the table.
    private var dependencies: [DependencyAnalysis] = []

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

    /// Replaces the displayed dependency rows and reloads the table.
    func update(dependencies: [DependencyAnalysis]) {
        self.dependencies = dependencies
        tableView.reloadData()
    }

    /// Installs the fixed column set used by the dependency table.
    private func setupColumns() {
        addColumn(identifier: "package", title: "Package", width: 220)
        addColumn(identifier: "current", title: "Current", width: 120)
        addColumn(identifier: "latest", title: "Latest", width: 120)
        addColumn(identifier: "update", title: "Update", width: 90)
        addColumn(identifier: "pin", title: "Pin", width: 120)
    }

    /// Adds one configured column to the backing table view.
    private func addColumn(identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }
}

extension DependenciesTableView: NSTableViewDataSource, NSTableViewDelegate {
    /// Returns the number of dependency rows currently displayed.
    func numberOfRows(in tableView: NSTableView) -> Int {
        dependencies.count
    }

    /// Builds the label view for one dependency cell based on the selected column.
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let dependency = dependencies[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let text: String

        switch identifier.rawValue {
        case "current":
            text = dependency.pin.state.displayValue
        case "latest":
            text = dependency.outdated?.latestVersion ?? "—"
        case "update":
            text = dependency.outdated?.updateType?.rawValue ?? "—"
        case "pin":
            text = dependency.pin.state.strategyLabel
        default:
            text = dependency.pin.identity
        }

        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }
}
