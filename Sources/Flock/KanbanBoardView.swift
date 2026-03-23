import AppKit

// MARK: - KanbanBoardView

/// Three-column Kanban board for Agent Mode task management.
/// Custom-drawn via `draw(_:)` -- no subviews for cards.
final class KanbanBoardView: NSView, NSTextFieldDelegate {

    override var isFlipped: Bool { true }

    // MARK: - Constants

    private let columnGap: CGFloat = Theme.Space.sm
    private let cardGap: CGFloat = Theme.Space.xs
    private let headerHeight: CGFloat = 32
    private let cardHeight: CGFloat = 52
    private let cardRadius: CGFloat = 6
    private let cardPadH: CGFloat = Theme.Space.md
    private let cardPadV: CGFloat = Theme.Space.sm
    private let addAreaHeight: CGFloat = 36

    // MARK: - Columns

    private enum Column: Int, CaseIterable {
        case backlog = 0
        case inProgress = 1
        case done = 2

        var title: String {
            switch self {
            case .backlog:    return "Backlog"
            case .inProgress: return "In Progress"
            case .done:       return "Done"
            }
        }
    }

    // MARK: - Selection Callback

    /// Called when the user clicks a task card in any column.
    var onSelectTask: ((AgentTask) -> Void)?

    // MARK: - Hover / Interaction State

    private var trackingArea: NSTrackingArea?
    private var hoveredCardID: UUID?
    private var hoveredAddArea: Bool = false

    // Inline add-task field
    private var addField: NSTextField?
    private var isAddingTask: Bool = false

