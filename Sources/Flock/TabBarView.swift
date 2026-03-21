import AppKit

class TabBarView: NSView, NSTextFieldDelegate {
    weak var paneManager: PaneManager?
    private var hoveredTab: Int = -1
    private var hoveredClose: Bool = false
    private var hoveredButton: Int = -1
    private var trackingArea: NSTrackingArea?

    private var editField: NSTextField?
    private var editingIndex: Int = -1

    // Hover animation state: per-tab progress 0→1
    private var tabHoverProgress: [Int: CGFloat] = [:]
    private var hoverTimer: Timer?

    // Active indicator layer (renders above draw content — intentional)
    private let activeIndicator = CALayer()
    private var lastActiveIndex: Int = -1

    private let tabH: CGFloat = 30
    private let tabPadL: CGFloat = 12
    private let tabPadR: CGFloat = 8
    private let closeSize: CGFloat = 18
    private let closeGap: CGFloat = 4
    private let tabGap: CGFloat = 2

    private let brandText = "flock"
    private let brandPadL: CGFloat = Theme.Space.lg
    private let brandGap:  CGFloat = Theme.Space.xl

    override var isFlipped: Bool { true }

    init(paneManager: PaneManager) {
        self.paneManager = paneManager
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.chrome.cgColor

        // Active indicator: thin bar under active tab
        activeIndicator.backgroundColor = Theme.textPrimary.withAlphaComponent(0.15).cgColor
        activeIndicator.cornerRadius = 1
        activeIndicator.isHidden = true
        layer?.addSublayer(activeIndicator)

        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: Theme.themeDidChange, object: nil)
    }

    @objc private func themeChanged() {
        layer?.backgroundColor = Theme.chrome.cgColor
        activeIndicator.backgroundColor = Theme.textPrimary.withAlphaComponent(0.15).cgColor
        needsDisplay = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func update() {
        updateActiveIndicator()
        needsDisplay = true
    }

    // MARK: - Active Indicator

    private func updateActiveIndicator() {
        guard let mgr = paneManager, let ati = mgr.activeTabIndex else {
            activeIndicator.isHidden = true
            return
        }
        let frames = tabFrames()
        guard ati < frames.count else {
            activeIndicator.isHidden = true
            return
        }

        let rect = frames[ati]
        let inset: CGFloat = 8
        let indicatorFrame = CGRect(
            x: rect.origin.x + inset,
            y: rect.maxY,
            width: rect.width - inset * 2,
            height: 2
        )

        activeIndicator.isHidden = false

        if lastActiveIndex != ati && lastActiveIndex >= 0 {
            CATransaction.begin()
            CATransaction.setAnimationDuration(Theme.Anim.normal)
            CATransaction.setAnimationTimingFunction(Theme.Anim.snappyTimingFunction)
            activeIndicator.frame = indicatorFrame
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            activeIndicator.frame = indicatorFrame
            CATransaction.commit()
        }

        lastActiveIndex = ati
    }

    // MARK: - Hover Animation

    private func startHoverAnimation() {
        guard hoverTimer == nil else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickHover()
        }
    }

    private func tickHover() {
        guard let mgr = paneManager else { return }
        var changed = false
        let step: CGFloat = 0.15  // converges in ~6-7 frames ≈ 0.1s

        // Animate toward targets
        for i in 0..<mgr.panes.count {
            let target: CGFloat = (i == hoveredTab) ? 1.0 : 0.0
            let current = tabHoverProgress[i] ?? 0.0
            let diff = target - current

            if abs(diff) < 0.01 {
                if tabHoverProgress[i] != target {
                    tabHoverProgress[i] = target
                    changed = true
                }
            } else {
                tabHoverProgress[i] = current + diff * step
                changed = true
            }
        }

        if changed {
            needsDisplay = true
        } else {
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }

    // Tab drag reorder state
    private struct TabDragState {
        let sourceIndex: Int
        let startX: CGFloat
        var currentX: CGFloat
        var didPassThreshold: Bool = false
    }
    private var dragState: TabDragState?

    // MARK: - Label

    private func tabLabel(for index: Int, node: SplitNode) -> String {
        // Show the focused pane's name if it's in this node, else first leaf
        let leaves = node.allLeaves
        let mgr = paneManager
        let activePaneInNode: TerminalPane? = {
            guard let mgr = mgr, mgr.activePaneIndex >= 0, mgr.activePaneIndex < mgr.panes.count else { return nil }
            let active = mgr.panes[mgr.activePaneIndex]
            return leaves.contains(where: { $0 === active }) ? active : nil
        }()
        let pane = activePaneInNode ?? leaves.first
        let name = pane?.customName ?? pane?.processTitle ?? pane?.type.label ?? "pane"
        let suffix = node.leafCount > 1 ? " (\(node.leafCount))" : ""
        return "\(index + 1)  \(name)\(suffix)"
    }

    // MARK: - Geometry

    private var tabsOriginX: CGFloat {
        let bw = brandText.size(withAttributes: [.font: Theme.Typo.brand, .kern: Theme.Typo.brandKern]).width
        return brandPadL + bw + brandGap
    }

    private func tabFrames() -> [CGRect] {
        guard let mgr = paneManager else { return [] }

        // Calculate natural widths first
        let y = (bounds.height - tabH) / 2
        var naturalWidths: [CGFloat] = []
        for (i, node) in mgr.tabNodes.enumerated() {
            let label = tabLabel(for: i, node: node)
            let font = Theme.Typo.tabActive
            let labelW = label.size(withAttributes: [.font: font]).width
            naturalWidths.append(tabPadL + labelW + closeGap + closeSize + tabPadR)
        }

        // Available width for tabs (between brand and action buttons)
        let btns = buttonFrames()
        let availableWidth = btns.claude.origin.x - tabsOriginX - Theme.Space.sm
        let totalNatural = naturalWidths.reduce(0, +) + CGFloat(max(0, naturalWidths.count - 1)) * tabGap
        let minTabWidth: CGFloat = 80

        // Progressive compression if tabs overflow
        var widths = naturalWidths
        if totalNatural > availableWidth && !widths.isEmpty {
            let totalGaps = CGFloat(max(0, widths.count - 1)) * tabGap
            let maxPerTab = (availableWidth - totalGaps) / CGFloat(widths.count)
            widths = widths.map { max(minTabWidth, min($0, maxPerTab)) }
        }

        var frames: [CGRect] = []
        var x = tabsOriginX
        for w in widths {
            frames.append(CGRect(x: x, y: y, width: w, height: tabH))
            x += w + tabGap
        }
        return frames
    }

    private func closeButtonRect(for tabRect: CGRect) -> CGRect {
        CGRect(
            x: tabRect.maxX - closeSize - tabPadR,
            y: tabRect.midY - closeSize / 2,
            width: closeSize,
            height: closeSize
        )
    }

    private func buttonFrames() -> (claude: CGRect, shell: CGRect) {
        let btnH: CGFloat = 26
        let y = (bounds.height - btnH) / 2
        let shellW = "+ shell".size(withAttributes: [.font: Theme.Typo.button]).width + 20
        let claudeW = "+ claude".size(withAttributes: [.font: Theme.Typo.button]).width + 20
        let shellX = bounds.width - shellW - Theme.Space.lg
        let claudeX = shellX - claudeW - Theme.Space.sm
        return (
            CGRect(x: claudeX, y: y, width: claudeW, height: btnH),
            CGRect(x: shellX, y: y, width: shellW, height: btnH)
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext,
              let mgr = paneManager else { return }

        // Chrome background
        ctx.setFillColor(Theme.chrome.cgColor)
        ctx.fill(bounds)

        // Bottom divider — gradient fade at edges
        drawGradientDivider(ctx: ctx, y: bounds.height - 0.5, width: bounds.width)

        // Brand wordmark
        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.brand,
            .foregroundColor: Theme.textPrimary,
            .kern: Theme.Typo.brandKern,
        ]
        let brandSz = brandText.size(withAttributes: brandAttrs)
        brandText.draw(
            at: NSPoint(x: brandPadL, y: (bounds.height - brandSz.height) / 2),
            withAttributes: brandAttrs
        )

        // Tabs — one per tabNode
        let frames = tabFrames()
        let activeTabIdx = mgr.activeTabIndex
        for (i, node) in mgr.tabNodes.enumerated() {
            guard i < frames.count else { break }
            if i == editingIndex { continue }

            let rect = frames[i]
            let active = (i == activeTabIdx)
            let hovered = (i == hoveredTab)
            let hoverAlpha = tabHoverProgress[i] ?? 0.0

            // Tab background
            let bgPath = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            if active {
                Theme.surface.setFill()
                bgPath.fill()
            } else if hoverAlpha > 0.01 {
                Theme.hover.withAlphaComponent(hoverAlpha).setFill()
                bgPath.fill()
            }

            // Label
            let label = tabLabel(for: i, node: node)
            let textColor = active ? Theme.textPrimary : Theme.textSecondary
            let font = active ? Theme.Typo.tabActive : Theme.Typo.tabRest
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let sz = label.size(withAttributes: attrs)
            label.draw(
                at: NSPoint(x: rect.origin.x + tabPadL, y: rect.midY - sz.height / 2),
                withAttributes: attrs
            )

            // Activity dot — show if any leaf in this node has unread activity
            let leaves = node.allLeaves
            let hasActivity = !active && leaves.contains(where: { $0.hasUnreadActivity }) && Settings.shared.showActivityIndicators
            if hasActivity {
                let dotSize: CGFloat = 6
                let dotX = rect.origin.x + tabPadL + sz.width + 6
                let dotY = rect.midY - dotSize / 2
                let dotRect = CGRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
                NSColor(hex: 0x007AFF).withAlphaComponent(0.7).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }

            // Accent color dot — show first leaf's accent
            if let accent = leaves.first?.accentColor {
                let adotSize: CGFloat = 6
                let adotX = rect.origin.x + 5
                let adotY = rect.midY - adotSize / 2
                accent.setFill()
                NSBezierPath(ovalIn: CGRect(x: adotX, y: adotY, width: adotSize, height: adotSize)).fill()
            }

            // Close button
            if active || hovered {
                let cr = closeButtonRect(for: rect)
                let closeHovered = hovered && hoveredClose

                if closeHovered {
                    let circlePath = NSBezierPath(ovalIn: cr.insetBy(dx: 1, dy: 1))
                    Theme.hover.setFill()
                    circlePath.fill()
                }

                let xColor = closeHovered ? Theme.textPrimary : Theme.textTertiary
                let cx = cr.midX
                let cy = cr.midY
                let s: CGFloat = 3.5
                ctx.setStrokeColor(xColor.cgColor)
                ctx.setLineWidth(1.5)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: cx - s, y: cy - s))
                ctx.addLine(to: CGPoint(x: cx + s, y: cy + s))
                ctx.move(to: CGPoint(x: cx + s, y: cy - s))
                ctx.addLine(to: CGPoint(x: cx - s, y: cy + s))
                ctx.strokePath()
            }
        }

        // Action buttons
        let btns = buttonFrames()
        drawActionButton(ctx: ctx, rect: btns.claude, title: "+ claude", hovered: hoveredButton == 0)
        drawActionButton(ctx: ctx, rect: btns.shell, title: "+ shell", hovered: hoveredButton == 1)
    }

    private func drawGradientDivider(ctx: CGContext, y: CGFloat, width: CGFloat) {
        let fadeLen: CGFloat = width * 0.1
        let color = Theme.divider

        for i in 0..<Int(fadeLen) {
            let alpha = CGFloat(i) / fadeLen
            ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
            ctx.fill(CGRect(x: CGFloat(i), y: y, width: 1, height: 0.5))
        }
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: fadeLen, y: y, width: width - fadeLen * 2, height: 0.5))
        for i in 0..<Int(fadeLen) {
            let alpha = CGFloat(i) / fadeLen
            ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
            ctx.fill(CGRect(x: width - CGFloat(i) - 1, y: y, width: 1, height: 0.5))
        }
    }

    private func drawActionButton(ctx: CGContext, rect: CGRect, title: String, hovered: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        if hovered {
            Theme.hover.setFill()
            path.fill()
        }
        // Subtle border
        Theme.divider.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let color = hovered ? Theme.textPrimary : Theme.textSecondary
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.Typo.button, .foregroundColor: color]
        let sz = title.size(withAttributes: attrs)
        title.draw(
            at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2),
            withAttributes: attrs
        )
    }

    // MARK: - Inline rename

    private func beginRename(at index: Int) {
        guard let mgr = paneManager, index < mgr.tabNodes.count else { return }
        let frames = tabFrames()
        guard index < frames.count else { return }
        commitRename()

        editingIndex = index
        let pane = mgr.panes[index]
        let rect = frames[index].insetBy(dx: 4, dy: 3)

        let field = NSTextField(frame: rect)
        field.stringValue = pane.customName ?? pane.type.label
        field.font = Theme.Typo.tabActive
        field.textColor = Theme.textPrimary
        field.backgroundColor = Theme.surface
        field.isBordered = false
        field.focusRingType = .none
        field.alignment = .center
        field.delegate = self
        field.target = self
        field.action = #selector(renameAction(_:))
        addSubview(field)
        field.selectText(nil)
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: field.stringValue.count)
        editField = field
    }

    @objc private func renameAction(_ sender: NSTextField) { commitRename() }

    private func commitRename() {
        guard let field = editField,
              let mgr = paneManager,
              editingIndex >= 0, editingIndex < mgr.panes.count else {
            cleanupEditor(); return
        }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        mgr.panes[editingIndex].customName = text.isEmpty ? nil : text
        cleanupEditor()
        update()
    }

    private func cleanupEditor() {
        editField?.removeFromSuperview()
        editField = nil
        editingIndex = -1
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitRename() }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        guard let mgr = paneManager else { return }
        let pt = convert(event.locationInWindow, from: nil)

        if event.clickCount == 2 {
            for (i, rect) in tabFrames().enumerated() {
                if rect.contains(pt) { beginRename(at: i); return }
            }
        }

        if editField != nil { commitRename() }

        let frames = tabFrames()
        for (i, rect) in frames.enumerated() {
            let isActiveTab = (i == mgr.activeTabIndex)
            if closeButtonRect(for: rect).contains(pt) && (isActiveTab || i == hoveredTab) {
                // Close entire tab (all panes in this node)
                mgr.closeTab(at: i)
                return
            }
            if rect.contains(pt) {
                // Focus the first leaf in this tab node
                if i < mgr.tabNodes.count, let firstPane = mgr.tabNodes[i].allLeaves.first,
                   let paneIdx = mgr.panes.firstIndex(where: { $0 === firstPane }) {
                    mgr.focusPane(at: paneIdx)
                }
                // Start potential drag
                if !mgr.isMaximized && mgr.tabNodes.count > 1 {
                    dragState = TabDragState(sourceIndex: i, startX: pt.x, currentX: pt.x)
                }
                return
            }
        }

        let btns = buttonFrames()
        if btns.claude.contains(pt) { mgr.addPane(type: .claude) }
        else if btns.shell.contains(pt) { mgr.addPane(type: .shell) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag = dragState else { return }
        let pt = convert(event.locationInWindow, from: nil)
        drag.currentX = pt.x

        if !drag.didPassThreshold && abs(pt.x - drag.startX) > 3 {
            drag.didPassThreshold = true
        }
        dragState = drag

        if drag.didPassThreshold {
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag = dragState, drag.didPassThreshold else {
            dragState = nil
            return
        }

        // Determine drop target
        let frames = tabFrames()
        var targetIndex = drag.sourceIndex
        for (i, rect) in frames.enumerated() {
            if drag.currentX < rect.midX {
                targetIndex = i
                break
            }
            targetIndex = i + 1
        }
        targetIndex = min(targetIndex, (paneManager?.panes.count ?? 1) - 1)
        targetIndex = max(0, targetIndex)

        if targetIndex != drag.sourceIndex {
            paneManager?.reorderPane(from: drag.sourceIndex, to: targetIndex)
        }

        dragState = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        guard paneManager != nil else { return }
        let pt = convert(event.locationInWindow, from: nil)
        for (i, rect) in tabFrames().enumerated() {
            if rect.contains(pt) { showContextMenu(at: i, event: event); return }
        }
    }

    private static let accentPresets: [(name: String, color: NSColor?)] = [
        ("Red", NSColor(hex: 0xFF3B30)),
        ("Orange", NSColor(hex: 0xFF9500)),
        ("Yellow", NSColor(hex: 0xFFCC00)),
        ("Green", NSColor(hex: 0x28CD41)),
        ("Blue", NSColor(hex: 0x007AFF)),
        ("Purple", NSColor(hex: 0xAF52DE)),
        ("None", nil),
    ]

    private func showContextMenu(at index: Int, event: NSEvent) {
        guard let mgr = paneManager, index < mgr.tabNodes.count else { return }
        let menu = NSMenu()

        let rename = NSMenuItem(title: "Rename", action: #selector(ctxRename(_:)), keyEquivalent: "")
        rename.target = self; rename.tag = index
        menu.addItem(rename)

        // Split submenu
        let splitH = NSMenuItem(title: "Split Horizontal", action: #selector(ctxSplitH(_:)), keyEquivalent: "")
        splitH.target = self; splitH.tag = index
        menu.addItem(splitH)

        let splitV = NSMenuItem(title: "Split Vertical", action: #selector(ctxSplitV(_:)), keyEquivalent: "")
        splitV.target = self; splitV.tag = index
        menu.addItem(splitV)

        menu.addItem(.separator())

        // Color submenu
        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for (ci, preset) in Self.accentPresets.enumerated() {
            let item = NSMenuItem(title: preset.name, action: #selector(ctxSetColor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index * 100 + ci  // encode both pane index and color index
            if let c = preset.color {
                let swatch = NSImage(size: NSSize(width: 12, height: 12))
                swatch.lockFocus()
                c.setFill()
                NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 10, height: 10)).fill()
                swatch.unlockFocus()
                item.image = swatch
            }
            colorMenu.addItem(item)
        }
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        menu.addItem(.separator())

        let close = NSMenuItem(title: "Close", action: #selector(ctxClose(_:)), keyEquivalent: "")
        close.target = self; close.tag = index
        menu.addItem(close)

        let closeOthers = NSMenuItem(title: "Close Others", action: #selector(ctxCloseOthers(_:)), keyEquivalent: "")
        closeOthers.target = self; closeOthers.tag = index
        closeOthers.isEnabled = mgr.tabNodes.count > 1
        menu.addItem(closeOthers)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func ctxRename(_ s: NSMenuItem) { beginRename(at: s.tag) }
    @objc private func ctxSplitH(_ s: NSMenuItem) {
        guard let mgr = paneManager, s.tag < mgr.tabNodes.count,
              let firstPane = mgr.tabNodes[s.tag].allLeaves.first,
              let idx = mgr.panes.firstIndex(where: { $0 === firstPane }) else { return }
        mgr.focusPane(at: idx)
        mgr.splitActivePane(direction: .horizontal)
    }
    @objc private func ctxSplitV(_ s: NSMenuItem) {
        guard let mgr = paneManager, s.tag < mgr.tabNodes.count,
              let firstPane = mgr.tabNodes[s.tag].allLeaves.first,
              let idx = mgr.panes.firstIndex(where: { $0 === firstPane }) else { return }
        mgr.focusPane(at: idx)
        mgr.splitActivePane(direction: .vertical)
    }
    @objc private func ctxSetColor(_ s: NSMenuItem) {
        let tabIdx = s.tag / 100
        let colorIndex = s.tag % 100
        guard let mgr = paneManager, tabIdx < mgr.tabNodes.count,
              colorIndex < Self.accentPresets.count else { return }
        // Apply accent to all leaves in this tab
        for pane in mgr.tabNodes[tabIdx].allLeaves {
            pane.accentColor = Self.accentPresets[colorIndex].color
        }
        needsDisplay = true
    }
    @objc private func ctxClose(_ s: NSMenuItem) { paneManager?.closeTab(at: s.tag) }
    @objc private func ctxCloseOthers(_ s: NSMenuItem) {
        guard let mgr = paneManager else { return }
        for i in stride(from: mgr.tabNodes.count - 1, through: 0, by: -1) {
            if i != s.tag { mgr.closeTab(at: i) }
        }
    }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let mgr = paneManager else { return }
        let pt = convert(event.locationInWindow, from: nil)

        var newTab = -1
        var newClose = false
        for (i, rect) in tabFrames().enumerated() {
            if rect.contains(pt) && i < mgr.tabNodes.count {
                newTab = i
                newClose = closeButtonRect(for: rect).contains(pt)
                break
            }
        }

        var newBtn = -1
        let btns = buttonFrames()
        if btns.claude.contains(pt) { newBtn = 0 }
        else if btns.shell.contains(pt) { newBtn = 1 }

        let tabChanged = newTab != hoveredTab
        hoveredTab = newTab
        hoveredClose = newClose
        hoveredButton = newBtn

        if tabChanged {
            startHoverAnimation()
        }

        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        let tabChanged = hoveredTab != -1
        hoveredTab = -1
        hoveredClose = false
        hoveredButton = -1
        if tabChanged { startHoverAnimation() }
        needsDisplay = true
    }
}
