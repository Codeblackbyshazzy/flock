import AppKit

enum PaneType {
    case claude, shell
    var label: String {
        switch self {
        case .claude: return "claude"
        case .shell:  return "shell"
        }
    }
}

enum Direction { case left, right, up, down }

class PaneManager {
    private(set) var panes: [TerminalPane] = []
    private(set) var activePaneIndex: Int = -1
    private(set) var isMaximized: Bool = false

    weak var tabBar: TabBarView?
    weak var gridContainer: GridContainer?
    weak var statusBar: StatusBarView?

    // Find bar
    private var findBar: FindBarView?

    // Broadcast mode
    private(set) var isBroadcasting: Bool = false

    // Split pane tree roots (one per tab)
    private(set) var tabNodes: [SplitNode] = []

    // MARK: - Pane lifecycle

    func addPane(type: PaneType, workingDirectory: String? = nil) {
        let pane = TerminalPane(type: type, manager: self, workingDirectory: workingDirectory)
        panes.append(pane)
        tabNodes.append(SplitNode(pane: pane))
        gridContainer?.addSubview(pane)
        focusPane(at: panes.count - 1)
        layoutAndUpdate(animated: true)
        pane.animateEntrance()
    }

    func closePane(at index: Int) {
        guard index >= 0, index < panes.count else { return }
        closeFindBar()
        let pane = panes[index]

        // Update tabNodes: remove the pane from its split tree or remove the whole tab
        if let tabIdx = tabNodes.firstIndex(where: { $0.findLeaf(containing: pane) != nil }) {
            if tabNodes[tabIdx].leafCount <= 1 {
                // Only leaf in this tab — remove the entire tab node
                tabBar?.animateTabClose(at: tabIdx)
                tabNodes.remove(at: tabIdx)
            } else {
                // Part of a split — remove pane and promote sibling
                _ = tabNodes[tabIdx].removePaneAndPromoteSibling(pane: pane)
            }
        }

        // Rebuild flat panes array from the updated tree
        rebuildPanesFromNodes()

        if panes.isEmpty {
            activePaneIndex = -1
        } else {
            activePaneIndex = min(max(0, index <= activePaneIndex ? activePaneIndex - 1 : activePaneIndex), panes.count - 1)
            panes[activePaneIndex].isFocused = true
            panes[activePaneIndex].terminalView.window?.makeFirstResponder(panes[activePaneIndex].terminalView)
        }
        isMaximized = false

        // Animate exit, then remove + reflow
        pane.animateExit { [weak pane] in
            pane?.shutdown()
            pane?.removeFromSuperview()
        }

        layoutAndUpdate(animated: true)
    }

    func closeActivePane() {
        closePane(at: activePaneIndex)
    }

    func closeTab(at tabIndex: Int) {
        guard tabIndex >= 0, tabIndex < tabNodes.count else { return }
        tabBar?.animateTabClose(at: tabIndex)
        let leaves = tabNodes[tabIndex].allLeaves
        tabNodes.remove(at: tabIndex)
        for pane in leaves {
            pane.animateExit { [weak pane] in
                pane?.shutdown()
                pane?.removeFromSuperview()
            }
        }
        rebuildPanesFromNodes()
        if panes.isEmpty {
            activePaneIndex = -1
        } else {
            activePaneIndex = min(activePaneIndex, panes.count - 1)
            panes[activePaneIndex].isFocused = true
            panes[activePaneIndex].terminalView.window?.makeFirstResponder(panes[activePaneIndex].terminalView)
        }
        isMaximized = false
        layoutAndUpdate(animated: true)
    }

    func focusPane(at index: Int) {
        guard index >= 0, index < panes.count else { return }
        if activePaneIndex >= 0, activePaneIndex < panes.count {
            panes[activePaneIndex].isFocused = false
        }
        activePaneIndex = index
        panes[index].isFocused = true
        panes[index].terminalView.window?.makeFirstResponder(panes[index].terminalView)
        closeFindBar()
        tabBar?.update()
        statusBar?.update()
    }

    func toggleMaximize() {
        guard !panes.isEmpty else { return }
        isMaximized.toggle()

        if isMaximized {
            for (i, pane) in panes.enumerated() {
                if i != activePaneIndex {
                    pane.animateFadeOut()
                }
            }
            gridContainer?.layoutPanes(animated: true)
        } else {
            gridContainer?.layoutPanes(animated: true)
            for (i, pane) in panes.enumerated() {
                if i != activePaneIndex {
                    pane.isHidden = false
                    pane.animateFadeIn()
                }
            }
        }
        tabBar?.update()
        statusBar?.update()
    }

