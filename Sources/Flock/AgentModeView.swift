import AppKit

// MARK: - AgentModeView

/// Top-level split container: Kanban board on the left (35%),
/// vertical divider, and AgentCardPanel on the right (65%).
final class AgentModeView: NSView {

    override var isFlipped: Bool { true }

    let kanban = KanbanBoardView()
    let agentPanel = AgentCardPanel()
    private let divider = NSView()
    private let splitRatio: CGFloat = 0.35

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

        // Divider
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.divider.cgColor

        addSubview(kanban)
        addSubview(divider)
        addSubview(agentPanel)

        // Wire kanban task selection to the agent card panel
        kanban.onSelectTask = { [weak self] task in
            self?.agentPanel.selectedTask = task
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: Theme.themeDidChange,
            object: nil
        )
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

        let kanbanWidth = floor(insetBounds.width * splitRatio)
        let dividerWidth: CGFloat = 1
        let panelWidth = insetBounds.width - kanbanWidth - dividerWidth - gap * 2

        kanban.frame = NSRect(
            x: insetBounds.minX,
            y: insetBounds.minY,
            width: kanbanWidth,
            height: insetBounds.height
        )

        divider.frame = NSRect(
            x: insetBounds.minX + kanbanWidth + gap,
            y: insetBounds.minY,
            width: dividerWidth,
            height: insetBounds.height
        )

        agentPanel.frame = NSRect(
            x: insetBounds.minX + kanbanWidth + gap + dividerWidth + gap,
            y: insetBounds.minY,
            width: panelWidth,
            height: insetBounds.height
        )
    }

    // MARK: - Theme

    @objc private func handleThemeChange() {
        layer?.backgroundColor = Theme.chrome.cgColor
        divider.layer?.backgroundColor = Theme.divider.cgColor
    }
}
