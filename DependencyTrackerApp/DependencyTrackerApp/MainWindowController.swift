import AppKit
import Combine
import DependencyTrackerCore

@MainActor
/// Builds the AppKit interface and binds it to `TrackerViewModel`.
final class MainWindowController: NSWindowController, NSOpenSavePanelDelegate {
    /// The source of truth for all user-visible analysis state.
    private let viewModel: TrackerViewModel
    /// Combine subscriptions that keep the UI in sync with the view model.
    private var cancellables = Set<AnyCancellable>()

    /// Text field where the user enters or pastes the project path.
    private let pathField = NSTextField()
    /// Button that opens a file picker for the target project.
    private let browseButton = NSButton(title: "Browse…", target: nil, action: nil)
    /// Button that starts the dependency audit.
    private let analyzeButton = NSButton(title: "Analyze", target: nil, action: nil)
    /// Button that exports the latest report as markdown.
    private let markdownButton = NSButton(title: "Export Markdown", target: nil, action: nil)
    /// Button that exports the latest report as JSON.
    private let jsonButton = NSButton(title: "Export JSON", target: nil, action: nil)
    /// Spinner shown while the audit is running.
    private let progressIndicator = NSProgressIndicator()
    /// Inline error label used for validation and runtime failures.
    private let errorLabel = NSTextField(labelWithString: "")
    /// Summary label shown above the tables.
    private let summaryLabel = NSTextField(labelWithString: "No report loaded.")
    /// Table that renders report findings.
    private let findingsTableView = FindingsTableView()
    /// Table that renders dependency rows.
    private let dependenciesTableView = DependenciesTableView()

    /// Creates the window and immediately installs the UI and bindings.
    init(viewModel: TrackerViewModel) {
        self.viewModel = viewModel

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SPM Dependency Tracker"
        window.minSize = NSSize(width: 960, height: 720)
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
        setupUI()
        bindViewModel()
    }

    @available(*, unavailable)
    /// Storyboard/XIB initialization is intentionally unsupported because the window is built in code.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Constructs the entire window layout and configures control defaults.
    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.distribution = .fill
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let pathLabel = NSTextField(labelWithString: "Project")
        pathLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        pathField.placeholderString = "/path/to/MyApp.xcodeproj"
        pathField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        browseButton.target = self
        browseButton.action = #selector(browseTapped)
        analyzeButton.target = self
        analyzeButton.action = #selector(analyzeTapped)
        markdownButton.target = self
        markdownButton.action = #selector(exportMarkdownTapped)
        jsonButton.target = self
        jsonButton.action = #selector(exportJSONTapped)
        markdownButton.isEnabled = false
        jsonButton.isEnabled = false

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false

        let pathRow = NSStackView(views: [pathLabel, pathField, browseButton, analyzeButton, progressIndicator])
        pathRow.orientation = .horizontal
        pathRow.alignment = .centerY
        pathRow.distribution = .fill
        pathRow.spacing = 8
        pathLabel.setContentHuggingPriority(.required, for: .horizontal)
        browseButton.setContentHuggingPriority(.required, for: .horizontal)
        analyzeButton.setContentHuggingPriority(.required, for: .horizontal)
        progressIndicator.setContentHuggingPriority(.required, for: .horizontal)

        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true

        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor

        findingsTableView.translatesAutoresizingMaskIntoConstraints = false
        dependenciesTableView.translatesAutoresizingMaskIntoConstraints = false
        findingsTableView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        dependenciesTableView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        findingsTableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        dependenciesTableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        let findingsSection = sectionContainer(title: "Findings", tableView: findingsTableView)
        let dependenciesSection = sectionContainer(title: "Dependencies", tableView: dependenciesTableView)
        findingsSection.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        dependenciesSection.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let exportRow = NSStackView(views: [markdownButton, jsonButton])
        exportRow.orientation = .horizontal
        exportRow.alignment = .centerY
        exportRow.spacing = 8

