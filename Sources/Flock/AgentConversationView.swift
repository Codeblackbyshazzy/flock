import AppKit

// MARK: - AgentConversationView

/// Center panel showing a scrollable conversation-style feed of the selected agent's actions.
final class AgentConversationView: NSView, NSTextFieldDelegate {

    override var isFlipped: Bool { true }

    // MARK: - Properties

    var task: AgentTask? {
        didSet {
            refresh()
        }
    }

    // MARK: - Layout Constants

    private let headerHeight: CGFloat = 40
    private let footerHeight: CGFloat = 28
    private let inputHeight: CGFloat = 36
    private let dotSize: CGFloat = 8
    private let cancelButtonSize: CGFloat = 16

    // Row heights (variable per action type)
    private let toolRowHeight: CGFloat = 52
    private let thinkRowHeight: CGFloat = 44
    private let minRowHeight: CGFloat = 40

    // MARK: - Subviews

    private let scrollView = NSScrollView()
    private let documentView = ConversationDocumentView()
    private let pulseLayer = CALayer()
    private let messageField = NSTextField()
    private let promptLabel = NSTextField(labelWithString: ">")
    private let emptyLabel = NSTextField(labelWithString: "Select an agent")

    // Timer
    private var elapsedTimer: Timer?
    private var lastActionCount: Int = 0

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

        // Pulse layer for status dot
        pulseLayer.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
        pulseLayer.cornerRadius = dotSize / 2
        pulseLayer.backgroundColor = Theme.textTertiary.cgColor
        layer?.addSublayer(pulseLayer)

        // Scroll view
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        documentView.conversation = self
        scrollView.documentView = documentView
        addSubview(scrollView)

        // Prompt ">"
        promptLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        promptLabel.textColor = Theme.accent
        promptLabel.backgroundColor = .clear
        promptLabel.drawsBackground = false
        promptLabel.isBordered = false
        promptLabel.isEditable = false
        promptLabel.isSelectable = false
        promptLabel.isHidden = true
        addSubview(promptLabel)

        // Message input
        messageField.stringValue = ""
        messageField.placeholderString = "Send a message..."
        messageField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        messageField.textColor = Theme.textPrimary
        messageField.backgroundColor = Theme.surface
        messageField.drawsBackground = true
        messageField.isBordered = false
        messageField.focusRingType = .none
        messageField.delegate = self
        messageField.target = self
        messageField.action = #selector(messageFieldAction(_:))
        messageField.isHidden = true
        addSubview(messageField)

