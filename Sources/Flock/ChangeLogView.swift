import AppKit

// MARK: - ChangeLogView

/// Compact overlay that shows recent tool calls (edits, writes, commands) inside a terminal pane.
/// Toggle on/off per-pane. Sits in the bottom-right corner of the pane, translucent.
final class ChangeLogView: NSView {

    override var isFlipped: Bool { true }

    // MARK: - Properties

    private(set) var actions: [ClaudeOutputParser.ActionEntry] = []
    private let scrollView = NSScrollView()
    private let listView = NSView()
    private let headerLabel = NSTextField(labelWithString: "Changes")
    private let countLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "\u{2715}", target: nil, action: nil)

    let panelWidth: CGFloat = 240
    private let rowHeight: CGFloat = 22
    private let headerHeight: CGFloat = 28
    private let maxVisibleRows = 12

    var onClose: (() -> Void)?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Theme.surface.withAlphaComponent(0.95).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = Theme.divider.cgColor

        // Shadow
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.15
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -4)

        // Header
        headerLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = Theme.textSecondary
        addSubview(headerLabel)

        countLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        countLabel.textColor = Theme.textTertiary
        addSubview(countLabel)

        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        closeButton.contentTintColor = Theme.textTertiary
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)

        // Scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = listView
        listView.wantsLayer = true
        addSubview(scrollView)

        NotificationCenter.default.addObserver(
            self, selector: #selector(themeDidChange),
            name: Theme.themeDidChange, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    func addAction(_ entry: ClaudeOutputParser.ActionEntry) {
        actions.append(entry)
        countLabel.stringValue = "(\(actions.count))"
        rebuildList()
    }

    func clearActions() {
        actions.removeAll()
        countLabel.stringValue = ""
        rebuildList()
    }

    // MARK: - Layout

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)

        let w = bounds.width
        let padH: CGFloat = 10

        headerLabel.frame = CGRect(x: padH, y: 6, width: 70, height: 16)
        countLabel.frame = CGRect(x: padH + 70, y: 7, width: 40, height: 14)
        closeButton.frame = CGRect(x: w - 26, y: 4, width: 20, height: 20)

        scrollView.frame = CGRect(x: 0, y: headerHeight, width: w, height: bounds.height - headerHeight)
        updateListHeight()
    }

    func idealHeight() -> CGFloat {
        let rows = min(actions.count, maxVisibleRows)
        let listH = CGFloat(max(rows, 1)) * rowHeight + 4
        return headerHeight + listH
    }

    private func updateListHeight() {
        let contentH = CGFloat(actions.count) * rowHeight + 4
        let scrollH = scrollView.bounds.height
        listView.frame = NSRect(x: 0, y: 0, width: scrollView.bounds.width, height: max(contentH, scrollH))
    }

    // MARK: - List Rebuild

    private func rebuildList() {
        listView.subviews.forEach { $0.removeFromSuperview() }
        updateListHeight()

        let w = scrollView.bounds.width
        let padH: CGFloat = 10
        var y: CGFloat = 2

        for action in actions {
            let row = NSView(frame: NSRect(x: 0, y: y, width: w, height: rowHeight))

            // Badge
            let badgeColor = action.type.badgeColor
            let badgeView = NSView(frame: NSRect(x: padH, y: 4, width: 16, height: 14))
            badgeView.wantsLayer = true
            badgeView.layer?.backgroundColor = badgeColor.withAlphaComponent(0.12).cgColor
            badgeView.layer?.cornerRadius = 3
            row.addSubview(badgeView)

            let badge = NSTextField(labelWithString: action.type.badge)
            badge.font = Theme.Typo.badge
            badge.textColor = badgeColor
            badge.alignment = .center
            badge.frame = NSRect(x: padH, y: 3, width: 16, height: 14)
            row.addSubview(badge)

            // Target path (truncated)
            let target = NSTextField(labelWithString: action.target)
            target.font = Theme.Typo.monoSmall
            target.textColor = Theme.textSecondary
            target.lineBreakMode = .byTruncatingMiddle
            target.frame = NSRect(x: padH + 22, y: 3, width: w - padH * 2 - 22, height: 16)
            row.addSubview(target)

            listView.addSubview(row)
            y += rowHeight
        }

        // Auto-scroll to bottom
        if actions.count > maxVisibleRows {
            let bottomPoint = NSPoint(x: 0, y: listView.frame.height - scrollView.bounds.height)
            scrollView.documentView?.scroll(bottomPoint)
        }

        // Resize parent frame to fit
        if let superview = superview {
            let h = idealHeight()
            let newY = superview.bounds.height - h - 8
            frame = NSRect(x: frame.origin.x, y: newY, width: panelWidth, height: h)
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        onClose?()
    }

    // MARK: - Theme

    @objc private func themeDidChange() {
        layer?.backgroundColor = Theme.surface.withAlphaComponent(0.95).cgColor
        layer?.borderColor = Theme.divider.cgColor
        headerLabel.textColor = Theme.textSecondary
        countLabel.textColor = Theme.textTertiary
        closeButton.contentTintColor = Theme.textTertiary
        rebuildList()
    }
}
