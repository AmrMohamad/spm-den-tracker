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

    /// Replaces the displayed dependency rows and reloads the table.
    func update(dependencies: [DependencyAnalysis]) {
        self.dependencies = dependencies
        tableView.reloadData()
    }

    /// Installs the fixed column set used by the dependency table.
    @discardableResult
    private func setupColumns() -> CGFloat {
        var totalWidth: CGFloat = 0
        addColumn(identifier: "package", title: "Package", width: 220)
        totalWidth += 220
        addColumn(identifier: "current", title: "Current", width: 120)
        totalWidth += 120
        addColumn(identifier: "declared", title: "Declared", width: 180)
        totalWidth += 180
        addColumn(identifier: "allowed", title: "Allowed", width: 110)
        totalWidth += 110
        addColumn(identifier: "latest", title: "Latest", width: 120)
        totalWidth += 120
        addColumn(identifier: "update", title: "Update", width: 90)
        totalWidth += 90
        addColumn(identifier: "pin", title: "Pin", width: 120)
        totalWidth += 120
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
        case "declared":
            text = dependency.declaredRequirement?.description ?? "—"
        case "allowed":
            text = dependency.latestAllowedVersion ?? "—"
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
        if identifier.rawValue == "update" || identifier.rawValue == "pin" {
            cell.textColor = color(for: dependency)
        }
        return cell
    }

    /// Applies a light risk tint to rows so risky updates are easier to scan.
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.backgroundColor = backgroundColor(for: dependencies[row])
        return rowView
    }

    /// Colors cell text to reinforce update severity and pin risk.
    private func color(for dependency: DependencyAnalysis) -> NSColor {
        switch dependency.outdated?.updateType {
        case .major:
            return .systemRed
        case .minor:
            return .systemOrange
        case .patch:
            return .systemYellow
        case nil:
            break
        }

        switch dependency.strategyRisk {
        case .environmentSensitive:
            return .systemRed
        case .elevated:
            return .systemOrange
        case .normal:
            return .labelColor
        }
    }

    /// Returns the row background color associated with the dependency risk.
    private func backgroundColor(for dependency: DependencyAnalysis) -> NSColor {
        switch dependency.outdated?.updateType {
        case .major:
            return .systemRed.withAlphaComponent(0.08)
        case .minor:
            return .systemOrange.withAlphaComponent(0.08)
        case .patch:
            return .systemYellow.withAlphaComponent(0.05)
        case nil:
            break
        }

        switch dependency.strategyRisk {
        case .environmentSensitive:
            return .systemRed.withAlphaComponent(0.08)
        case .elevated:
            return .systemOrange.withAlphaComponent(0.08)
        case .normal:
            return .clear
        }
    }
}
