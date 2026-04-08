import AppKit

/// Floating overlay panel showing detailed cost & usage stats for a Claude session.
/// Styled to match ChangeLogView / Flock's overlay design language.
final class CostStatsView: NSView {

    var onClose: (() -> Void)?

    let panelWidth: CGFloat = 260
    private let headerHeight: CGFloat = 28
    private let rowHeight: CGFloat = 22
    private let sectionHeaderHeight: CGFloat = 26
    private let padH: CGFloat = 12

    // Data
    private var sessionCost: Double = 0
    private var sessionTokens: Int = 0
    private var sessionInputTokens: Int = 0
    private var sessionOutputTokens: Int = 0
    private var sessionCacheReadTokens: Int = 0
    private var sessionCacheCreateTokens: Int = 0
    private var dailyCost: Double = 0
    private var dailyTokens: Int = 0
    private var limitPercent: Int = 0
    private var limitResetText: String = ""
    private var sessionCount: Int = 0

    // Subviews
    private let headerLabel = NSTextField(labelWithString: "Usage & Costs")
    private let closeButton = NSButton(title: "×", target: nil, action: nil)
    private let contentStack = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Theme.surface.withAlphaComponent(0.95).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.divider.cgColor
        layer?.cornerRadius = 8
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.15
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -4)

        // Header
        headerLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = Theme.textSecondary
        headerLabel.isBezeled = false
        headerLabel.drawsBackground = false
        headerLabel.isEditable = false
        addSubview(headerLabel)

        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        closeButton.contentTintColor = Theme.textTertiary
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)

        // Content stack
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 0
        addSubview(contentStack)
    }

    @objc private func closeTapped() { onClose?() }

    // MARK: - Data Update

    func update(
        sessionCost: Double, sessionTokens: Int,
        inputTokens: Int, outputTokens: Int,
        cacheReadTokens: Int, cacheCreateTokens: Int
    ) {
        self.sessionCost = sessionCost
        self.sessionTokens = sessionTokens
        self.sessionInputTokens = inputTokens
        self.sessionOutputTokens = outputTokens
        self.sessionCacheReadTokens = cacheReadTokens
        self.sessionCacheCreateTokens = cacheCreateTokens

        // Global daily stats from UsageTracker
        let tracker = UsageTracker.shared
        self.dailyCost = tracker.today.costUSD
        self.dailyTokens = tracker.today.totalTokens
        self.sessionCount = tracker.today.sessionCount
        self.limitPercent = tracker.limits.available ? min(max(Int(tracker.limits.fiveHourPercent), 0), 999) : -1
        self.limitResetText = tracker.statusText

        rebuildContent()
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Session section
        addSectionHeader("This Session")
        addRow("Cost", formatCost(sessionCost))
        addRow("Tokens", formatTokens(sessionTokens))
        addRow("  Input", formatTokens(sessionInputTokens), dimLabel: true)
        addRow("  Output", formatTokens(sessionOutputTokens), dimLabel: true)
        if sessionCacheReadTokens > 0 {
            addRow("  Cache read", formatTokens(sessionCacheReadTokens), dimLabel: true)
        }
        if sessionCacheCreateTokens > 0 {
            addRow("  Cache write", formatTokens(sessionCacheCreateTokens), dimLabel: true)
        }

        addSpacer(8)

        // Daily section
        addSectionHeader("Today")
        addRow("Total cost", formatCost(dailyCost))
        addRow("Total tokens", formatTokens(dailyTokens))
        addRow("Sessions", "\(sessionCount)")

        // Rate limits
        if limitPercent >= 0 {
            addSpacer(8)
            addSectionHeader("Rate Limit")
            let pctColor: NSColor = limitPercent >= 80 ? NSColor(hex: 0xC75450) : Theme.textPrimary
            addRow("5h usage", "\(limitPercent)%", valueColor: pctColor)
            if !limitResetText.isEmpty {
                addRow("Status", limitResetText, dimLabel: true)
            }
        }

        resizeSubviews(withOldSize: bounds.size)
    }

    // MARK: - Row builders

    private func addSectionHeader(_ title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = Theme.textTertiary
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: sectionHeaderHeight),
            row.widthAnchor.constraint(equalToConstant: panelWidth - padH * 2),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4),
        ])
        contentStack.addArrangedSubview(row)
    }

    private func addRow(_ label: String, _ value: String, dimLabel: Bool = false, valueColor: NSColor? = nil) {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        labelField.textColor = dimLabel ? Theme.textTertiary : Theme.textSecondary
        labelField.isBezeled = false
        labelField.drawsBackground = false
        labelField.isEditable = false
        labelField.lineBreakMode = .byTruncatingTail
        labelField.translatesAutoresizingMaskIntoConstraints = false

        let valueField = NSTextField(labelWithString: value)
        valueField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueField.textColor = valueColor ?? Theme.textPrimary
        valueField.alignment = .right
        valueField.isBezeled = false
        valueField.drawsBackground = false
        valueField.isEditable = false
        valueField.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(labelField)
        row.addSubview(valueField)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: rowHeight),
            row.widthAnchor.constraint(equalToConstant: panelWidth - padH * 2),
            labelField.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labelField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            labelField.widthAnchor.constraint(lessThanOrEqualToConstant: 120),
            valueField.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            valueField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueField.leadingAnchor.constraint(greaterThanOrEqualTo: labelField.trailingAnchor, constant: 4),
        ])
        contentStack.addArrangedSubview(row)
    }

    private func addSpacer(_ height: CGFloat) {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        spacer.widthAnchor.constraint(equalToConstant: panelWidth - padH * 2).isActive = true
        contentStack.addArrangedSubview(spacer)
    }

    // MARK: - Formatting

    private func formatCost(_ cost: Double) -> String {
        if cost == 0 { return "$0.00" }
        if cost < 0.01 { return "<$0.01" }
        if cost < 10 { return String(format: "$%.2f", cost) }
        return String(format: "$%.0f", cost)
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens < 1000 { return "\(tokens)" }
        if tokens < 1_000_000 { return String(format: "%.1fK", Double(tokens) / 1000) }
        return String(format: "%.1fM", Double(tokens) / 1_000_000)
    }

    // MARK: - Layout

    func idealHeight() -> CGFloat {
        let contentH = contentStack.fittingSize.height
        return headerHeight + contentH + 12  // 12px bottom padding
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        headerLabel.frame = CGRect(x: padH, y: 4, width: panelWidth - 40, height: headerHeight - 4)
        closeButton.frame = CGRect(x: panelWidth - 26, y: 4, width: 20, height: 20)
        contentStack.frame = CGRect(x: padH, y: headerHeight, width: panelWidth - padH * 2, height: bounds.height - headerHeight - 8)
    }

    // MARK: - Theme

    func applyTheme() {
        layer?.backgroundColor = Theme.surface.withAlphaComponent(0.95).cgColor
        layer?.borderColor = Theme.divider.cgColor
        headerLabel.textColor = Theme.textSecondary
        closeButton.contentTintColor = Theme.textTertiary
    }
}