        // Empty label
        emptyLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        emptyLabel.textColor = Theme.textTertiary
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        // Timer
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.task?.status == .inProgress else { return }
            self.needsDisplay = true
            self.documentView.needsDisplay = true
        }

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
        elapsedTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Refresh

    private var showMessageInput: Bool {
        task?.status == .inProgress
    }

    private func refresh() {
        let hasTask = task != nil
        scrollView.isHidden = !hasTask
        messageField.isHidden = !showMessageInput
        promptLabel.isHidden = !showMessageInput
        messageField.placeholderString = (task?.isWaitingForInput ?? false)
            ? "Reply or right-click to finish..."
            : "Send a message..."
        emptyLabel.isHidden = hasTask

        updatePulseAnimation()
        updateDocumentHeight()
        needsDisplay = true
        documentView.needsDisplay = true
        needsLayout = true

        // Auto-scroll if new actions arrived
        if let t = task, t.actions.count > lastActionCount {
            let wasAtBottom = isScrolledToBottom()
            lastActionCount = t.actions.count
            if wasAtBottom {
                DispatchQueue.main.async { [weak self] in
                    self?.scrollToBottom()
                }
            }
        } else {
            lastActionCount = task?.actions.count ?? 0
        }
    }

    @objc private func taskStoreChanged() {
        if task != nil {
            refresh()
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        let inputVisible = showMessageInput
        let inputH: CGFloat = inputVisible ? inputHeight : 0

        let timelineY = headerHeight
        let timelineH = max(0, bounds.height - headerHeight - inputH - footerHeight)
        scrollView.frame = NSRect(x: 0, y: timelineY, width: bounds.width, height: timelineH)
        updateDocumentHeight()

        if inputVisible {
            let inputY = timelineY + timelineH
            let promptW: CGFloat = 16
            let promptX = Theme.Space.lg
            promptLabel.frame = NSRect(x: promptX, y: inputY + (inputH - 18) / 2, width: promptW, height: 18)

            let fieldX = promptX + promptW
            messageField.frame = NSRect(
                x: fieldX,
                y: inputY + (inputH - 22) / 2,
                width: bounds.width - fieldX - Theme.Space.lg,
                height: 22
            )
        }

        // Pulse layer position
        let dotX = Theme.Space.lg
        let dotY = (headerHeight - dotSize) / 2
        pulseLayer.position = CGPoint(x: dotX + dotSize / 2, y: dotY + dotSize / 2)

        // Empty label
        emptyLabel.sizeToFit()
        emptyLabel.frame.origin = NSPoint(
            x: (bounds.width - emptyLabel.frame.width) / 2,
            y: (bounds.height - emptyLabel.frame.height) / 2
        )
    }

    private func updateDocumentHeight() {
        let rowHeights = computeRowHeights()
        let contentH = rowHeights.reduce(0, +) + summaryRowHeight()
        let scrollH = scrollView.bounds.height
        documentView.frame = NSRect(x: 0, y: 0, width: scrollView.bounds.width, height: max(contentH, scrollH))
    }

    // MARK: - Row Heights

    fileprivate func computeRowHeights() -> [CGFloat] {
        guard let actions = task?.actions else { return [] }
        return actions.map { action in
            switch action.type {
            case .think:
                return action.detail != nil ? thinkRowHeight + 16 : thinkRowHeight
            default:
                return action.detail != nil ? toolRowHeight : minRowHeight
            }
        }
    }

    fileprivate func summaryRowHeight() -> CGFloat {
        guard let task = task else { return 0 }
        if (task.status == .done || task.status == .failed),
           (task.resultSummary != nil || task.errorMessage != nil) {
            return minRowHeight
        }
        return 0
    }

    // MARK: - Scroll Helpers

    private func isScrolledToBottom() -> Bool {
        let clipView = scrollView.contentView
        let maxScroll = documentView.bounds.height - clipView.bounds.height
        return clipView.bounds.origin.y >= maxScroll - 20
    }

    private func scrollToBottom() {
        let clipView = scrollView.contentView
        let maxScroll = max(0, documentView.bounds.height - clipView.bounds.height)
        clipView.scroll(to: NSPoint(x: 0, y: maxScroll))
        scrollView.reflectScrolledClipView(clipView)
    }

    // MARK: - Pulse Animation

    private func updatePulseAnimation() {
        let status = task?.status
        let isActivelyRunning = status == .inProgress && !(task?.isWaitingForInput ?? false)
        if isActivelyRunning && !Theme.prefersReducedMotion {
            guard pulseLayer.animation(forKey: "pulse") == nil else { return }
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0
            anim.toValue = 0.3
            anim.duration = 1.0
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulseLayer.add(anim, forKey: "pulse")
        } else {
            pulseLayer.removeAnimation(forKey: "pulse")
            pulseLayer.opacity = 1.0
        }
        pulseLayer.backgroundColor = statusDotColor.cgColor
    }

    // MARK: - Message Input

    @objc private func messageFieldAction(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, task != nil else { return }
        sender.stringValue = ""

        WrenCompressor.shared.compress(text) { [weak self] compressed, _ in
            guard let self, let task = self.task else { return }
            AgentRunner.shared.sendMessage(to: task, text: compressed)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            messageField.stringValue = ""
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    // MARK: - Theme

    @objc private func themeDidChange() {
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.borderColor = Theme.borderRest.cgColor
        pulseLayer.backgroundColor = statusDotColor.cgColor
        messageField.textColor = Theme.textPrimary
        messageField.backgroundColor = Theme.surface
        promptLabel.textColor = Theme.accent
        emptyLabel.textColor = Theme.textTertiary
        needsDisplay = true
        documentView.needsDisplay = true
    }

    // MARK: - Drawing (Header + Footer)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard task != nil else { return }

        let w = bounds.width

        // Header background
        ctx.setFillColor(Theme.chrome.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: headerHeight))

        // Header divider
        ctx.setFillColor(Theme.divider.cgColor)
        ctx.fill(CGRect(x: 0, y: headerHeight - 1, width: w, height: 1))

        // Status dot color
        pulseLayer.backgroundColor = statusDotColor.cgColor

        // Title
        let titleX = Theme.Space.lg + dotSize + Theme.Space.sm
        let timerWidth: CGFloat = 48
        let cancelW: CGFloat = showMessageInput ? cancelButtonSize + Theme.Space.sm : 0
        let titleMaxW = w - titleX - timerWidth - cancelW - Theme.Space.lg

        let titleStr = task?.title ?? "Untitled"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: Theme.textPrimary,
        ]
        let titleAttr = NSAttributedString(string: titleStr, attributes: titleAttrs)
        titleAttr.draw(with: CGRect(x: titleX, y: (headerHeight - 18) / 2, width: titleMaxW, height: 18),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        // Elapsed timer
        let elapsed = task?.elapsedTime ?? 0
        let timerStr = Theme.formatElapsed(elapsed)
        let timerAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.monoDigit, .foregroundColor: Theme.textTertiary,
        ]
        let timerAttr = NSAttributedString(string: timerStr, attributes: timerAttrs)
        let timerSize = timerAttr.size()
        let timerX = w - timerSize.width - cancelW - Theme.Space.lg
        timerAttr.draw(in: CGRect(x: timerX, y: (headerHeight - timerSize.height) / 2,
                                  width: timerSize.width, height: timerSize.height))

        // Cancel button
        if showMessageInput {
            let cancelX = w - cancelButtonSize - Theme.Space.lg
            let cancelY = (headerHeight - cancelButtonSize) / 2
            drawCancelButton(in: ctx, rect: CGRect(x: cancelX, y: cancelY, width: cancelButtonSize, height: cancelButtonSize))
        }

        // Input divider
        if showMessageInput {
            let inputDividerY = bounds.height - footerHeight - inputHeight
            ctx.setFillColor(Theme.divider.cgColor)
            ctx.fill(CGRect(x: 0, y: inputDividerY, width: w, height: 1))
        }

        // Footer
        let footerY = bounds.height - footerHeight
        ctx.setFillColor(Theme.chrome.cgColor)
        ctx.fill(CGRect(x: 0, y: footerY, width: w, height: footerHeight))
        ctx.setFillColor(Theme.divider.cgColor)
        ctx.fill(CGRect(x: 0, y: footerY, width: w, height: 1))

        let actionCount = task?.actions.count ?? 0
        let footerStr = "\(actionCount) action\(actionCount == 1 ? "" : "s")"
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.caption, .foregroundColor: Theme.textTertiary,
        ]
        NSAttributedString(string: footerStr, attributes: footerAttrs)
            .draw(in: CGRect(x: Theme.Space.lg, y: footerY + (footerHeight - 16) / 2, width: w / 2, height: 16))

        if let cost = task?.costUsd, (task?.status == .done || task?.status == .failed) {
            let costStr = String(format: "$%.2f", cost)
            let costAttrs: [NSAttributedString.Key: Any] = [
                .font: Theme.Typo.caption, .foregroundColor: Theme.textTertiary,
            ]
            let costAttr = NSAttributedString(string: costStr, attributes: costAttrs)
            let costSize = costAttr.size()
            costAttr.draw(in: CGRect(x: w - costSize.width - Theme.Space.lg,
                                     y: footerY + (footerHeight - 16) / 2,
                                     width: costSize.width, height: 16))
        }
    }

    // MARK: - Cancel Button

    private func drawCancelButton(in ctx: CGContext, rect: CGRect) {
        let inset: CGFloat = 4
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: rect.minX + inset, y: rect.minY + inset))
        path.line(to: NSPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.move(to: NSPoint(x: rect.maxX - inset, y: rect.minY + inset))
        path.line(to: NSPoint(x: rect.minX + inset, y: rect.maxY - inset))
        Theme.textSecondary.setStroke()
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let task = task, showMessageInput else {
            super.mouseDown(with: event)
            return
        }
        let loc = convert(event.locationInWindow, from: nil)
        let cancelX = bounds.width - cancelButtonSize - Theme.Space.lg
        let cancelY = (headerHeight - cancelButtonSize) / 2
        let cancelRect = CGRect(x: cancelX, y: cancelY, width: cancelButtonSize, height: cancelButtonSize)
            .insetBy(dx: -4, dy: -4)
        if cancelRect.contains(loc) {
            AgentRunner.shared.cancel(task)
        } else {
            super.mouseDown(with: event)
        }
    }

    // MARK: - Helpers

    fileprivate var statusDotColor: NSColor {
        guard let task = task else { return Theme.textTertiary }
        if task.isWaitingForInput { return Theme.statusGreen }
        switch task.status {
        case .inProgress: return Theme.accent
        case .done:       return Theme.statusGreen
        case .failed:     return Theme.statusRed
        case .backlog:    return Theme.textTertiary
        }
    }

    fileprivate func formatRelativeTimestamp(action: AgentTaskAction) -> String {
        guard let startedAt = task?.startedAt else { return "0:00" }
        return Theme.formatElapsed(action.timestamp.timeIntervalSince(startedAt))
    }

}

