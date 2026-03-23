import AppKit

// MARK: - MemorySidebar

/// Slide-in overlay sidebar for browsing and managing memories.
/// Sits on the right edge of the window, overlaying content.
final class MemorySidebar {

    private var backdropView: MemoryBackdropView?
    private var sidebarView: MemorySidebarView?
    private(set) var isVisible = false

    func toggle(in window: NSWindow) {
        if isVisible { dismiss() } else { show(in: window) }
    }

    func show(in window: NSWindow) {
        guard !isVisible, let contentView = window.contentView else { return }
        isVisible = true

        // Backdrop
        let backdrop = MemoryBackdropView(frame: contentView.bounds)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.onClickOutside = { [weak self] in self?.dismiss() }
        contentView.addSubview(backdrop)
        self.backdropView = backdrop

        // Sidebar (right edge)
        let sidebarWidth: CGFloat = 340
        let sidebar = MemorySidebarView(
            frame: NSRect(x: contentView.bounds.width, y: 0,
                          width: sidebarWidth, height: contentView.bounds.height)
        )
        sidebar.autoresizingMask = [.minXMargin, .height]
        sidebar.onDismiss = { [weak self] in self?.dismiss() }
        contentView.addSubview(sidebar)
        self.sidebarView = sidebar

        // Animate in
        backdrop.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = Theme.Anim.snappyTimingFunction
            backdrop.animator().alphaValue = 1
            sidebar.animator().frame = NSRect(
                x: contentView.bounds.width - sidebarWidth, y: 0,
                width: sidebarWidth, height: contentView.bounds.height
            )
        }
    }

    func dismiss() {
        guard isVisible else { return }
        isVisible = false

        let backdrop = self.backdropView
        let sidebar = self.sidebarView

        guard let contentView = sidebar?.superview else {
            backdrop?.removeFromSuperview()
            sidebar?.removeFromSuperview()
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = Theme.Anim.snappyTimingFunction
            backdrop?.animator().alphaValue = 0
            sidebar?.animator().frame = NSRect(
                x: contentView.bounds.width, y: 0,
                width: sidebar?.bounds.width ?? 340,
                height: contentView.bounds.height
            )
        }, completionHandler: {
            backdrop?.removeFromSuperview()
            sidebar?.removeFromSuperview()
        })

        self.backdropView = nil
        self.sidebarView = nil
    }
}

// MARK: - Backdrop

private class MemoryBackdropView: NSView {
    var onClickOutside: (() -> Void)?
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.1).setFill()
        dirtyRect.fill()
    }

    override func mouseDown(with event: NSEvent) {
        onClickOutside?()
    }
}

// MARK: - Sidebar View

private class MemorySidebarView: NSView {

    var onDismiss: (() -> Void)?

    private let headerView = NSView()
    private let titleLabel = NSTextField(labelWithString: "Memory")
    private let countLabel = NSTextField(labelWithString: "")
    private let addButton = NSButton(title: "+", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let divider = NSView()
    private let filterControl = NSSegmentedControl()
    private let scrollView = NSScrollView()
    private let listView = MemoryListView()

    private var activeFilter: MemoryCategory? = nil

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.15
        layer?.shadowRadius = 20
        layer?.shadowOffset = CGSize(width: -4, height: 0)

        setupHeader()
        setupFilter()
        setupList()
        refresh()

        NotificationCenter.default.addObserver(
            self, selector: #selector(memoryChanged),
            name: MemoryStore.didChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChange),
            name: Theme.themeDidChange, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Setup

    private func setupHeader() {
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = Theme.chrome.cgColor
        addSubview(headerView)

        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Theme.textPrimary
        headerView.addSubview(titleLabel)

        countLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = Theme.textTertiary
        headerView.addSubview(countLabel)

        addButton.bezelStyle = .rounded
        addButton.isBordered = false
        addButton.font = NSFont.systemFont(ofSize: 18, weight: .light)
        addButton.contentTintColor = Theme.textSecondary
        addButton.target = self
        addButton.action = #selector(addMemory(_:))
        addButton.toolTip = "Add memory"
        headerView.addSubview(addButton)

        clearButton.bezelStyle = .rounded
        clearButton.isBordered = false
        clearButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        clearButton.contentTintColor = Theme.textTertiary
        clearButton.target = self
        clearButton.action = #selector(clearMemories(_:))
        headerView.addSubview(clearButton)

        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.divider.cgColor
        addSubview(divider)
    }

    private func setupFilter() {
        let categories = ["All"] + MemoryCategory.allCases.map { $0.label }
        filterControl.segmentCount = categories.count
        for (i, name) in categories.enumerated() {
            filterControl.setLabel(name, forSegment: i)
            filterControl.setWidth(0, forSegment: i)  // auto-size
        }
        filterControl.selectedSegment = 0
        filterControl.segmentStyle = .rounded
        filterControl.target = self
        filterControl.action = #selector(filterChanged(_:))
        filterControl.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        addSubview(filterControl)
    }

    private func setupList() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = listView
        addSubview(scrollView)

        listView.onDelete = { [weak self] entry in
            MemoryStore.shared.remove(entry)
            self?.refresh()
        }
        listView.onTogglePin = { [weak self] entry in
            MemoryStore.shared.togglePin(entry)
            self?.refresh()
        }
    }

