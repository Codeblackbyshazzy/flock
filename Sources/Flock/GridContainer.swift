import AppKit

class GridContainer: NSView {
    weak var paneManager: PaneManager?
    private let emptyContainer = NSView(frame: .zero)

    override var isFlipped: Bool { true }

    init(paneManager: PaneManager) {
        self.paneManager = paneManager
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = Theme.chrome.cgColor

        setupEmptyState()

        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: Theme.themeDidChange, object: nil)
    }

    @objc private func themeChanged() {
        layer?.backgroundColor = Theme.chrome.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func setupEmptyState() {
        emptyContainer.isHidden = true
        addSubview(emptyContainer)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Theme.Space.xl
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Shortcuts
        let shortcuts = NSStackView()
        shortcuts.orientation = .vertical
        shortcuts.alignment = .leading
        shortcuts.spacing = 10

        func shortcutRow(key: String, label: String) -> NSView {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = Theme.Space.md

            let descLabel = NSTextField(labelWithString: label)
            descLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            descLabel.textColor = Theme.textSecondary

            // Key badge
            let badge = NSView()
            badge.wantsLayer = true
            badge.layer?.backgroundColor = Theme.divider.cgColor
            badge.layer?.cornerRadius = Theme.Space.xs
            badge.translatesAutoresizingMaskIntoConstraints = false

            let badgeLabel = NSTextField(labelWithString: key)
            badgeLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
            badgeLabel.textColor = Theme.textSecondary
            badgeLabel.isBezeled = false
            badgeLabel.drawsBackground = false
            badgeLabel.isEditable = false
            badgeLabel.translatesAutoresizingMaskIntoConstraints = false
            badge.addSubview(badgeLabel)

            NSLayoutConstraint.activate([
                badgeLabel.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
                badgeLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
                badge.widthAnchor.constraint(equalTo: badgeLabel.widthAnchor, constant: Theme.Space.md),
                badge.heightAnchor.constraint(equalToConstant: 22),
            ])

            row.addArrangedSubview(badge)
            row.addArrangedSubview(descLabel)

            NSLayoutConstraint.activate([
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            ])

            return row
        }

        shortcuts.addArrangedSubview(shortcutRow(key: "\u{2318}T", label: "new claude session"))
        shortcuts.addArrangedSubview(shortcutRow(key: "\u{2318}\u{21E7}T", label: "new shell"))
        shortcuts.addArrangedSubview(shortcutRow(key: "\u{2318}K", label: "command palette"))

        stack.addArrangedSubview(shortcuts)

        // Layout presets
        let presetLabel = NSTextField(labelWithString: "Quick Start")
        presetLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        presetLabel.textColor = Theme.textTertiary
        stack.addArrangedSubview(presetLabel)

        let presetStack = NSStackView()
        presetStack.orientation = .horizontal
        presetStack.spacing = Theme.Space.sm

        for preset in LayoutPresets.all {
            let btn = PresetButton(preset: preset, paneManager: paneManager)
            presetStack.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(presetStack)

        emptyContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor),
        ])
    }

    func layoutPanes(animated: Bool = false) {
        guard let mgr = paneManager else { return }

        let empty = mgr.tabNodes.isEmpty
        emptyContainer.isHidden = !empty
        emptyContainer.frame = bounds

        guard !empty else { return }

        if mgr.isMaximized && mgr.activePaneIndex >= 0 {
            let pad = Theme.panePadding
            let maxFrame = NSRect(
                x: pad,
                y: 0,
                width: bounds.width - pad * 2,
                height: bounds.height - pad
            )
            // Hide all panes not in the active tab node
            let activeTabIdx = mgr.activeTabIndex ?? 0
            for (ti, node) in mgr.tabNodes.enumerated() {
                for pane in node.allLeaves {
                    pane.isHidden = (ti != activeTabIdx)
                }
            }
            // Layout the active tab node's splits within the full frame
            if activeTabIdx < mgr.tabNodes.count {
                let paneFrames = mgr.tabNodes[activeTabIdx].layoutFrames(in: maxFrame, gap: Theme.paneGap)
                applyFrames(paneFrames, animated: animated)
            }
        } else {
            // One grid cell per tab node
            let cellFrames = mgr.calculateTabFrames(in: bounds)
            for (ti, node) in mgr.tabNodes.enumerated() {
                guard ti < cellFrames.count else { continue }
                // Each tab node subdivides its grid cell
                let paneFrames = node.layoutFrames(in: cellFrames[ti], gap: Theme.paneGap)
                for (pane, _) in paneFrames { pane.isHidden = false }
                applyFrames(paneFrames, animated: animated)
            }
        }
    }

    private func applyFrames(_ frames: [(FlockPane, NSRect)], animated: Bool) {
        for (pane, frame) in frames {
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = Theme.Anim.slow
                    ctx.timingFunction = Theme.Anim.snappyTimingFunction
                    pane.animator().frame = frame
                }
            } else {
                pane.frame = frame
            }
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutPanes(animated: false)
    }
}

// MARK: - Preset Button for empty state

private class PresetButton: NSView {
    private let preset: LayoutPreset
    private weak var paneManager: PaneManager?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(preset: LayoutPreset, paneManager: PaneManager?) {
        self.preset = preset
        self.paneManager = paneManager
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 110),
            heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        paneManager?.applyPreset(preset)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        if isHovered {
            Theme.hover.setFill()
            path.fill()
        }
        Theme.divider.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        // Draw mini grid preview
        let previewRect = CGRect(x: 12, y: 8, width: bounds.width - 24, height: 22)
        let count = preset.panes.count
        let cols = count <= 2 ? count : 2
        let rows = Int(ceil(Double(count) / Double(cols)))
        let gap: CGFloat = 2
        let cellW = (previewRect.width - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let cellH = (previewRect.height - CGFloat(rows - 1) * gap) / CGFloat(rows)

        var idx = 0
        for r in 0..<rows {
            let itemsInRow = min(cols, count - idx)
            for c in 0..<itemsInRow {
                let x = previewRect.origin.x + CGFloat(c) * (cellW + gap)
                let y = previewRect.origin.y + CGFloat(r) * (cellH + gap)
                let cell = NSBezierPath(roundedRect: CGRect(x: x, y: y, width: cellW, height: cellH),
                                        xRadius: 2, yRadius: 2)
                Theme.borderRest.setFill()
                cell.fill()
                idx += 1
            }
        }

        // Label
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: isHovered ? Theme.textPrimary : Theme.textSecondary,
        ]
        let sz = preset.name.size(withAttributes: attrs)
        preset.name.draw(at: NSPoint(x: bounds.midX - sz.width / 2, y: 34), withAttributes: attrs)
    }
}