    // Tab index for a given pane
    func tabIndex(for pane: TerminalPane) -> Int? {
        tabNodes.firstIndex(where: { $0.findLeaf(containing: pane) != nil })
    }

    var activeTabIndex: Int? {
        guard activePaneIndex >= 0, activePaneIndex < panes.count else { return nil }
        return tabIndex(for: panes[activePaneIndex])
    }

    // MARK: - Broadcast

    func toggleBroadcast() {
        isBroadcasting.toggle()
        statusBar?.update()

        // Animate border color changes (constant 1pt width -- no width animation)
        CATransaction.begin()
        CATransaction.setAnimationDuration(Theme.Anim.normal)
        CATransaction.setAnimationTimingFunction(Theme.Anim.snappyTimingFunction)

        for pane in panes {
            if isBroadcasting {
                pane.layer?.borderColor = NSColor(hex: 0xFF9500).withAlphaComponent(0.6).cgColor
            } else {
                pane.layer?.borderColor = (pane.isFocused ? Theme.borderFocus : Theme.borderRest).cgColor
            }
        }

        CATransaction.commit()

        // On broadcast enable, pulse the border color briefly
        if isBroadcasting {
            for pane in panes {
                let pulse = CABasicAnimation(keyPath: "borderColor")
                pulse.fromValue = NSColor(hex: 0xFF9500).withAlphaComponent(0.6).cgColor
                pulse.toValue = NSColor(hex: 0xFF9500).withAlphaComponent(0.9).cgColor
                pulse.duration = 0.3
                pulse.autoreverses = true
                pulse.timingFunction = Theme.Anim.snappyTimingFunction
                pane.layer?.add(pulse, forKey: "broadcastPulse")
            }
        }
    }

    // MARK: - Split Panes

    func splitActivePane(direction: SplitDirection) {
        guard activePaneIndex >= 0, activePaneIndex < panes.count else { return }
        let activePane = panes[activePaneIndex]

        // Find the tab node containing this pane
        guard let nodeIndex = tabNodes.firstIndex(where: { $0.findLeaf(containing: activePane) != nil }),
              let leafNode = tabNodes[nodeIndex].findLeaf(containing: activePane) else { return }

        // Create new pane
        let newPane = TerminalPane(type: .shell, manager: self)
        gridContainer?.addSubview(newPane)

        // Split the leaf
        leafNode.split(direction: direction, newPane: newPane)

        // Update flat panes array
        rebuildPanesFromNodes()
        focusPane(at: panes.firstIndex(where: { $0 === newPane }) ?? activePaneIndex)
        layoutAndUpdate(animated: true)
        newPane.animateEntrance()
    }

    private func rebuildPanesFromNodes() {
        panes = tabNodes.flatMap { $0.allLeaves }
    }

    // MARK: - Session Save/Restore

    func saveSession() {
        let sessionPanes = panes.map { pane in
            (type: pane.type == .claude ? "claude" : "shell",
             directory: pane.currentDirectory,
             name: pane.customName)
        }
        SessionRestore.save(panes: sessionPanes, activeIndex: activePaneIndex)
    }

    func restoreSession() {
        guard let layout = SessionRestore.restore() else { return }
        for sp in layout.panes {
            let type: PaneType = sp.type == "shell" ? .shell : .claude
            let pane = TerminalPane(type: type, manager: self, workingDirectory: sp.workingDirectory)
            pane.customName = sp.customName
            panes.append(pane)
            tabNodes.append(SplitNode(pane: pane))
            gridContainer?.addSubview(pane)
        }
        if layout.activeIndex >= 0, layout.activeIndex < panes.count {
            focusPane(at: layout.activeIndex)
        } else if !panes.isEmpty {
            focusPane(at: 0)
        }
        layoutAndUpdate(animated: false)
    }

    // MARK: - Layout Presets

    func applyPreset(_ preset: LayoutPreset) {
        // Close all existing panes
        for i in stride(from: panes.count - 1, through: 0, by: -1) {
            let pane = panes.remove(at: i)
            pane.shutdown()
            pane.removeFromSuperview()
        }
        tabNodes.removeAll()
        activePaneIndex = -1
        isMaximized = false

        // Create new panes
        for type in preset.panes {
            addPane(type: type)
        }
    }

