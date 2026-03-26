import AppKit

// MARK: - AgentDetailView

/// Right panel with Plan and Changes tabs for the selected agent.
final class AgentDetailView: NSView {

    override var isFlipped: Bool { true }

    // MARK: - Properties

    var task: AgentTask? {
        didSet { refresh() }
    }

    // MARK: - Tab State

    private enum DetailTab: Int, CaseIterable {
        case plan = 0
        case changes = 1

        var title: String {
            switch self {
            case .plan:    return "Plan"
            case .changes: return "Changes"
            }
        }
    }

    private var activeTab: DetailTab = .plan
    private var hoveredTab: DetailTab?
    private var trackingArea: NSTrackingArea?

    // MARK: - Layout Constants

    private let tabBarHeight: CGFloat = 32
    private let tabPadH: CGFloat = Theme.Space.md
    private let rowHeight: CGFloat = 28

    // MARK: - Subviews

    private let planScrollView = NSScrollView()
    private let planDocumentView = PlanDocumentView()
    private let changesScrollView = NSScrollView()
    private let changesDocumentView = ChangesDocumentView()
    private let emptyLabel = NSTextField(labelWithString: "Select an agent")

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = Theme.paneRadius
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.borderRest.cgColor

        // Plan scroll view
        planScrollView.hasVerticalScroller = true
        planScrollView.hasHorizontalScroller = false
        planScrollView.scrollerStyle = .overlay
        planScrollView.borderType = .noBorder
        planScrollView.drawsBackground = false
        planScrollView.autohidesScrollers = true
        planDocumentView.panel = self
        planScrollView.documentView = planDocumentView
        addSubview(planScrollView)

        // Changes scroll view
        changesScrollView.hasVerticalScroller = true
        changesScrollView.hasHorizontalScroller = false
        changesScrollView.scrollerStyle = .overlay
        changesScrollView.borderType = .noBorder
        changesScrollView.drawsBackground = false
        changesScrollView.autohidesScrollers = true
        changesDocumentView.panel = self
        changesScrollView.documentView = changesDocumentView
        addSubview(changesScrollView)

        // Empty label
        emptyLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        emptyLabel.textColor = Theme.textTertiary
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        NotificationCenter.default.addObserver(
            self, selector: #selector(themeDidChange),
            name: Theme.themeDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(taskStoreChanged),
            name: TaskStore.didChange, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Refresh

    private func refresh() {
        let hasTask = task != nil
        emptyLabel.isHidden = hasTask

        planScrollView.isHidden = !hasTask || activeTab != .plan
        changesScrollView.isHidden = !hasTask || activeTab != .changes

        updateDocumentHeights()
        needsDisplay = true
        planDocumentView.needsDisplay = true
        changesDocumentView.needsDisplay = true
    }

    @objc private func taskStoreChanged() {
        if task != nil {
            refresh()
        }
    }

    // MARK: - Layout

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)

        let contentY = tabBarHeight
        let contentH = bounds.height - tabBarHeight
        let contentFrame = NSRect(x: 0, y: contentY, width: bounds.width, height: contentH)

        planScrollView.frame = contentFrame
        changesScrollView.frame = contentFrame
        updateDocumentHeights()

