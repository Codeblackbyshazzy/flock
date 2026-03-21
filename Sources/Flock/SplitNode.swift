import AppKit

enum SplitDirection {
    case horizontal  // side by side (left | right)
    case vertical    // stacked (top / bottom)
}

class SplitNode {
    enum Content {
        case leaf(TerminalPane)
        case split(direction: SplitDirection, first: SplitNode, second: SplitNode)
    }

    var content: Content
    var ratio: CGFloat = 0.5  // split position (0.0-1.0)
    weak var parent: SplitNode?

    init(pane: TerminalPane) {
        self.content = .leaf(pane)
    }

    init(direction: SplitDirection, first: SplitNode, second: SplitNode) {
        self.content = .split(direction: direction, first: first, second: second)
        first.parent = self
        second.parent = self
    }

    // Get all leaf panes in this tree
    var allLeaves: [TerminalPane] {
        switch content {
        case .leaf(let pane): return [pane]
        case .split(_, let first, let second): return first.allLeaves + second.allLeaves
        }
    }

    // Find the leaf node containing a specific pane
    func findLeaf(containing pane: TerminalPane) -> SplitNode? {
        switch content {
        case .leaf(let p): return p === pane ? self : nil
        case .split(_, let first, let second):
            return first.findLeaf(containing: pane) ?? second.findLeaf(containing: pane)
        }
    }

    // Calculate frames for all leaves given a bounding rect
    func layoutFrames(in rect: NSRect, gap: CGFloat) -> [(TerminalPane, NSRect)] {
        switch content {
        case .leaf(let pane):
            return [(pane, rect)]
        case .split(let direction, let first, let second):
            let (firstRect, secondRect) = splitRect(rect, direction: direction, ratio: ratio, gap: gap)
            return first.layoutFrames(in: firstRect, gap: gap) + second.layoutFrames(in: secondRect, gap: gap)
        }
    }

    private func splitRect(_ rect: NSRect, direction: SplitDirection, ratio: CGFloat, gap: CGFloat) -> (NSRect, NSRect) {
        switch direction {
        case .horizontal:
            let firstW = (rect.width - gap) * ratio
            let secondW = rect.width - gap - firstW
            let first = NSRect(x: rect.minX, y: rect.minY, width: firstW, height: rect.height)
            let second = NSRect(x: rect.minX + firstW + gap, y: rect.minY, width: secondW, height: rect.height)
            return (first, second)
        case .vertical:
            let firstH = (rect.height - gap) * ratio
            let secondH = rect.height - gap - firstH
            let first = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstH)
            let second = NSRect(x: rect.minX, y: rect.minY + firstH + gap, width: rect.width, height: secondH)
            return (first, second)
        }
    }

    // Split this leaf node into two panes
    func split(direction: SplitDirection, newPane: TerminalPane) {
        guard case .leaf(let existingPane) = content else { return }
        let firstChild = SplitNode(pane: existingPane)
        let secondChild = SplitNode(pane: newPane)
        firstChild.parent = self
        secondChild.parent = self
        self.content = .split(direction: direction, first: firstChild, second: secondChild)
    }

    // Remove a pane from a split, promoting the sibling
    func removePaneAndPromoteSibling(pane: TerminalPane) -> Bool {
        guard case .split(_, let first, let second) = content else { return false }

        // Check if a direct child leaf matches
        if case .leaf(let p) = first.content, p === pane {
            // Promote second child's content to this node
            self.content = second.content
            if case .split(_, let a, let b) = self.content {
                a.parent = self
                b.parent = self
            }
            return true
        }
        if case .leaf(let p) = second.content, p === pane {
            self.content = first.content
            if case .split(_, let a, let b) = self.content {
                a.parent = self
                b.parent = self
            }
            return true
        }

        // Recurse
        return first.removePaneAndPromoteSibling(pane: pane) || second.removePaneAndPromoteSibling(pane: pane)
    }

    // Count of leaves
    var leafCount: Int {
        switch content {
        case .leaf: return 1
        case .split(_, let first, let second): return first.leafCount + second.leafCount
        }
    }
}
