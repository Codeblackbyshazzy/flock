import AppKit

// MARK: - AgentCardPanel

/// Scrollable container that shows stacked AgentCardView instances
/// for in-progress tasks or a selected task from the TaskStore.
final class AgentCardPanel: NSView {

    override var isFlipped: Bool { true }

    private let scrollView = NSScrollView()
    private let documentView = FlippedDocumentView()
    private var cardViews: [UUID: AgentCardView] = [:]
    private let emptyLabel = NSTextField(labelWithString: "No agents running")

    /// When set to a non-in-progress task, the panel shows only that task's card.
    /// When nil (or the task is in-progress), the panel shows all in-progress tasks.
    var selectedTask: AgentTask? {
        didSet {
            refresh()
        }
    }

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setup() {
        // Scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = documentView
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        addSubview(scrollView)

        // Empty state label
        emptyLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        emptyLabel.textColor = Theme.textTertiary
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        // Observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTaskStoreChange),
            name: TaskStore.didChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: Theme.themeDidChange,
            object: nil
        )

        refresh()
    }

    // MARK: - Layout

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)

        scrollView.frame = bounds
        layoutCards()

        // Center the empty label
        emptyLabel.sizeToFit()
        emptyLabel.frame.origin = NSPoint(
            x: (bounds.width - emptyLabel.frame.width) / 2,
            y: (bounds.height - emptyLabel.frame.height) / 2
        )
    }

    private func layoutCards() {
        let width = bounds.width
        let gap = Theme.paneGap
        let tasks = displayedTasks

        // Calculate the natural (content-based) height for each card
        var naturalHeights: [(UUID, CGFloat)] = []
        for task in tasks {
            guard cardViews[task.id] != nil else { continue }
            let cardHeight = AgentCardView.preferredHeight(for: task)
            naturalHeights.append((task.id, cardHeight))
        }

        let cardCount = naturalHeights.count
        guard cardCount > 0 else {
            documentView.frame = NSRect(x: 0, y: 0, width: width, height: 0)
            return
        }

        let totalGaps = CGFloat(cardCount - 1) * gap
        let totalNaturalHeight = naturalHeights.reduce(CGFloat(0)) { $0 + $1.1 }
        let availableHeight = scrollView.frame.height

        // If cards fit within available space, expand them proportionally to fill it
        let needsExpansion = totalNaturalHeight + totalGaps < availableHeight
        let expandableSpace = availableHeight - totalGaps
        let scale = needsExpansion ? expandableSpace / totalNaturalHeight : 1.0

        var y: CGFloat = 0
        for (id, naturalHeight) in naturalHeights {
            guard let card = cardViews[id] else { continue }
            let cardHeight = needsExpansion ? naturalHeight * scale : naturalHeight
            card.frame = NSRect(x: 0, y: y, width: width, height: cardHeight)
            y += cardHeight + gap
        }

        // Remove trailing gap
        let totalHeight = max(y - gap, 0)
        documentView.frame = NSRect(x: 0, y: 0, width: width, height: totalHeight)
    }

    // MARK: - Displayed Tasks

    /// Returns the tasks that should be displayed: either a single selected
    /// (non-in-progress) task, or all in-progress tasks.
    private var displayedTasks: [AgentTask] {
        if let selected = selectedTask, selected.status != .inProgress {
            return [selected]
        }
        return TaskStore.shared.inProgress
    }

    // MARK: - Refresh

    func refresh() {
        let tasksToShow = displayedTasks
        let currentIds = Set(tasksToShow.map { $0.id })
        let existingIds = Set(cardViews.keys)

        // Remove cards for tasks no longer displayed
        for id in existingIds.subtracting(currentIds) {
            cardViews[id]?.removeFromSuperview()
            cardViews.removeValue(forKey: id)
        }

        // Add new cards / update existing
        for task in tasksToShow {
            if let existing = cardViews[task.id] {
                existing.task = task
            } else {
                let card = AgentCardView()
                card.task = task
                documentView.addSubview(card)
                cardViews[task.id] = card
            }
        }

        // Empty state
        let empty = tasksToShow.isEmpty
        emptyLabel.stringValue = TaskStore.shared.tasks.isEmpty ? "No agents running" : "Select a task"
        emptyLabel.isHidden = !empty
        scrollView.isHidden = empty

        layoutCards()
    }

    // MARK: - Notifications

    @objc private func handleTaskStoreChange() {
        refresh()
    }

    @objc private func handleThemeChange() {
        emptyLabel.textColor = Theme.textTertiary
    }
}

// MARK: - FlippedDocumentView

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