    // Elapsed time refresh timer
    private var elapsedTimer: Timer?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = Theme.chrome.cgColor

        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: TaskStore.didChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged),
            name: Theme.themeDidChange, object: nil
        )

        startElapsedTimer()
    }

    deinit {
        elapsedTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Notifications

    @objc private func storeChanged() {
        needsDisplay = true
    }

    @objc private func themeChanged() {
        layer?.backgroundColor = Theme.chrome.cgColor
        needsDisplay = true
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !TaskStore.shared.inProgress.isEmpty {
                self.needsDisplay = true
            }
        }
    }

    // MARK: - Geometry Helpers

    private func columnWidth() -> CGFloat {
        let totalGaps = columnGap * CGFloat(Column.allCases.count - 1)
        let inset = Theme.Space.lg * 2
        return (bounds.width - inset - totalGaps) / CGFloat(Column.allCases.count)
    }

    private func columnRect(for column: Column) -> CGRect {
        let colW = columnWidth()
        let x = Theme.Space.lg + CGFloat(column.rawValue) * (colW + columnGap)
        return CGRect(x: x, y: Theme.Space.md, width: colW, height: bounds.height - Theme.Space.md * 2)
    }

    private func tasks(for column: Column) -> [AgentTask] {
        switch column {
        case .backlog:    return TaskStore.shared.backlog
        case .inProgress: return TaskStore.shared.inProgress
        case .done:       return TaskStore.shared.tasks.filter { $0.status == .done || $0.status == .failed }
        }
    }

    /// Returns (cardRect, task) pairs for a given column.
    private func cardFrames(for column: Column) -> [(rect: CGRect, task: AgentTask)] {
        let colRect = columnRect(for: column)
        let columnTasks = tasks(for: column)
        var y = colRect.origin.y + headerHeight + Theme.Space.sm
        var results: [(CGRect, AgentTask)] = []

        for task in columnTasks {
            let rect = CGRect(x: colRect.origin.x, y: y, width: colRect.width, height: cardHeight)
            results.append((rect, task))
            y += cardHeight + cardGap
        }
        return results
    }

    private func addAreaRect() -> CGRect {
        let colRect = columnRect(for: .backlog)
        let cards = cardFrames(for: .backlog)
        let y: CGFloat
        if let last = cards.last {
            y = last.rect.maxY + cardGap
        } else {
            y = colRect.origin.y + headerHeight + Theme.Space.sm
        }
        return CGRect(x: colRect.origin.x, y: y, width: colRect.width, height: addAreaHeight)
    }

    /// Returns the task at a given point, if any.
    private func taskAtPoint(_ point: NSPoint) -> AgentTask? {
        for column in Column.allCases {
            for (rect, task) in cardFrames(for: column) {
                if rect.contains(point) { return task }
            }
        }
        return nil
    }

    // MARK: - Intrinsic Size

    override var intrinsicContentSize: NSSize {
        let maxCards = Column.allCases.map { tasks(for: $0).count }.max() ?? 0
        let cardsHeight = CGFloat(maxCards) * (cardHeight + cardGap)
        let total = Theme.Space.md + headerHeight + Theme.Space.sm + cardsHeight + addAreaHeight + Theme.Space.xl
        return NSSize(width: NSView.noIntrinsicMetric, height: max(200, total))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background
        ctx.setFillColor(Theme.chrome.cgColor)
        ctx.fill(bounds)

        for column in Column.allCases {
            drawColumn(ctx: ctx, column: column)
        }

        // Add task area (bottom of Backlog)
        if !isAddingTask {
            drawAddArea(ctx: ctx)
        }
    }

    private func drawColumn(ctx: CGContext, column: Column) {
        let colRect = columnRect(for: column)
        let columnTasks = tasks(for: column)

        // Column header
        drawColumnHeader(ctx: ctx, column: column, count: columnTasks.count, rect: colRect)

        // Cards
        for (rect, task) in cardFrames(for: column) {
            drawCard(ctx: ctx, task: task, rect: rect)
        }
    }

    private func drawColumnHeader(ctx: CGContext, column: Column, count: Int, rect: CGRect) {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.sectionHeader,
            .foregroundColor: Theme.textSecondary
        ]
        let title = column.title.uppercased()
        let titleSize = title.size(withAttributes: titleAttrs)
        let titleY = rect.origin.y + (headerHeight - titleSize.height) / 2
        title.draw(at: NSPoint(x: rect.origin.x + cardPadH, y: titleY), withAttributes: titleAttrs)

        // Count badge
        let countStr = "\(count)"
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.badge,
            .foregroundColor: Theme.textTertiary
        ]
        let countSize = countStr.size(withAttributes: badgeAttrs)
        let badgePadH: CGFloat = 5
        let badgePadV: CGFloat = 2
        let badgeW = countSize.width + badgePadH * 2
        let badgeH = countSize.height + badgePadV * 2
        let badgeX = rect.origin.x + cardPadH + titleSize.width + Theme.Space.sm
        let badgeY = rect.origin.y + (headerHeight - badgeH) / 2

        let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2, yRadius: badgeH / 2)
        Theme.divider.setFill()
        badgePath.fill()

        countStr.draw(
            at: NSPoint(x: badgeRect.midX - countSize.width / 2, y: badgeRect.midY - countSize.height / 2),
            withAttributes: badgeAttrs
        )
    }

    private func drawCard(ctx: CGContext, task: AgentTask, rect: CGRect) {
        let isHovered = task.id == hoveredCardID
        let isFailed = task.status == .failed

        // Card background
        let bgColor = isHovered ? Theme.hover : Theme.surface
        let cardPath = NSBezierPath(roundedRect: rect, xRadius: cardRadius, yRadius: cardRadius)
        bgColor.setFill()
        cardPath.fill()

        // Card border
        let borderColor = isFailed ? NSColor(hex: 0xC75450).withAlphaComponent(0.5) : Theme.borderRest
        borderColor.setStroke()
        cardPath.lineWidth = 0.5
        cardPath.stroke()

        // Title
        let titleFont = Theme.Typo.body
        let titleColor = Theme.textPrimary
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: titleColor
        ]

        // Calculate available width for title
        let textX = rect.origin.x + cardPadH
        let rightMargin: CGFloat = cardPadH + 40 // space for status indicator
        let maxTitleWidth = rect.width - cardPadH - rightMargin

        let truncatedTitle = truncateString(task.title, font: titleFont, maxWidth: maxTitleWidth)
        let titleSize = truncatedTitle.size(withAttributes: titleAttrs)

        // Vertically center title, or shift up if there's a subtitle
        let hasSubtitle = task.status == .inProgress || isFailed
        let titleY: CGFloat
        if hasSubtitle {
            titleY = rect.origin.y + cardPadV + 2
        } else {
            titleY = rect.midY - titleSize.height / 2
        }
        truncatedTitle.draw(at: NSPoint(x: textX, y: titleY), withAttributes: titleAttrs)

        // Subtitle line
        if task.status == .inProgress {
            let elapsed = formatElapsed(task.elapsedTime)
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: Theme.Typo.monoDigit,
                .foregroundColor: Theme.textTertiary
            ]
            let subY = titleY + titleSize.height + 2
            elapsed.draw(at: NSPoint(x: textX, y: subY), withAttributes: subAttrs)
        } else if isFailed {
            let errText = task.errorMessage ?? "Failed"
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: Theme.Typo.caption,
                .foregroundColor: NSColor(hex: 0xC75450)
            ]
            let truncErr = truncateString(errText, font: Theme.Typo.caption, maxWidth: maxTitleWidth)
            let subY = titleY + titleSize.height + 2
            truncErr.draw(at: NSPoint(x: textX, y: subY), withAttributes: subAttrs)
        }

        // Status indicator (right side)
        drawStatusIndicator(ctx: ctx, task: task, cardRect: rect)
    }

    private func drawStatusIndicator(ctx: CGContext, task: AgentTask, cardRect: CGRect) {
        let indicatorX = cardRect.maxX - cardPadH - 16
        let indicatorY = cardRect.midY

        switch task.status {
        case .done:
            // Checkmark
            let checkColor = Theme.accent
            ctx.setStrokeColor(checkColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: indicatorX, y: indicatorY))
            ctx.addLine(to: CGPoint(x: indicatorX + 4, y: indicatorY + 4))
            ctx.addLine(to: CGPoint(x: indicatorX + 10, y: indicatorY - 4))
            ctx.strokePath()

        case .failed:
            // X mark
            let xColor = NSColor(hex: 0xC75450)
            ctx.setStrokeColor(xColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            let s: CGFloat = 4
            ctx.move(to: CGPoint(x: indicatorX + 1, y: indicatorY - s))
            ctx.addLine(to: CGPoint(x: indicatorX + 1 + s * 2, y: indicatorY + s))
            ctx.move(to: CGPoint(x: indicatorX + 1 + s * 2, y: indicatorY - s))
            ctx.addLine(to: CGPoint(x: indicatorX + 1, y: indicatorY + s))
            ctx.strokePath()

        case .inProgress:
            // Pulsing dot
            let dotSize: CGFloat = 6
            let dotRect = CGRect(
                x: indicatorX + 4,
                y: indicatorY - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            Theme.accent.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

        case .backlog:
            // Small circle outline
            let dotSize: CGFloat = 6
            let dotRect = CGRect(
                x: indicatorX + 4,
                y: indicatorY - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            Theme.borderRest.setStroke()
            let circlePath = NSBezierPath(ovalIn: dotRect)
            circlePath.lineWidth = 1.0
            circlePath.stroke()
        }
    }

    private func drawAddArea(ctx: CGContext) {
        let rect = addAreaRect()
        let isHovered = hoveredAddArea

        // Dashed border
        let dashPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: cardRadius, yRadius: cardRadius)
        let dashPattern: [CGFloat] = [4, 3]
        dashPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        dashPath.lineWidth = 1.0

        let borderColor = isHovered ? Theme.textSecondary : Theme.textTertiary
        borderColor.withAlphaComponent(0.5).setStroke()
        dashPath.stroke()

        if isHovered {
            Theme.hover.withAlphaComponent(0.4).setFill()
            NSBezierPath(roundedRect: rect, xRadius: cardRadius, yRadius: cardRadius).fill()
        }

        // "+ Add task" label
        let label = "+ Add task"
        let labelColor = isHovered ? Theme.textSecondary : Theme.textTertiary
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.caption,
            .foregroundColor: labelColor
        ]
        let labelSize = label.size(withAttributes: attrs)
        label.draw(
            at: NSPoint(x: rect.midX - labelSize.width / 2, y: rect.midY - labelSize.height / 2),
            withAttributes: attrs
        )
    }

    // MARK: - String Helpers

    private func truncateString(_ str: String, font: NSFont, maxWidth: CGFloat) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if str.size(withAttributes: attrs).width <= maxWidth {
            return str
        }
        var truncated = str
        while truncated.count > 1 {
            truncated = String(truncated.dropLast())
            let candidate = truncated + "..."
            if candidate.size(withAttributes: attrs).width <= maxWidth {
                return candidate
            }
        }
        return "..."
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let m = total / 60
        let s = total % 60
        if m > 0 {
            return String(format: "%d:%02d", m, s)
        }
        return String(format: "0:%02d", s)
    }

    // MARK: - Inline Add Task

    private func beginAddTask() {
        guard addField == nil else { return }
        isAddingTask = true
        needsDisplay = true

        let rect = addAreaRect().insetBy(dx: 1, dy: 1)
        let field = NSTextField(frame: rect)
        field.stringValue = ""
        field.placeholderString = "Task description..."
        field.font = Theme.Typo.body
        field.textColor = Theme.textPrimary
        field.backgroundColor = Theme.surface
        field.drawsBackground = true
        field.isBordered = false
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = cardRadius
        field.layer?.borderWidth = 1.0
        field.layer?.borderColor = Theme.borderFocus.cgColor
        field.delegate = self
        field.target = self
        field.action = #selector(addFieldAction(_:))
        addSubview(field)
        field.becomeFirstResponder()
        addField = field
    }

    @objc private func addFieldAction(_ sender: NSTextField) {
        commitAddTask()
    }

    private func commitAddTask() {
        guard let field = addField else { cleanupAddField(); return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanupAddField()

        guard !text.isEmpty else { return }

        let task = AgentTask(title: text)
        TaskStore.shared.add(task)
        AgentRunner.shared.scheduleNext()
    }

    private func cancelAddTask() {
        cleanupAddField()
    }

    private func cleanupAddField() {
        addField?.removeFromSuperview()
        addField = nil
        isAddingTask = false
        needsDisplay = true
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelAddTask()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // If the field loses focus without Enter, treat as cancel
        if addField != nil {
            let text = addField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                cancelAddTask()
            } else {
                commitAddTask()
            }
        }
    }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        let oldHoveredCard = hoveredCardID
        let oldHoveredAdd = hoveredAddArea

        hoveredCardID = taskAtPoint(pt)?.id
        hoveredAddArea = !isAddingTask && addAreaRect().contains(pt)

        if hoveredCardID != oldHoveredCard || hoveredAddArea != oldHoveredAdd {
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredCardID = nil
        hoveredAddArea = false
        needsDisplay = true
    }

    // MARK: - Mouse Down

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        // Clicked on add area?
        if !isAddingTask && addAreaRect().contains(pt) {
            beginAddTask()
            return
        }

        // Clicked on a task card?
        if let task = taskAtPoint(pt) {
            onSelectTask?(task)
            return
        }
    }

    // MARK: - Right-Click Context Menu

    override func rightMouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard let task = taskAtPoint(pt) else { return }
        showContextMenu(for: task, event: event)
    }

    private func showContextMenu(for task: AgentTask, event: NSEvent) {
        let menu = NSMenu()

        switch task.status {
        case .backlog:
            let startItem = NSMenuItem(title: "Start Now", action: #selector(ctxStartNow(_:)), keyEquivalent: "")
            startItem.target = self
            startItem.representedObject = task
            menu.addItem(startItem)

            menu.addItem(.separator())

            let deleteItem = NSMenuItem(title: "Delete", action: #selector(ctxDelete(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = task
            menu.addItem(deleteItem)

        case .inProgress:
            let cancelItem = NSMenuItem(title: "Cancel", action: #selector(ctxCancel(_:)), keyEquivalent: "")
            cancelItem.target = self
            cancelItem.representedObject = task
            menu.addItem(cancelItem)

        case .done, .failed:
            let retryItem = NSMenuItem(title: "Retry", action: #selector(ctxRetry(_:)), keyEquivalent: "")
            retryItem.target = self
            retryItem.representedObject = task
            menu.addItem(retryItem)

            menu.addItem(.separator())

            let deleteItem = NSMenuItem(title: "Delete", action: #selector(ctxDelete(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = task
            menu.addItem(deleteItem)
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func ctxStartNow(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? AgentTask else { return }
        AgentRunner.shared.start(task)
    }

    @objc private func ctxDelete(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? AgentTask else { return }
        TaskStore.shared.remove(task)
    }

    @objc private func ctxCancel(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? AgentTask else { return }
        AgentRunner.shared.cancel(task)
    }

    @objc private func ctxRetry(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? AgentTask else { return }
        // Create a fresh task with the same title and add it to backlog
        let newTask = AgentTask(title: task.title)
        TaskStore.shared.remove(task)
        TaskStore.shared.add(newTask)
        AgentRunner.shared.scheduleNext()
    }
}