    // MARK: - Layout

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let w = bounds.width
        let headerH: CGFloat = 52
        let filterH: CGFloat = 28
        let pad: CGFloat = 12

        headerView.frame = NSRect(x: 0, y: 0, width: w, height: headerH)
        titleLabel.frame = NSRect(x: pad, y: 16, width: 80, height: 20)
        countLabel.frame = NSRect(x: 72, y: 18, width: 60, height: 16)
        addButton.frame = NSRect(x: w - 76, y: 12, width: 30, height: 28)
        clearButton.frame = NSRect(x: w - 48, y: 16, width: 40, height: 20)
        divider.frame = NSRect(x: 0, y: headerH, width: w, height: 1)

        filterControl.frame = NSRect(x: pad, y: headerH + 8, width: w - pad * 2, height: filterH)

        let listTop = headerH + filterH + 16
        scrollView.frame = NSRect(x: 0, y: listTop, width: w, height: bounds.height - listTop)

        let listH = max(bounds.height - listTop, listView.contentHeight)
        listView.frame = NSRect(x: 0, y: 0, width: w, height: listH)
    }

    // MARK: - Refresh

    private func refresh() {
        let store = MemoryStore.shared
        let entries: [MemoryEntry]

        if let filter = activeFilter {
            entries = store.memories(for: filter)
        } else {
            entries = store.memories
        }

        // Sort: pinned first, then by date descending
        let sorted = entries.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.createdAt > b.createdAt
        }

        listView.entries = sorted
        listView.frame.size.height = max(scrollView.bounds.height, listView.contentHeight)
        listView.needsDisplay = true

        countLabel.stringValue = "(\(store.memories.count))"
    }

    // MARK: - Actions

    @objc private func addMemory(_ sender: Any) {
        let alert = NSAlert()
        alert.messageText = "Add Memory"
        alert.informativeText = "Enter a note, preference, or context to remember across sessions."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 80))
        input.placeholderString = "e.g. Always use Swift conventions, prefer async/await..."
        input.isEditable = true
        input.isBordered = true
        input.bezelStyle = .roundedBezel
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn, !input.stringValue.isEmpty {
            MemoryStore.shared.addMemory(category: .note, content: input.stringValue)
        }
    }

    @objc private func clearMemories(_ sender: Any) {
        let alert = NSAlert()
        alert.messageText = "Clear Memories"
        alert.informativeText = activeFilter != nil
            ? "Remove all \(activeFilter!.label) memories?"
            : "Remove all memories? This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            MemoryStore.shared.removeAll(category: activeFilter)
        }
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            activeFilter = nil
        } else {
            activeFilter = MemoryCategory.allCases[sender.selectedSegment - 1]
        }
        refresh()
    }

    @objc private func memoryChanged() {
        refresh()
    }

    @objc private func handleThemeChange() {
        layer?.backgroundColor = Theme.surface.cgColor
        headerView.layer?.backgroundColor = Theme.chrome.cgColor
        divider.layer?.backgroundColor = Theme.divider.cgColor
        titleLabel.textColor = Theme.textPrimary
        countLabel.textColor = Theme.textTertiary
        addButton.contentTintColor = Theme.textSecondary
        clearButton.contentTintColor = Theme.textTertiary
        listView.needsDisplay = true
    }
}

// MARK: - Memory List View (custom draw)

private class MemoryListView: NSView {

    var entries: [MemoryEntry] = []
    var onDelete: ((MemoryEntry) -> Void)?
    var onTogglePin: ((MemoryEntry) -> Void)?

    private let rowHeight: CGFloat = 72
    private let pad: CGFloat = 12
    private var hoveredIndex: Int = -1

    override var isFlipped: Bool { true }

