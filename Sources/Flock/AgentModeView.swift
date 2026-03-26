import AppKit

// MARK: - AgentModeView

/// Sculptor-style three-panel layout: sidebar (agent list) + conversation stream + detail panel.
final class AgentModeView: NSView {

    override var isFlipped: Bool { true }

    let sidebar = AgentSidebarView()
    let conversation = AgentConversationView()
    let detail = AgentDetailView()
    private let divider1 = NSView()
    private let divider2 = NSView()

    private let sidebarWidth: CGFloat = 200
    private let detailRatio: CGFloat = 0.35

    private(set) var selectedTaskID: UUID?

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
        wantsLayer = true
        layer?.backgroundColor = Theme.chrome.cgColor

        divider1.wantsLayer = true
        divider1.layer?.backgroundColor = Theme.divider.cgColor
        divider2.wantsLayer = true
        divider2.layer?.backgroundColor = Theme.divider.cgColor

        addSubview(sidebar)
        addSubview(divider1)
        addSubview(conversation)
        addSubview(divider2)
        addSubview(detail)

        sidebar.onSelectTask = { [weak self] task in
            self?.selectTask(task)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChange),
            name: Theme.themeDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleTaskStoreChange),
            name: TaskStore.didChange, object: nil
        )
    }

    // MARK: - Selection

    func selectTask(_ task: AgentTask?) {
        selectedTaskID = task?.id
        sidebar.selectedTaskID = task?.id
        conversation.task = task
        detail.task = task
        sidebar.needsDisplay = true
    }

    private func autoSelectIfNeeded() {
        // If selection is still valid, do nothing -- sub-views observe TaskStore.didChange themselves
        if let id = selectedTaskID,
           TaskStore.shared.tasks.contains(where: { $0.id == id }) {
            return
        }

        // Selection gone -- pick next available
        let next = TaskStore.shared.inProgress.first ?? TaskStore.shared.tasks.first
        selectTask(next)
    }

    // MARK: - Layout

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)

        let padding = Theme.panePadding
        let gap = Theme.paneGap

        let insetBounds = NSRect(
            x: padding,
            y: padding,
            width: bounds.width - padding * 2,
            height: bounds.height - padding * 2
        )

        let dividerWidth: CGFloat = 1
        let remaining = insetBounds.width - sidebarWidth - dividerWidth * 2 - gap * 4
        let detailWidth = floor(remaining * detailRatio)
        let conversationWidth = remaining - detailWidth

        sidebar.frame = NSRect(
            x: insetBounds.minX,
            y: insetBounds.minY,
            width: sidebarWidth,
            height: insetBounds.height
        )

        divider1.frame = NSRect(
            x: insetBounds.minX + sidebarWidth + gap,
            y: insetBounds.minY,
            width: dividerWidth,
            height: insetBounds.height
        )

        conversation.frame = NSRect(
            x: divider1.frame.maxX + gap,
            y: insetBounds.minY,
            width: conversationWidth,
            height: insetBounds.height
        )

        divider2.frame = NSRect(
            x: conversation.frame.maxX + gap,
            y: insetBounds.minY,
            width: dividerWidth,
            height: insetBounds.height
        )

        detail.frame = NSRect(
            x: divider2.frame.maxX + gap,
            y: insetBounds.minY,
            width: detailWidth,
            height: insetBounds.height
        )
    }

    // MARK: - Notifications

    @objc private func handleThemeChange() {
        layer?.backgroundColor = Theme.chrome.cgColor
        divider1.layer?.backgroundColor = Theme.divider.cgColor
        divider2.layer?.backgroundColor = Theme.divider.cgColor
    }

    @objc private func handleTaskStoreChange() {
        autoSelectIfNeeded()
    }
}