        emptyLabel.sizeToFit()
        emptyLabel.frame.origin = NSPoint(
            x: (bounds.width - emptyLabel.frame.width) / 2,
            y: (bounds.height - emptyLabel.frame.height) / 2
        )
    }

    private func updateDocumentHeights() {
        let w = planScrollView.bounds.width
        let scrollH = planScrollView.bounds.height

        // Plan
        let planItems = buildPlanItems()
        let planTitleH: CGFloat = task != nil ? 36 : 0
        let planH = planTitleH + CGFloat(planItems.count) * rowHeight
        planDocumentView.frame = NSRect(x: 0, y: 0, width: w, height: max(planH, scrollH))

        // Changes
        let changedFiles = buildChangedFiles()
        let changesH = CGFloat(changedFiles.count) * rowHeight + Theme.Space.lg
        changesDocumentView.frame = NSRect(x: 0, y: 0, width: w, height: max(changesH, scrollH))
    }

    // MARK: - Data

    fileprivate struct PlanItem {
        enum Status { case done, active, pending }
        let title: String
        let status: Status
    }

    fileprivate func buildPlanItems() -> [PlanItem] {
        guard let actions = task?.actions else { return [] }
        var items: [PlanItem] = []
        var lastThinkGroup = false

        for action in actions {
            if action.type == .think {
                if !lastThinkGroup {
                    let status: PlanItem.Status = action.isActive ? .active : .done
                    items.append(PlanItem(title: "Analyzing...", status: status))
                    lastThinkGroup = true
                } else if action.isActive {
                    // Update last think item to active
                    if !items.isEmpty {
                        items[items.count - 1] = PlanItem(title: "Analyzing...", status: .active)
                    }
                }
            } else {
                lastThinkGroup = false
                let status: PlanItem.Status = action.isActive ? .active : .done
                items.append(PlanItem(title: action.title, status: status))
            }
        }
        return items
    }

    fileprivate struct ChangedFile {
        let path: String
        let type: AgentActionType
    }

    fileprivate func buildChangedFiles() -> [ChangedFile] {
        guard let actions = task?.actions else { return [] }
        var seen: [String: AgentActionType] = [:]
        var order: [String] = []

        for action in actions where action.type == .edit || action.type == .write {
            let path = action.title
            if seen[path] == nil {
                order.append(path)
            }
            seen[path] = action.type
        }

        return order.compactMap { path in
            guard let type = seen[path] else { return nil }
            return ChangedFile(path: path, type: type)
        }
    }

    // MARK: - Drawing (Tab Bar)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let w = bounds.width

        // Tab bar background
        ctx.setFillColor(Theme.chrome.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: tabBarHeight))

        // Tab bar bottom divider
        ctx.setFillColor(Theme.divider.cgColor)
        ctx.fill(CGRect(x: 0, y: tabBarHeight - 1, width: w, height: 1))

        // Draw tabs
        let tabs = DetailTab.allCases
        let tabWidth = (w - tabPadH * 2) / CGFloat(tabs.count)

        for tab in tabs {
            let tabX = tabPadH + CGFloat(tab.rawValue) * tabWidth
            let tabRect = CGRect(x: tabX, y: 0, width: tabWidth, height: tabBarHeight)
            let isActive = tab == activeTab
            let isHovered = tab == hoveredTab && !isActive

            // Hover background
            if isHovered {
                ctx.setFillColor(Theme.hover.cgColor)
                ctx.fill(tabRect)
            }

            // Tab title
            let titleFont = isActive ? Theme.Typo.tabActive : Theme.Typo.tabRest
            let titleColor = isActive ? Theme.textPrimary : Theme.textTertiary
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor]
            let titleAttr = NSAttributedString(string: tab.title, attributes: titleAttrs)
            let titleSize = titleAttr.size()
            titleAttr.draw(at: NSPoint(
                x: tabRect.midX - titleSize.width / 2,
                y: tabRect.midY - titleSize.height / 2
            ))

            // Active underline
            if isActive {
                ctx.setFillColor(Theme.accent.cgColor)
                ctx.fill(CGRect(x: tabRect.minX + Theme.Space.sm, y: tabBarHeight - 2,
                                width: tabRect.width - Theme.Space.sm * 2, height: 2))
            }
        }
    }

    // MARK: - Tab Interaction

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: CGRect(x: 0, y: 0, width: bounds.width, height: tabBarHeight),
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard pt.y < tabBarHeight else {
            if hoveredTab != nil { hoveredTab = nil; needsDisplay = true }
            return
        }

        let tabs = DetailTab.allCases
        let tabWidth = (bounds.width - tabPadH * 2) / CGFloat(tabs.count)
        let index = Int((pt.x - tabPadH) / tabWidth)
        let newHovered = (index >= 0 && index < tabs.count) ? tabs[index] : nil

        if newHovered != hoveredTab {
            hoveredTab = newHovered
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredTab != nil {
            hoveredTab = nil
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard pt.y < tabBarHeight else { return }

        let tabs = DetailTab.allCases
        let tabWidth = (bounds.width - tabPadH * 2) / CGFloat(tabs.count)
        let index = Int((pt.x - tabPadH) / tabWidth)
        guard index >= 0, index < tabs.count else { return }

        let tab = tabs[index]
        if tab != activeTab {
            activeTab = tab
            refresh()
        }
    }

    // MARK: - Theme

    @objc private func themeDidChange() {
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.borderColor = Theme.borderRest.cgColor
        emptyLabel.textColor = Theme.textTertiary
        needsDisplay = true
        planDocumentView.needsDisplay = true
        changesDocumentView.needsDisplay = true
    }
}

// MARK: - PlanDocumentView

private final class PlanDocumentView: NSView {

    weak var panel: AgentDetailView?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let panel = panel, let task = panel.task else { return }

        let w = bounds.width
        let padH = Theme.Space.lg
        var y: CGFloat = 0

