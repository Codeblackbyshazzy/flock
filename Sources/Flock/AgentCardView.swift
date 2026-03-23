import AppKit

// MARK: - AgentCardView

/// A single agent execution card showing task progress.
/// Custom-drawn via `draw(_:)` with a scrolling action timeline.
final class AgentCardView: NSView, NSTextFieldDelegate {

    // MARK: - Properties

    var task: AgentTask? {
        didSet {
            updateTimelineHeight()
            updateMessageFieldVisibility()
            needsDisplay = true
            timelineDocumentView.needsDisplay = true
            updatePulseAnimation()
        }
    }

    private(set) var elapsedTimer: Timer?

    // MARK: - Layout Constants

    private let headerHeight: CGFloat = 40
    private let footerHeight: CGFloat = 28
    private let actionRowHeight: CGFloat = 32
    private let dotSize: CGFloat = 8
    private let badgeWidth: CGFloat = 20
    private let badgeHeight: CGFloat = 16
    private let activeBarWidth: CGFloat = 3
    private let cancelButtonSize: CGFloat = 16
    private let inputHeight: CGFloat = 36

    // MARK: - Subviews

    private let timelineScrollView = NSScrollView()
    private let timelineDocumentView = TimelineDocumentView()
    private let pulseLayer = CALayer()
    private let messageField = NSTextField()
    private let promptLabel = NSTextField(labelWithString: ">")

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
        layer?.cornerRadius = Theme.paneRadius
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.borderRest.cgColor
        applyShadows()

        // Pulse layer for status dot
        pulseLayer.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
        pulseLayer.cornerRadius = dotSize / 2
        pulseLayer.backgroundColor = Theme.accent.cgColor
        layer?.addSublayer(pulseLayer)

        // Timeline scroll view
        timelineScrollView.drawsBackground = false
        timelineScrollView.hasVerticalScroller = true
        timelineScrollView.hasHorizontalScroller = false
        timelineScrollView.autohidesScrollers = true
        timelineScrollView.borderType = .noBorder
        timelineScrollView.scrollerStyle = .overlay

        timelineDocumentView.card = self
        timelineScrollView.documentView = timelineDocumentView
        addSubview(timelineScrollView)

        // Prompt indicator ">"
        promptLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        promptLabel.textColor = Theme.accent
        promptLabel.backgroundColor = .clear
        promptLabel.drawsBackground = false
        promptLabel.isBordered = false
        promptLabel.isEditable = false
        promptLabel.isSelectable = false
        promptLabel.isHidden = true
        addSubview(promptLabel)

        // Message input field
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

