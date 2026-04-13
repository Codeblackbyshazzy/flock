import AppKit

// MARK: - AgentSidebarView

/// Left sidebar listing all agents grouped by status with inline task creation.
final class AgentSidebarView: NSView, NSTextFieldDelegate {

    override var isFlipped: Bool { true }

    // MARK: - Constants

    fileprivate let rowHeight: CGFloat = 48
    fileprivate let addBtnHeight: CGFloat = 36
    fileprivate let sectionHeaderHeight: CGFloat = 24
    fileprivate let padH: CGFloat = Theme.Space.md
    private let cardRadius: CGFloat = 6

    // MARK: - State

    var onSelectTask: ((AgentTask) -> Void)?
    var selectedTaskID: UUID?
    fileprivate var hoveredTaskID: UUID?
    fileprivate var hoveredAddArea: Bool = false
    private var trackingArea: NSTrackingArea?

    // Inline add-task
    fileprivate var addField: NSTextField?

    // Scroll
    private let scrollView = NSScrollView()
    fileprivate let documentView = SidebarDocumentView()

    // Timer
    private var elapsedTimer: Timer?

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
        layer?.backgroundColor = Theme.chrome.cgColor

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        documentView.sidebar = self
        scrollView.documentView = documentView
        addSubview(scrollView)

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
        updateDocumentHeight()
        documentView.needsDisplay = true
    }

    @objc private func themeChanged() {
        layer?.backgroundColor = Theme.chrome.cgColor
        documentView.needsDisplay = true
    }

    // MARK: - Timer

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !TaskStore.shared.inProgress.isEmpty {
                self.documentView.needsDisplay = true
            }
        }
    }

    // MARK: - Layout

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        scrollView.frame = bounds
        updateDocumentHeight()
    }

    private func updateDocumentHeight() {
        let height = computeTotalHeight()
        documentView.frame = NSRect(x: 0, y: 0, width: scrollView.bounds.width, height: max(height, scrollView.bounds.height))
    }

    // MARK: - Geometry

    struct SectionInfo {
        let title: String
        let tasks: [AgentTask]
    }

    fileprivate func buildSections() -> [SectionInfo] {
        var result: [SectionInfo] = []
        let running = TaskStore.shared.inProgress
        let queued = TaskStore.shared.backlog
        let finished = TaskStore.shared.tasks.filter { $0.status == .done || $0.status == .failed }

        if !running.isEmpty  { result.append(SectionInfo(title: "RUNNING", tasks: running)) }
        if !queued.isEmpty   { result.append(SectionInfo(title: "QUEUED", tasks: queued)) }
        if !finished.isEmpty { result.append(SectionInfo(title: "DONE", tasks: finished)) }
        return result
    }

    private func computeTotalHeight() -> CGFloat {
        var y: CGFloat = addBtnHeight + Theme.Space.sm
        for section in buildSections() {
            y += sectionHeaderHeight
            y += CGFloat(section.tasks.count) * rowHeight
            y += Theme.Space.sm
        }
        return y + Theme.Space.lg
    }

    fileprivate func rowFrames() -> [(rect: CGRect, task: AgentTask)] {
        let width = documentView.bounds.width
        var y: CGFloat = addBtnHeight + Theme.Space.sm
        var results: [(CGRect, AgentTask)] = []

        for section in buildSections() {
            y += sectionHeaderHeight
            for task in section.tasks {
                results.append((CGRect(x: 0, y: y, width: width, height: rowHeight), task))
                y += rowHeight
            }
            y += Theme.Space.sm
        }
        return results
    }

    fileprivate func addAreaRect() -> CGRect {
        CGRect(x: padH, y: 0, width: documentView.bounds.width - padH * 2, height: addBtnHeight)
    }

    private func taskAtPoint(_ point: NSPoint) -> AgentTask? {
        for (rect, task) in rowFrames() {
            if rect.contains(point) { return task }
        }
        return nil
    }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = documentView.convert(event.locationInWindow, from: nil)
        let oldHovered = hoveredTaskID
        let oldAdd = hoveredAddArea

        hoveredTaskID = taskAtPoint(pt)?.id
        hoveredAddArea = addField == nil && addAreaRect().contains(pt)

        if hoveredTaskID != oldHovered || hoveredAddArea != oldAdd {
            documentView.needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredTaskID = nil
        hoveredAddArea = false
        documentView.needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let pt = documentView.convert(event.locationInWindow, from: nil)

        if addField == nil && addAreaRect().contains(pt) {
            beginAddTask()
            return
        }

        if let task = taskAtPoint(pt) {
            onSelectTask?(task)
            return
        }
    }

    // MARK: - Right-Click Context Menu

    override func rightMouseDown(with event: NSEvent) {
        let pt = documentView.convert(event.locationInWindow, from: nil)
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
            if task.isWaitingForInput {
                let finishItem = NSMenuItem(title: "Finish", action: #selector(ctxFinish(_:)), keyEquivalent: "")
                finishItem.target = self
                finishItem.representedObject = task
                menu.addItem(finishItem)
                menu.addItem(.separator())
            }
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

    @objc private func ctxFinish(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? AgentTask else { return }
        AgentRunner.shared.finish(task)
    }

    @objc private func ctxCancel(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? AgentTask else { return }
        AgentRunner.shared.cancel(task)
    }

    @objc private func ctxRetry(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? AgentTask else { return }
        let newTask = AgentTask(title: task.title)
        TaskStore.shared.remove(task)
        TaskStore.shared.add(newTask)
        AgentRunner.shared.scheduleNext()
    }

    // MARK: - Inline Add Task

    private func beginAddTask() {
        guard addField == nil else { return }

        let rect = addAreaRect().insetBy(dx: 1, dy: 1)
        let field = NSTextField(frame: rect)
        field.stringValue = ""
        field.placeholderString = "Describe a task..."
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
        documentView.addSubview(field)
        field.becomeFirstResponder()
        addField = field
        documentView.needsDisplay = true
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
        documentView.needsDisplay = true
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
        if addField != nil {
            let text = addField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty { cancelAddTask() } else { commitAddTask() }
        }
    }

    // MARK: - String Helpers


    fileprivate func truncateString(_ str: String, font: NSFont, maxWidth: CGFloat) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if str.size(withAttributes: attrs).width <= maxWidth { return str }
        var truncated = str
        while truncated.count > 1 {
            truncated = String(truncated.dropLast())
            if (truncated + "...").size(withAttributes: attrs).width <= maxWidth {
                return truncated + "..."
            }
        }
        return "..."
    }
}