// MARK: - ConversationDocumentView

private final class ConversationDocumentView: NSView {

    weak var conversation: AgentConversationView?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let conv = conversation, let task = conv.task else { return }

        let w = bounds.width
        let rowHeights = conv.computeRowHeights()
        var y: CGFloat = 0

        for (index, action) in task.actions.enumerated() {
            let rowH = index < rowHeights.count ? rowHeights[index] : 40
            let rowRect = CGRect(x: 0, y: y, width: w, height: rowH)

            if rowRect.intersects(dirtyRect) {
                drawActionRow(action: action, in: rowRect, width: w, conv: conv, isLast: index == task.actions.count - 1)
            }
            y += rowH
        }

        // Summary/error row
        if task.status == .done || task.status == .failed {
            let summaryText: String?
            let summaryColor: NSColor
            if task.status == .failed {
                summaryText = task.errorMessage ?? "Failed"
                summaryColor = Theme.statusRed
            } else {
                summaryText = task.resultSummary
                summaryColor = Theme.statusGreen
            }

            if let text = summaryText {
                let summaryRect = CGRect(x: 0, y: y, width: w, height: 40)
                if summaryRect.intersects(dirtyRect) {
                    drawSummaryRow(text: text, color: summaryColor, in: summaryRect, width: w)
                }
            }
        }
    }

    private func drawActionRow(action: AgentTaskAction, in rowRect: CGRect, width: CGFloat,
                                conv: AgentConversationView, isLast: Bool) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let rowY = rowRect.minY
        let badgeWidth: CGFloat = 20
        let badgeHeight: CGFloat = 16
        let activeBarWidth: CGFloat = 3

        // Active bar
        if action.isActive {
            ctx.setFillColor(Theme.accent.cgColor)
            ctx.fill(CGRect(x: 0, y: rowY, width: activeBarWidth, height: rowRect.height))
        }

        // Badge
        let badgeX = Theme.Space.lg
        let badgeY = rowY + 12
        let badgeColor = action.type.badgeColor

        let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)
        badgeColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 3, yRadius: 3).fill()

        let badgeText = action.type.badge
        let badgeAttrs: [NSAttributedString.Key: Any] = [.font: Theme.Typo.badge, .foregroundColor: badgeColor]
        let badgeAttr = NSAttributedString(string: badgeText, attributes: badgeAttrs)
        let badgeTextSize = badgeAttr.size()
        badgeAttr.draw(at: NSPoint(
            x: badgeX + (badgeWidth - badgeTextSize.width) / 2,
            y: badgeY + (badgeHeight - badgeTextSize.height) / 2
        ))

        // Title
        let titleX = badgeX + badgeWidth + Theme.Space.sm
        let timestampWidth: CGFloat = 40
        let titleMaxW = width - titleX - timestampWidth - Theme.Space.lg - Theme.Space.sm

        let titleFont: NSFont = action.isActive
            ? NSFont.systemFont(ofSize: 13, weight: .medium)
            : Theme.Typo.body
        let titleColor: NSColor = action.isActive ? Theme.textPrimary : Theme.textSecondary

        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor]
        let titleAttr = NSAttributedString(string: action.title, attributes: titleAttrs)
        titleAttr.draw(with: CGRect(x: titleX, y: rowY + 10, width: titleMaxW, height: 18),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        // Detail line (second row)
        if let detail = action.detail, !detail.isEmpty {
            let detailAttrs: [NSAttributedString.Key: Any] = [
                .font: Theme.Typo.monoSmall,
                .foregroundColor: Theme.textTertiary,
            ]
            let detailAttr = NSAttributedString(string: detail, attributes: detailAttrs)
            detailAttr.draw(with: CGRect(x: titleX, y: rowY + 30, width: titleMaxW, height: 16),
                           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }

        // Relative timestamp
        let tsStr = conv.formatRelativeTimestamp(action: action)
        let tsAttrs: [NSAttributedString.Key: Any] = [.font: Theme.Typo.monoDigit, .foregroundColor: Theme.textTertiary]
        let tsAttr = NSAttributedString(string: tsStr, attributes: tsAttrs)
        let tsSize = tsAttr.size()
        tsAttr.draw(at: NSPoint(x: width - tsSize.width - Theme.Space.lg, y: rowY + 12))

        // Timeline connector
        let lineX = badgeX + badgeWidth / 2
        ctx.setStrokeColor(Theme.divider.cgColor)
        ctx.setLineWidth(1)

        if rowRect.minY > 0 {
            ctx.move(to: CGPoint(x: lineX, y: rowY))
            ctx.addLine(to: CGPoint(x: lineX, y: badgeY))
            ctx.strokePath()
        }

        if !isLast || (conv.task?.status == .done || conv.task?.status == .failed) {
            ctx.move(to: CGPoint(x: lineX, y: badgeY + badgeHeight))
            ctx.addLine(to: CGPoint(x: lineX, y: rowY + rowRect.height))
            ctx.strokePath()
        }

        // Active dot
        if action.isActive {
            let dotRadius: CGFloat = 3
            ctx.setFillColor(Theme.accent.cgColor)
            ctx.fillEllipse(in: CGRect(
                x: lineX - dotRadius, y: badgeY + badgeHeight + 1,
                width: dotRadius * 2, height: dotRadius * 2
            ))
        }
    }

    private func drawSummaryRow(text: String, color: NSColor, in rowRect: CGRect, width: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let badgeX = Theme.Space.lg
        let badgeWidth: CGFloat = 20
        let lineX = badgeX + badgeWidth / 2
        let badgeHeight: CGFloat = 16
        let badgeY = rowRect.minY + (rowRect.height - badgeHeight) / 2

        // Connector from above
        ctx.setStrokeColor(Theme.divider.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: lineX, y: rowRect.minY))
        ctx.addLine(to: CGPoint(x: lineX, y: badgeY))
        ctx.strokePath()

        // Terminal dot
        let dotRadius: CGFloat = 4
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(
            x: lineX - dotRadius, y: badgeY + badgeHeight / 2 - dotRadius,
            width: dotRadius * 2, height: dotRadius * 2
        ))

        // Summary text
        let titleX = badgeX + badgeWidth + Theme.Space.sm
        let summaryAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
        ]
        NSAttributedString(string: text, attributes: summaryAttrs)
            .draw(with: CGRect(x: titleX, y: rowRect.minY + (rowRect.height - 16) / 2,
                               width: width - titleX - Theme.Space.lg, height: 16),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