    var contentHeight: CGFloat {
        CGFloat(entries.count) * rowHeight + 8
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width

        if entries.isEmpty {
            let emptyAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: Theme.textTertiary,
            ]
            let str = NSAttributedString(string: "No memories yet", attributes: emptyAttrs)
            let sz = str.size()
            str.draw(at: NSPoint(x: (w - sz.width) / 2, y: 40))
            return
        }

        let dateFormatter = RelativeDateTimeFormatter()
        dateFormatter.unitsStyle = .abbreviated

        for (i, entry) in entries.enumerated() {
            let rowRect = NSRect(x: 0, y: CGFloat(i) * rowHeight, width: w, height: rowHeight)
            guard rowRect.intersects(dirtyRect) else { continue }

            // Hover background
            if i == hoveredIndex {
                Theme.hover.withAlphaComponent(0.5).setFill()
                NSBezierPath(roundedRect: rowRect.insetBy(dx: 4, dy: 2), xRadius: 6, yRadius: 6).fill()
            }

            // Pin indicator
            if entry.pinned {
                let pinAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: Theme.accent,
                ]
                NSAttributedString(string: "📌", attributes: pinAttrs)
                    .draw(at: NSPoint(x: pad, y: rowRect.minY + 8))
            }

            // Category badge
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: Theme.textTertiary,
            ]
            let badgeStr = NSAttributedString(string: entry.category.label, attributes: badgeAttrs)
            let badgeSize = badgeStr.size()
            let badgeX = entry.pinned ? pad + 18 : pad
            let badgePadH: CGFloat = 5
            let badgePadV: CGFloat = 2
            let badgeRect = NSRect(
                x: badgeX, y: rowRect.minY + 6,
                width: badgeSize.width + badgePadH * 2,
                height: badgeSize.height + badgePadV * 2
            )
            Theme.chrome.setFill()
            NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()
            badgeStr.draw(at: NSPoint(x: badgeRect.minX + badgePadH, y: badgeRect.minY + badgePadV))

            // Timestamp
            let timeStr = dateFormatter.localizedString(for: entry.createdAt, relativeTo: Date())
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: Theme.textTertiary,
            ]
            let timeNS = NSAttributedString(string: timeStr, attributes: timeAttrs)
            let timeSize = timeNS.size()
            timeNS.draw(at: NSPoint(x: w - pad - timeSize.width, y: rowRect.minY + 8))

            // Content (truncated to 2 lines)
            let contentAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: Theme.textPrimary,
            ]
            let contentText = entry.content.replacingOccurrences(of: "\n", with: " ")
            let truncated = contentText.count > 120 ? String(contentText.prefix(120)) + "..." : contentText
            let contentStr = NSAttributedString(string: truncated, attributes: contentAttrs)
            let contentRect = NSRect(x: pad, y: rowRect.minY + 26, width: w - pad * 2, height: 36)
            contentStr.draw(with: contentRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

            // Source label
            if let source = entry.source {
                let sourceAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: Theme.textTertiary,
                ]
                let sourceStr = NSAttributedString(string: "from: \(source)", attributes: sourceAttrs)
                sourceStr.draw(at: NSPoint(x: pad, y: rowRect.maxY - 16))
            }

            // Bottom divider
            Theme.divider.setFill()
            NSRect(x: pad, y: rowRect.maxY - 1, width: w - pad * 2, height: 0.5).fill()
        }
    }

    // MARK: - Mouse Tracking

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let idx = Int(pt.y / rowHeight)
        if idx >= 0, idx < entries.count, idx != hoveredIndex {
            hoveredIndex = idx
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = -1
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let idx = Int(pt.y / rowHeight)
        guard idx >= 0, idx < entries.count else { return }

        let entry = entries[idx]
        let menu = NSMenu()

        let pinTitle = entry.pinned ? "Unpin" : "Pin"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(contextPin(_:)), keyEquivalent: "")
        pinItem.representedObject = entry
        pinItem.target = self
        menu.addItem(pinItem)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(contextCopy(_:)), keyEquivalent: "")
        copyItem.representedObject = entry
        copyItem.target = self
        menu.addItem(copyItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(contextDelete(_:)), keyEquivalent: "")
        deleteItem.representedObject = entry
        deleteItem.target = self
        menu.addItem(deleteItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextPin(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? MemoryEntry else { return }
        onTogglePin?(entry)
    }

    @objc private func contextCopy(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? MemoryEntry else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.content, forType: .string)
    }

    @objc private func contextDelete(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? MemoryEntry else { return }
        onDelete?(entry)
    }
}