        // Elapsed timer -- fires every second
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
            self?.timelineDocumentView.needsDisplay = true
        }

        // Theme change observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: Theme.themeDidChange,
            object: nil
        )
    }

    deinit {
        elapsedTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override var isFlipped: Bool { true }

    // MARK: - Preferred Height

    /// Calculate the right height for a task based on its action count.
    /// Header (40) + timeline rows (count * 32, min 3 rows) + summary row (32 if completed) + input (36 if running) + footer (28).
    static func preferredHeight(for task: AgentTask, minRows: Int = 3) -> CGFloat {
        var rows = max(minRows, task.actions.count)
        // Add a row for the summary/error text on completed tasks
        if (task.status == .done || task.status == .failed),
           (task.resultSummary != nil || task.errorMessage != nil) {
            rows += 1
        }
        let inputH: CGFloat = (task.status == .inProgress) ? 36 : 0
        return 40 + CGFloat(rows) * 32 + inputH + 28
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        let isRunning = task?.status == .inProgress
        let inputH: CGFloat = isRunning ? inputHeight : 0

        let timelineY = headerHeight
        let timelineHeight = max(0, bounds.height - headerHeight - inputH - footerHeight)
        timelineScrollView.frame = NSRect(
            x: 0,
            y: timelineY,
            width: bounds.width,
            height: timelineHeight
        )
        updateTimelineHeight()

        // Message input area (between timeline and footer)
        if isRunning {
            let inputY = timelineY + timelineHeight
            let promptW: CGFloat = 16
            let promptX = Theme.Space.lg
            promptLabel.frame = NSRect(
                x: promptX,
                y: inputY + (inputH - 18) / 2,
                width: promptW,
                height: 18
            )

            let fieldX = promptX + promptW
            messageField.frame = NSRect(
                x: fieldX,
                y: inputY + (inputH - 22) / 2,
                width: bounds.width - fieldX - Theme.Space.lg,
                height: 22
            )
        }

        // Position pulse layer in header
        let dotX = Theme.Space.lg
        let dotY = (headerHeight - dotSize) / 2
        pulseLayer.position = CGPoint(x: dotX + dotSize / 2, y: dotY + dotSize / 2)
    }

    private func updateTimelineHeight() {
        var contentHeight = CGFloat(task?.actions.count ?? 0) * actionRowHeight
        // Add space for the summary row on completed/failed tasks
        if let task = task, (task.status == .done || task.status == .failed),
           (task.resultSummary != nil || task.errorMessage != nil) {
            contentHeight += actionRowHeight
        }
        let scrollViewHeight = timelineScrollView.bounds.height
        let docHeight = max(contentHeight, scrollViewHeight)
        timelineDocumentView.frame = NSRect(
            x: 0,
            y: 0,
            width: timelineScrollView.bounds.width,
            height: docHeight
        )
    }

    // MARK: - Shadows

    private func applyShadows() {
        guard let layer = self.layer else { return }

        // Contact shadow
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = Theme.Shadow.Rest.contact.opacity
        layer.shadowRadius = Theme.Shadow.Rest.contact.radius
        layer.shadowOffset = Theme.Shadow.Rest.contact.offset

        // For ambient shadow we add a sublayer
        let ambient = CALayer()
        ambient.frame = layer.bounds
        ambient.shadowColor = NSColor.black.cgColor
        ambient.shadowOpacity = Theme.Shadow.Rest.ambient.opacity
        ambient.shadowRadius = Theme.Shadow.Rest.ambient.radius
        ambient.shadowOffset = Theme.Shadow.Rest.ambient.offset
        ambient.cornerRadius = Theme.paneRadius
        ambient.backgroundColor = Theme.surface.cgColor
        ambient.zPosition = -1
        ambient.name = "ambientShadow"
        layer.insertSublayer(ambient, at: 0)
    }

    // MARK: - Pulse Animation

    private func updatePulseAnimation() {
        let status = task?.status
        if status == .inProgress && !Theme.prefersReducedMotion {
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
        // Update dot color immediately for completed states
        pulseLayer.backgroundColor = statusDotColor.cgColor
    }

    // MARK: - Message Input

    private func updateMessageFieldVisibility() {
        let isRunning = task?.status == .inProgress
        messageField.isHidden = !isRunning
        promptLabel.isHidden = !isRunning
        needsLayout = true
    }

    @objc private func messageFieldAction(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let task = task else { return }
        AgentRunner.shared.sendMessage(to: task, text: text)
        sender.stringValue = ""
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            messageField.stringValue = ""
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    // MARK: - Theme Change

    @objc private func themeDidChange() {
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.borderColor = Theme.borderRest.cgColor
        pulseLayer.backgroundColor = statusDotColor.cgColor

        // Update ambient shadow sublayer
        if let ambient = layer?.sublayers?.first(where: { $0.name == "ambientShadow" }) {
            ambient.backgroundColor = Theme.surface.cgColor
        }

        // Update message input styling
        messageField.textColor = Theme.textPrimary
        messageField.backgroundColor = Theme.surface
        promptLabel.textColor = Theme.accent

        needsDisplay = true
        timelineDocumentView.needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width

        // -- Header Background --
        ctx.setFillColor(Theme.chrome.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: headerHeight))

        // -- Header divider --
        ctx.setFillColor(Theme.divider.cgColor)
        ctx.fill(CGRect(x: 0, y: headerHeight - 1, width: w, height: 1))

        // -- Status Dot (drawn via pulseLayer, but we update its color) --
        pulseLayer.backgroundColor = statusDotColor.cgColor

        // -- Title --
        let titleX = Theme.Space.lg + dotSize + Theme.Space.sm
        let timerWidth: CGFloat = 48
        let cancelWidth: CGFloat = task?.status == .inProgress ? cancelButtonSize + Theme.Space.sm : 0
        let titleMaxWidth = w - titleX - timerWidth - cancelWidth - Theme.Space.lg

        let titleStr = task?.title ?? "Untitled"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: Theme.textPrimary,
        ]
        let titleAttr = NSAttributedString(string: titleStr, attributes: titleAttrs)
        let titleRect = CGRect(
            x: titleX,
            y: (headerHeight - 18) / 2,
            width: titleMaxWidth,
            height: 18
        )
        titleAttr.draw(with: titleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        // -- Elapsed Timer --
        let elapsed = task?.elapsedTime ?? 0
        let timerStr = formatElapsed(elapsed)
        let timerAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.monoDigit,
            .foregroundColor: Theme.textTertiary,
        ]
        let timerAttr = NSAttributedString(string: timerStr, attributes: timerAttrs)
        let timerSize = timerAttr.size()
        let timerX = w - timerSize.width - cancelWidth - Theme.Space.lg
        let timerRect = CGRect(
            x: timerX,
            y: (headerHeight - timerSize.height) / 2,
            width: timerSize.width,
            height: timerSize.height
        )
        timerAttr.draw(in: timerRect)

        // -- Cancel Button --
        if task?.status == .inProgress {
            let cancelX = w - cancelButtonSize - Theme.Space.lg
            let cancelY = (headerHeight - cancelButtonSize) / 2
            drawCancelButton(in: ctx, rect: CGRect(x: cancelX, y: cancelY, width: cancelButtonSize, height: cancelButtonSize))
        }

        // -- Input divider (above the input area, when visible) --
        if task?.status == .inProgress {
            let inputDividerY = bounds.height - footerHeight - inputHeight
            ctx.setFillColor(Theme.divider.cgColor)
            ctx.fill(CGRect(x: 0, y: inputDividerY, width: w, height: 1))
        }

        // -- Footer Background --
        let footerY = bounds.height - footerHeight
        ctx.setFillColor(Theme.chrome.cgColor)
        ctx.fill(CGRect(x: 0, y: footerY, width: w, height: footerHeight))

        // -- Footer divider --
        ctx.setFillColor(Theme.divider.cgColor)
        ctx.fill(CGRect(x: 0, y: footerY, width: w, height: 1))

        // -- Footer Text --
        let actionCount = task?.actions.count ?? 0
        let footerStr = "\(actionCount) action\(actionCount == 1 ? "" : "s")"
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.caption,
            .foregroundColor: Theme.textTertiary,
        ]
        let footerAttr = NSAttributedString(string: footerStr, attributes: footerAttrs)
        let footerTextRect = CGRect(
            x: Theme.Space.lg,
            y: footerY + (footerHeight - 16) / 2,
            width: w / 2,
            height: 16
        )
        footerAttr.draw(in: footerTextRect)

        // -- Cost (right-aligned in footer, for completed tasks) --
        if let cost = task?.costUsd, (task?.status == .done || task?.status == .failed) {
            let costStr = String(format: "$%.2f", cost)
            let costAttrs: [NSAttributedString.Key: Any] = [
                .font: Theme.Typo.caption,
                .foregroundColor: Theme.textTertiary,
            ]
            let costAttr = NSAttributedString(string: costStr, attributes: costAttrs)
            let costSize = costAttr.size()
            let costRect = CGRect(
                x: w - costSize.width - Theme.Space.lg,
                y: footerY + (footerHeight - 16) / 2,
                width: costSize.width,
                height: 16
            )
            costAttr.draw(in: costRect)
        }
    }

    // MARK: - Cancel Button Drawing

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

    // MARK: - Hit Testing (cancel button)

    override func mouseDown(with event: NSEvent) {
        guard let task = task, task.status == .inProgress else {
            super.mouseDown(with: event)
            return
        }

        let loc = convert(event.locationInWindow, from: nil)
        let cancelX = bounds.width - cancelButtonSize - Theme.Space.lg
        let cancelY = (headerHeight - cancelButtonSize) / 2
        let cancelRect = CGRect(x: cancelX, y: cancelY, width: cancelButtonSize, height: cancelButtonSize)
            .insetBy(dx: -4, dy: -4) // Generous tap target

        if cancelRect.contains(loc) {
            AgentRunner.shared.cancel(task)
        } else {
            super.mouseDown(with: event)
        }
    }

    // MARK: - Helpers

    private var statusDotColor: NSColor {
        guard let task = task else { return Theme.textTertiary }
        switch task.status {
        case .inProgress: return Theme.accent
        case .done:       return NSColor(hex: 0x5B9A6B) // green
        case .failed:     return NSColor(hex: 0xC75450) // red
        case .backlog:    return Theme.textTertiary
        }
    }

    fileprivate func formatElapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    fileprivate func formatRelativeTimestamp(action: AgentTaskAction) -> String {
        guard let startedAt = task?.startedAt else { return "0:00" }
        let offset = action.timestamp.timeIntervalSince(startedAt)
        return formatElapsed(offset)
    }

    fileprivate static func badgeColor(for type: AgentActionType) -> NSColor {
        switch type {
        case .think:  return Theme.textTertiary
        case .read:   return Theme.accent.blended(withFraction: 0.4, of: Theme.textSecondary) ?? Theme.accent
        case .edit:   return Theme.accent
        case .write:  return Theme.accent
        case .bash:   return Theme.textPrimary.withAlphaComponent(0.8)
        case .search: return Theme.textSecondary
        case .agent:  return Theme.accent.withAlphaComponent(0.7)
        case .web:    return Theme.textSecondary
        }
    }
}