        // Task title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: Theme.textPrimary,
        ]
        let titleAttr = NSAttributedString(string: task.title, attributes: titleAttrs)
        titleAttr.draw(with: CGRect(x: padH, y: 10, width: w - padH * 2, height: 20),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        y = 36

        // Plan items
        let items = panel.buildPlanItems()
        let rowH: CGFloat = 28

        for item in items {
            let rowRect = CGRect(x: 0, y: y, width: w, height: rowH)
            guard rowRect.intersects(dirtyRect) else { y += rowH; continue }

            let indicatorX = padH
            let textX = indicatorX + 20

            // Status indicator
            switch item.status {
            case .done:
                let checkAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: Theme.statusGreen,
                ]
                NSAttributedString(string: "\u{2713}", attributes: checkAttrs)
                    .draw(at: NSPoint(x: indicatorX, y: y + 6))

            case .active:
                let dotSize: CGFloat = 6
                let dotY = y + (rowH - dotSize) / 2
                Theme.accent.setFill()
                NSBezierPath(ovalIn: CGRect(x: indicatorX + 2, y: dotY, width: dotSize, height: dotSize)).fill()

            case .pending:
                let dotSize: CGFloat = 6
                let dotY = y + (rowH - dotSize) / 2
                Theme.borderRest.setStroke()
                let path = NSBezierPath(ovalIn: CGRect(x: indicatorX + 2, y: dotY, width: dotSize, height: dotSize))
                path.lineWidth = 1.0
                path.stroke()
            }

            // Item text
            let textColor: NSColor
            let textFont: NSFont
            switch item.status {
            case .done:
                textColor = Theme.textTertiary
                textFont = Theme.Typo.body
            case .active:
                textColor = Theme.textPrimary
                textFont = NSFont.systemFont(ofSize: 13, weight: .medium)
            case .pending:
                textColor = Theme.textSecondary
                textFont = Theme.Typo.body
            }

            let textAttrs: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: textColor]
            let textAttr = NSAttributedString(string: item.title, attributes: textAttrs)
            textAttr.draw(with: CGRect(x: textX, y: y + 5, width: w - textX - padH, height: 18),
                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

            y += rowH
        }

        // Empty state
        if items.isEmpty {
            let emptyAttrs: [NSAttributedString.Key: Any] = [
                .font: Theme.Typo.body, .foregroundColor: Theme.textTertiary,
            ]
            NSAttributedString(string: "No plan yet", attributes: emptyAttrs)
                .draw(at: NSPoint(x: padH, y: y + Theme.Space.lg))
        }
    }
}

// MARK: - ChangesDocumentView

private final class ChangesDocumentView: NSView {

    weak var panel: AgentDetailView?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let panel = panel else { return }

        let w = bounds.width
        let padH = Theme.Space.lg
        let rowH: CGFloat = 28
        let files = panel.buildChangedFiles()

        if files.isEmpty {
            let emptyAttrs: [NSAttributedString.Key: Any] = [
                .font: Theme.Typo.body, .foregroundColor: Theme.textTertiary,
            ]
            NSAttributedString(string: "No changes yet", attributes: emptyAttrs)
                .draw(at: NSPoint(x: padH, y: Theme.Space.lg))
            return
        }

        var y: CGFloat = Theme.Space.sm

        for file in files {
            let rowRect = CGRect(x: 0, y: y, width: w, height: rowH)
            guard rowRect.intersects(dirtyRect) else { y += rowH; continue }

            // Badge
            let badgeX = padH
            let badgeW: CGFloat = 18
            let badgeH: CGFloat = 14
            let badgeY = y + (rowH - badgeH) / 2
            let badgeColor = file.type.badgeColor

            badgeColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: CGRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH),
                        xRadius: 3, yRadius: 3).fill()

            let badgeText = file.type.badge
            let badgeAttrs: [NSAttributedString.Key: Any] = [.font: Theme.Typo.badge, .foregroundColor: badgeColor]
            let badgeAttr = NSAttributedString(string: badgeText, attributes: badgeAttrs)
            let badgeTextSize = badgeAttr.size()
            badgeAttr.draw(at: NSPoint(
                x: badgeX + (badgeW - badgeTextSize.width) / 2,
                y: badgeY + (badgeH - badgeTextSize.height) / 2
            ))

            // File path
            let textX = badgeX + badgeW + Theme.Space.sm
            let pathAttrs: [NSAttributedString.Key: Any] = [
                .font: Theme.Typo.monoSmall, .foregroundColor: Theme.textSecondary,
            ]
            NSAttributedString(string: file.path, attributes: pathAttrs)
                .draw(with: CGRect(x: textX, y: y + 6, width: w - textX - padH, height: 16),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

            y += rowH
        }
    }
}