// MARK: - SidebarDocumentView

private final class SidebarDocumentView: NSView {

    weak var sidebar: AgentSidebarView?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let sidebar = sidebar, let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(Theme.chrome.cgColor)
        ctx.fill(bounds)

        let width = bounds.width

        // Add area
        if sidebar.addField == nil {
            drawAddArea(ctx: ctx, rect: sidebar.addAreaRect(), isHovered: sidebar.hoveredAddArea)
        }

        // Sections
        var y: CGFloat = sidebar.addBtnHeight + Theme.Space.sm

        // Empty-state hint when no tasks exist
        if sidebar.buildSections().isEmpty {
            let hint = "Add a task to get started.\n\u{2318}N to create one."
            let hintAttrs: [NSAttributedString.Key: Any] = [
                .font: Theme.Typo.caption,
                .foregroundColor: Theme.textTertiary
            ]
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attrHint = NSMutableAttributedString(string: hint, attributes: hintAttrs)
            attrHint.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: hint.count))
            let hintSize = attrHint.size()
            let hintY = y + 40
            attrHint.draw(in: NSRect(x: 0, y: hintY, width: width, height: hintSize.height + 4))
            return
        }

        for section in sidebar.buildSections() {
            drawSectionHeader(ctx: ctx, title: section.title, count: section.tasks.count, y: y, width: width)
            y += sidebar.sectionHeaderHeight

            for task in section.tasks {
                let rowRect = CGRect(x: 0, y: y, width: width, height: sidebar.rowHeight)
                if rowRect.intersects(dirtyRect) {
                    drawAgentRow(ctx: ctx, task: task, rect: rowRect,
                                 isSelected: task.id == sidebar.selectedTaskID,
                                 isHovered: task.id == sidebar.hoveredTaskID)
                }
                y += sidebar.rowHeight
            }
            y += Theme.Space.sm
        }
    }

    // MARK: - Drawing Helpers

    private func drawAddArea(ctx: CGContext, rect: CGRect, isHovered: Bool) {
        let dashPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        let dashPattern: [CGFloat] = [4, 3]
        dashPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        dashPath.lineWidth = 1.0

        (isHovered ? Theme.textSecondary : Theme.textTertiary).withAlphaComponent(0.5).setStroke()
        dashPath.stroke()

        if isHovered {
            Theme.accentSubtle.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }

        let label = "+ New Task"
        let labelColor = isHovered ? Theme.textSecondary : Theme.textTertiary
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.Typo.caption, .foregroundColor: labelColor]
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }

    private func drawSectionHeader(ctx: CGContext, title: String, count: Int, y: CGFloat, width: CGFloat) {
        let padH = Theme.Space.md
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.sectionHeader, .foregroundColor: Theme.textTertiary
        ]
        let titleSize = title.size(withAttributes: titleAttrs)
        title.draw(at: NSPoint(x: padH, y: y + (24 - titleSize.height) / 2), withAttributes: titleAttrs)

        let countStr = "\(count)"
        let badgeAttrs: [NSAttributedString.Key: Any] = [.font: Theme.Typo.badge, .foregroundColor: Theme.textTertiary]
        let countSize = countStr.size(withAttributes: badgeAttrs)
        let badgeW = countSize.width + 8
        let badgeH = countSize.height + 4
        let badgeX = padH + titleSize.width + Theme.Space.sm
        let badgeY = y + (24 - badgeH) / 2
        let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)

        Theme.divider.setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2, yRadius: badgeH / 2).fill()
        countStr.draw(
            at: NSPoint(x: badgeRect.midX - countSize.width / 2, y: badgeRect.midY - countSize.height / 2),
            withAttributes: badgeAttrs
        )
    }

    private func drawAgentRow(ctx: CGContext, task: AgentTask, rect: CGRect,
                              isSelected: Bool, isHovered: Bool) {
        guard let sidebar = sidebar else { return }
        let padH = sidebar.padH

        // Background
        if isSelected {
            ctx.setFillColor(Theme.accentSubtle.cgColor)
            ctx.fill(rect)
        } else if isHovered {
            ctx.setFillColor(Theme.hover.cgColor)
            ctx.fill(rect)
        }

        // Status dot
        let dotSize: CGFloat = 6
        let dotX = padH
        let dotY = rect.midY - dotSize / 2
        let dotRect = CGRect(x: dotX, y: dotY, width: dotSize, height: dotSize)

        switch task.status {
        case .inProgress:
            let dotColor = task.isWaitingForInput ? Theme.statusGreen : Theme.accent
            dotColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        case .backlog:
            Theme.borderRest.setStroke()
            let path = NSBezierPath(ovalIn: dotRect)
            path.lineWidth = 1.0
            path.stroke()
        case .done:
            Theme.statusGreen.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        case .failed:
            Theme.statusRed.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        // Title
        let textX = dotX + dotSize + Theme.Space.sm
        let maxTitleW = rect.width - textX - padH
        let hasSubtitle = task.status == .inProgress || task.status == .failed || task.costUsd != nil

        let truncTitle = sidebar.truncateString(task.title, font: Theme.Typo.body, maxWidth: maxTitleW)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.body,
            .foregroundColor: isSelected ? Theme.textPrimary : Theme.textSecondary
        ]
        let titleSize = truncTitle.size(withAttributes: titleAttrs)
        let titleY = hasSubtitle ? rect.minY + 10 : rect.midY - titleSize.height / 2
        truncTitle.draw(at: NSPoint(x: textX, y: titleY), withAttributes: titleAttrs)

        // Subtitle
        let subY = titleY + titleSize.height + 2
        if task.status == .inProgress {
            let elapsed = Theme.formatElapsed(task.elapsedTime)
            let subAttrs: [NSAttributedString.Key: Any] = [.font: Theme.Typo.monoDigit, .foregroundColor: Theme.textTertiary]
            elapsed.draw(at: NSPoint(x: textX, y: subY), withAttributes: subAttrs)
        } else if task.status == .failed {
            let errText = sidebar.truncateString(task.errorMessage ?? "Failed", font: Theme.Typo.caption, maxWidth: maxTitleW)
            let subAttrs: [NSAttributedString.Key: Any] = [.font: Theme.Typo.caption, .foregroundColor: Theme.statusRed]
            errText.draw(at: NSPoint(x: textX, y: subY), withAttributes: subAttrs)
        } else if let cost = task.costUsd {
            let costStr = String(format: "$%.2f", cost)
            let subAttrs: [NSAttributedString.Key: Any] = [.font: Theme.Typo.caption, .foregroundColor: Theme.textTertiary]
            costStr.draw(at: NSPoint(x: textX, y: subY), withAttributes: subAttrs)
        }
    }
}
