import AppKit
import DependencyTrackerCore

@MainActor
final class DependenciesTableView: NSScrollView {
    private let tableView = NSTableView()
    private var dependencies: [DependencyAnalysis] = []

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
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(dependencies: [DependencyAnalysis]) {
        self.dependencies = dependencies
        tableView.reloadData()
    }

    private func setupColumns() {
        addColumn(identifier: "package", title: "Package", width: 220)
        addColumn(identifier: "current", title: "Current", width: 120)
        addColumn(identifier: "latest", title: "Latest", width: 120)
        addColumn(identifier: "update", title: "Update", width: 90)
        addColumn(identifier: "pin", title: "Pin", width: 120)
    }

    private func addColumn(identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }
}

extension DependenciesTableView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        dependencies.count
    }

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