// MARK: - TimelineDocumentView

/// The custom-drawn document view inside the scroll view, rendering all action rows.
private final class TimelineDocumentView: NSView {

    weak var card: AgentCardView?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let card = card, let task = card.task else { return }

        let rowHeight: CGFloat = 32
        let w = bounds.width

        for (index, action) in task.actions.enumerated() {
            let rowY = CGFloat(index) * rowHeight
            let rowRect = CGRect(x: 0, y: rowY, width: w, height: rowHeight)

            // Skip rows outside dirty rect
            guard rowRect.intersects(dirtyRect) else { continue }

            drawActionRow(action: action, in: rowRect, width: w, card: card)
        }

        // Draw summary/error row at the bottom for completed/failed tasks
        if task.status == .done || task.status == .failed {
            let summaryText: String?
            let summaryColor: NSColor
            if task.status == .failed {
                summaryText = task.errorMessage ?? "Failed"
                summaryColor = NSColor(hex: 0xC75450)
            } else {
                summaryText = task.resultSummary
                summaryColor = NSColor(hex: 0x5B9A6B)
            }

            if let text = summaryText {
                let summaryY = CGFloat(task.actions.count) * rowHeight
                let summaryRect = CGRect(x: 0, y: summaryY, width: w, height: rowHeight)
                guard summaryRect.intersects(dirtyRect) else { return }

                drawSummaryRow(text: text, color: summaryColor, in: summaryRect, width: w)
            }
        }
    }

    private func drawSummaryRow(text: String, color: NSColor, in rowRect: CGRect, width: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let rowY = rowRect.minY
        let badgeWidth: CGFloat = 20
        let badgeHeight: CGFloat = 16
        let badgeX = Theme.Space.lg
        let lineX = badgeX + badgeWidth / 2

        // Timeline connector line from above
        ctx.setStrokeColor(Theme.divider.cgColor)
        ctx.setLineWidth(1)
        let badgeY = rowY + (rowRect.height - badgeHeight) / 2
        ctx.move(to: CGPoint(x: lineX, y: rowY))
        ctx.addLine(to: CGPoint(x: lineX, y: badgeY))
        ctx.strokePath()

        // Status dot (filled circle, terminal node)
        let dotRadius: CGFloat = 4
        let dotCenterY = badgeY + badgeHeight / 2
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(
            x: lineX - dotRadius,
            y: dotCenterY - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))

        // Summary text
        let titleX = badgeX + badgeWidth + Theme.Space.sm
        let titleMaxWidth = width - titleX - Theme.Space.lg
        let summaryAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
        ]
        let summaryAttr = NSAttributedString(string: text, attributes: summaryAttrs)
        let summaryTextRect = CGRect(
            x: titleX,
            y: rowY + (rowRect.height - 16) / 2,
            width: titleMaxWidth,
            height: 16
        )
        summaryAttr.draw(with: summaryTextRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func drawActionRow(action: AgentTaskAction, in rowRect: CGRect, width: CGFloat, card: AgentCardView) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let rowY = rowRect.minY
        let badgeWidth: CGFloat = 20
        let badgeHeight: CGFloat = 16
        let activeBarWidth: CGFloat = 3

        // -- Active bar (left edge) --
        if action.isActive {
            ctx.setFillColor(Theme.accent.cgColor)
            ctx.fill(CGRect(x: 0, y: rowY, width: activeBarWidth, height: rowRect.height))
        }

        // -- Badge --
        let badgeX = Theme.Space.lg
        let badgeY = rowY + (rowRect.height - badgeHeight) / 2
        let badgeColor = AgentCardView.badgeColor(for: action.type)

        // Badge background (12% opacity fill)
        let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 3, yRadius: 3)
        badgeColor.withAlphaComponent(0.12).setFill()
        badgePath.fill()

        // Badge letter
        let badgeText = action.type.badge
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.badge,
            .foregroundColor: badgeColor,
        ]
        let badgeAttr = NSAttributedString(string: badgeText, attributes: badgeAttrs)
        let badgeTextSize = badgeAttr.size()
        let badgeTextX = badgeX + (badgeWidth - badgeTextSize.width) / 2
        let badgeTextY = badgeY + (badgeHeight - badgeTextSize.height) / 2
        badgeAttr.draw(at: NSPoint(x: badgeTextX, y: badgeTextY))

        // -- Title --
        let titleX = badgeX + badgeWidth + Theme.Space.sm
        let timestampWidth: CGFloat = 40
        let titleMaxWidth = width - titleX - timestampWidth - Theme.Space.lg - Theme.Space.sm

        let titleFont: NSFont = action.isActive
            ? NSFont.systemFont(ofSize: 13, weight: .medium)
            : Theme.Typo.body
        let titleColor: NSColor = action.isActive
            ? Theme.textPrimary
            : Theme.textSecondary

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: titleColor,
        ]
        let titleAttr = NSAttributedString(string: action.title, attributes: titleAttrs)
        let titleRect = CGRect(
            x: titleX,
            y: rowY + (rowRect.height - 18) / 2,
            width: titleMaxWidth,
            height: 18
        )
        titleAttr.draw(with: titleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        // -- Relative Timestamp --
        let tsStr = card.formatRelativeTimestamp(action: action)
        let tsAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.monoDigit,
            .foregroundColor: Theme.textTertiary,
        ]
        let tsAttr = NSAttributedString(string: tsStr, attributes: tsAttrs)
        let tsSize = tsAttr.size()
        let tsX = width - tsSize.width - Theme.Space.lg
        let tsY = rowY + (rowRect.height - tsSize.height) / 2
        tsAttr.draw(at: NSPoint(x: tsX, y: tsY))

        // -- Timeline connector line --
        let lineX = badgeX + badgeWidth / 2
        ctx.setStrokeColor(Theme.divider.cgColor)
        ctx.setLineWidth(1)

        // Line above badge (skip for first row)
        if rowRect.minY > 0 {
            ctx.move(to: CGPoint(x: lineX, y: rowY))
            ctx.addLine(to: CGPoint(x: lineX, y: badgeY))
            ctx.strokePath()
        }

        // Line below badge (skip for last row if not active)
        let isLast = (Int(rowRect.minY / rowRect.height) == (card.task?.actions.count ?? 1) - 1)
        if !isLast {
            ctx.move(to: CGPoint(x: lineX, y: badgeY + badgeHeight))
            ctx.addLine(to: CGPoint(x: lineX, y: rowY + rowRect.height))
            ctx.strokePath()
        }

        // -- Active dot on timeline for active action --
        if action.isActive {
            let dotRadius: CGFloat = 3
            ctx.setFillColor(Theme.accent.cgColor)
            ctx.fillEllipse(in: CGRect(
                x: lineX - dotRadius,
                y: badgeY + badgeHeight + 1,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
        }
    }
}