    // MARK: - Tab Reorder

    func reorderPane(from sourceIndex: Int, to targetIndex: Int) {
        guard sourceIndex != targetIndex,
              sourceIndex >= 0, sourceIndex < panes.count,
              targetIndex >= 0, targetIndex < panes.count else { return }

        let pane = panes.remove(at: sourceIndex)
        panes.insert(pane, at: targetIndex)

        // Follow the active pane
        if activePaneIndex == sourceIndex {
            activePaneIndex = targetIndex
        } else if sourceIndex < activePaneIndex && targetIndex >= activePaneIndex {
            activePaneIndex -= 1
        } else if sourceIndex > activePaneIndex && targetIndex <= activePaneIndex {
            activePaneIndex += 1
        }

        layoutAndUpdate(animated: true)
    }

    // MARK: - Find

    func showFindBar() {
        guard activePaneIndex >= 0, activePaneIndex < panes.count else { return }
        if findBar != nil { closeFindBar() }

        let pane = panes[activePaneIndex]
        let bar = FindBarView(terminalView: pane.terminalView)
        pane.addSubview(bar)
        // FindBarView positions itself in viewDidMoveToSuperview (right-aligned pill)
        bar.show()
        findBar = bar
    }

    func closeFindBar() {
        findBar?.dismiss()
        findBar = nil
    }

    func findNext() {
        findBar?.findNext(nil)
    }

    func findPrevious() {
        findBar?.findPrevious(nil)
    }

    // MARK: - Navigation

    func navigateDirection(_ dir: Direction) {
        guard panes.count > 1, activePaneIndex >= 0 else { return }
        let dims = gridDimensions(for: panes.count)
        let cols = dims.cols
        let row = activePaneIndex / cols
        let col = activePaneIndex % cols

        var newIndex = activePaneIndex
        switch dir {
        case .left:  newIndex = row * cols + max(0, col - 1)
        case .right: newIndex = min(panes.count - 1, row * cols + min(cols - 1, col + 1))
        case .up:    newIndex = max(0, (row - 1) * cols + col)
        case .down:
            let below = (row + 1) * cols + col
            newIndex = below < panes.count ? below : activePaneIndex
        }
        if newIndex != activePaneIndex { focusPane(at: newIndex) }
    }

    func handleClick(event: NSEvent) {
        for (i, pane) in panes.enumerated() {
            let pt = pane.convert(event.locationInWindow, from: nil)
            if pane.bounds.contains(pt) {
                if i != activePaneIndex { focusPane(at: i) }
                return
            }
        }
    }

    // MARK: - Grid math

    func gridDimensions(for count: Int) -> (cols: Int, rows: Int) {
        switch count {
        case 0:      return (0, 0)
        case 1:      return (1, 1)
        case 2:      return (2, 1)
        case 3, 4:   return (2, 2)
        case 5, 6:   return (3, 2)
        default:     return (3, 3)
        }
    }

    // Grid frames for tab nodes (one rect per tab)
    func calculateTabFrames(in bounds: NSRect) -> [NSRect] {
        let count = tabNodes.count
        guard count > 0 else { return [] }

        let pad = Theme.panePadding
        let gap = Theme.paneGap
        let area = NSRect(
            x: bounds.origin.x + pad,
            y: bounds.origin.y + pad,
            width: bounds.width - pad * 2,
            height: bounds.height - pad * 2
        )

        let (cols, _) = gridDimensions(for: count)
        let totalRows = Int(ceil(Double(count) / Double(cols)))

        let totalVGap = CGFloat(totalRows - 1) * gap
        let cellH = (area.height - totalVGap) / CGFloat(totalRows)

        var frames: [NSRect] = []
        var idx = 0
        for row in 0..<totalRows {
            let itemsInRow = min(cols, count - idx)
            let totalHGap = CGFloat(itemsInRow - 1) * gap
            let cellW = (area.width - totalHGap) / CGFloat(itemsInRow)
            for col in 0..<itemsInRow {
                let x = area.origin.x + CGFloat(col) * (cellW + gap)
                let y = area.origin.y + CGFloat(row) * (cellH + gap)
                frames.append(NSRect(x: x, y: y, width: cellW, height: cellH))
                idx += 1
            }
        }
        return frames
    }

    func layoutAndUpdate(animated: Bool = false) {
        gridContainer?.layoutPanes(animated: animated)
        tabBar?.update()
        statusBar?.update()
    }
}