        rootStack.addArrangedSubview(pathRow)
        rootStack.addArrangedSubview(errorLabel)
        rootStack.addArrangedSubview(summaryLabel)
        rootStack.addArrangedSubview(findingsSection)
        rootStack.addArrangedSubview(dependenciesSection)
        rootStack.addArrangedSubview(exportRow)

        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            pathRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            errorLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            summaryLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            findingsSection.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            dependenciesSection.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            exportRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
        ])
    }

    /// Subscribes the UI controls to published view-model state.
    private func bindViewModel() {
        pathField.stringValue = viewModel.projectPath

        viewModel.$findings
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.findingsTableView.update(findings: $0) }
            .store(in: &cancellables)

        viewModel.$dependencies
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.dependenciesTableView.update(dependencies: $0) }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.errorLabel.stringValue = message ?? ""
                self?.errorLabel.isHidden = message == nil
            }
            .store(in: &cancellables)

        viewModel.$summaryText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.summaryLabel.stringValue = text
            }
            .store(in: &cancellables)

        viewModel.$isAnalyzing
            .receive(on: RunLoop.main)
            .sink { [weak self] isAnalyzing in
                self?.pathField.isEnabled = !isAnalyzing
                self?.browseButton.isEnabled = !isAnalyzing
                self?.analyzeButton.isEnabled = !isAnalyzing
                if isAnalyzing {
                    self?.progressIndicator.startAnimation(nil)
                } else {
                    self?.progressIndicator.stopAnimation(nil)
                }
            }
            .store(in: &cancellables)

        viewModel.$report
            .receive(on: RunLoop.main)
            .sink { [weak self] report in
                let enabled = report != nil
                self?.markdownButton.isEnabled = enabled
                self?.jsonButton.isEnabled = enabled
            }
            .store(in: &cancellables)
    }

    /// Creates a consistent section heading label for the stacked layout.
    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    /// Wraps a heading and table view into one vertical container.
    private func sectionContainer(title: String, tableView: NSView) -> NSStackView {
        let stack = NSStackView(views: [sectionLabel(title), tableView])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 6
        return stack
    }

    @objc
    /// Prompts the user for a project path and pushes the selection into the view model.
    private func browseTapped() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.resolvesAliases = true
        panel.delegate = self
        panel.message = ProjectSelectionValidator.selectionDescription
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.projectPath = url.path
            pathField.stringValue = url.path
        }
    }

    @objc
    /// Copies the current text-field value into the view model and starts analysis.
    private func analyzeTapped() {
        viewModel.projectPath = pathField.stringValue
        viewModel.analyze()
    }

    @objc
    /// Opens a project from the application menu.
    func openProjectFromMenu(_ sender: Any?) {
        browseTapped()
    }

    @objc
    /// Re-runs the current analysis from the application menu.
    func rerunAnalysisFromMenu(_ sender: Any?) {
        analyzeTapped()
    }

    @objc
    /// Exports the latest report as markdown when one is available.
    private func exportMarkdownTapped() {
        guard let content = viewModel.exportMarkdown() else { return }
        save(content: content, suggestedName: "dependency-report.md")
    }

    @objc
    /// Exports the latest report as JSON when one is available.
    private func exportJSONTapped() {
        guard let content = viewModel.exportJSON() else { return }
        save(content: content, suggestedName: "dependency-report.json")
    }

    /// Saves exported content to a user-selected destination and surfaces write errors inline.
    private func save(content: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorLabel.stringValue = error.localizedDescription
                errorLabel.isHidden = false
            }
        }
    }
}

extension MainWindowController {
    /// Enables only the item kinds that the dependency tracker can consume.
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        guard url.isFileURL else { return true }
        return ProjectSelectionValidator.isSupported(url: url)
    }

    /// Rejects unsupported manual file-name entries with a user-visible explanation.
    func panel(_ sender: Any, validate url: URL, error outError: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool {
        guard ProjectSelectionValidator.isSupported(url: url) else {
            outError?.pointee = ProjectSelectionValidator.validationError()
            return false
        }
        return true
    }
}
