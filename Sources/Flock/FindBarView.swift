import AppKit
import SwiftTerm

// ---------------------------------------------------------------------------
// MARK: - FindBarView
// ---------------------------------------------------------------------------
/// Floating search bar that overlays the top of the active terminal pane.
/// Uses SwiftTerm's built-in `findNext` / `findPrevious` / `clearSearch` API.
///
/// Add as a subview of the terminal pane and call `show()`. The bar positions
/// itself at the top of its superview (8px inset, 24px horizontal margins).
class FindBarView: NSView, NSTextFieldDelegate {

    // MARK: - Public interface

    weak var terminalView: LocalProcessTerminalView?

    /// Reveal the bar and focus the search field.
    func show() {
        isHidden = false
        window?.makeFirstResponder(searchField)
    }

    /// Clear highlights, remove from superview, and return focus to terminal.
    func dismiss() {
        let tv = terminalView
        searchField.stringValue = ""
        statusLabel.stringValue = ""
        currentTerm = ""
        lastFindSucceeded = false
        tv?.clearSearch()
        isHidden = true
        removeFromSuperview()
        if let tv { tv.window?.makeFirstResponder(tv) }
    }

    // MARK: - Subviews

    private let searchField: NSTextField = {
        let f = NSTextField(frame: .zero)
        f.placeholderString = "Find..."
        f.font = NSFont.systemFont(ofSize: 13)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.lineBreakMode = .byTruncatingTail
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        return f
    }()

    private let statusLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        l.textColor = Theme.textTertiary
        l.alignment = .right
        l.isSelectable = false
        return l
    }()

    private let prevButton = FindBarView.makeIconButton(title: "\u{2039}", tooltip: "Previous Match")
    private let nextButton = FindBarView.makeIconButton(title: "\u{203A}", tooltip: "Next Match")
    private let closeButton = FindBarView.makeIconButton(title: "\u{00D7}", tooltip: "Close")

    // MARK: - State

    private var currentTerm: String = ""
    private var lastFindSucceeded: Bool = false
    private var buttonTrackingAreas: [NSView: NSTrackingArea] = [:]

    // MARK: - Layout constants

    override var isFlipped: Bool { true }

    private enum K {
        static let barHeight: CGFloat = 36
        static let insetX: CGFloat = 24
        static let topInset: CGFloat = 8
        static let innerPadX: CGFloat = 10
        static let buttonSize: CGFloat = 24
        static let buttonGap: CGFloat = 2
        static let statusWidth: CGFloat = 64
        static let cornerRadius: CGFloat = 8
    }

    // MARK: - Init

    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Theme.surface.withAlphaComponent(0.97).cgColor
        layer?.cornerRadius = K.cornerRadius
        layer?.borderWidth = 0.5
        layer?.borderColor = Theme.borderRest.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.06
        layer?.shadowRadius = 2
        layer?.shadowOffset = CGSize(width: 0, height: 0.5)

        searchField.delegate = self
        addSubview(searchField)
        addSubview(statusLabel)

        prevButton.target = self
        prevButton.action = #selector(findPrevious(_:))
        addSubview(prevButton)

        nextButton.target = self
        nextButton.action = #selector(findNext(_:))
        addSubview(nextButton)

        closeButton.target = self
        closeButton.action = #selector(closeTapped(_:))
        addSubview(closeButton)
    }

    // MARK: - Superview integration

    /// When added to a pane, size and position automatically.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let sv = superview else { return }
        frame = NSRect(
            x: K.insetX,
            y: K.topInset,
            width: sv.bounds.width - K.insetX * 2,
            height: K.barHeight
        )
        autoresizingMask = [.width]
        layoutContents()
    }

    // MARK: - Layout

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutContents()
    }

    private func layoutContents() {
        let h = bounds.height
        let midY = floor((h - K.buttonSize) / 2)
        let fieldY = floor((h - 22) / 2)

        // Close button — rightmost
        let closeX = bounds.width - K.innerPadX - K.buttonSize
        closeButton.frame = NSRect(x: closeX, y: midY, width: K.buttonSize, height: K.buttonSize)

        // Next button
        let nextX = closeX - K.buttonGap - K.buttonSize
        nextButton.frame = NSRect(x: nextX, y: midY, width: K.buttonSize, height: K.buttonSize)

        // Prev button
        let prevX = nextX - K.buttonGap - K.buttonSize
        prevButton.frame = NSRect(x: prevX, y: midY, width: K.buttonSize, height: K.buttonSize)

        // Status label
        let statusX = prevX - 4 - K.statusWidth
        statusLabel.frame = NSRect(x: statusX, y: fieldY, width: K.statusWidth, height: 22)

        // Search field fills remaining space
        let fieldX: CGFloat = K.innerPadX
        let fieldW = statusX - 4 - fieldX
        searchField.frame = NSRect(x: fieldX, y: fieldY, width: max(fieldW, 60), height: 22)

        rebuildTrackingAreas()
    }

    // MARK: - Tracking areas (hover)

    private func rebuildTrackingAreas() {
        for button in [prevButton, nextButton, closeButton] {
            if let existing = buttonTrackingAreas[button] {
                button.removeTrackingArea(existing)
            }
            let area = NSTrackingArea(
                rect: button.bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow],
                owner: self,
                userInfo: ["button": button]
            )
            button.addTrackingArea(area)
            buttonTrackingAreas[button] = area
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard let button = event.trackingArea?.userInfo?["button"] as? NSView else { return }
        button.layer?.backgroundColor = Theme.hover.cgColor
        button.layer?.cornerRadius = 4
    }

    override func mouseExited(with event: NSEvent) {
        guard let button = event.trackingArea?.userInfo?["button"] as? NSView else { return }
        button.layer?.backgroundColor = nil
    }

    // MARK: - NSTextFieldDelegate (live search)

    func controlTextDidChange(_ obj: Notification) {
        guard let term = (obj.object as? NSTextField)?.stringValue else { return }
        currentTerm = term

        if term.isEmpty {
            terminalView?.clearSearch()
            lastFindSucceeded = false
            statusLabel.stringValue = ""
            return
        }

        // New term — clear previous state and find the first match.
        terminalView?.clearSearch()
        let found = terminalView?.findNext(term) ?? false
        lastFindSucceeded = found
        updateStatusLabel()
    }

    /// Handle special keys inside the search field.
    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Enter → find next; Shift+Enter → find previous
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                findPrevious(self)
            } else {
                findNext(self)
            }
            return true
        }
        return false
    }

    // MARK: - Actions

    @objc func findNext(_ sender: Any?) {
        guard !currentTerm.isEmpty else { return }
        let found = terminalView?.findNext(currentTerm) ?? false
        lastFindSucceeded = found
        updateStatusLabel()
    }

    @objc func findPrevious(_ sender: Any?) {
        guard !currentTerm.isEmpty else { return }
        let found = terminalView?.findPrevious(currentTerm) ?? false
        lastFindSucceeded = found
        updateStatusLabel()
    }

    @objc private func closeTapped(_ sender: Any?) {
        dismiss()
    }

    // MARK: - Status

    private func updateStatusLabel() {
        if currentTerm.isEmpty {
            statusLabel.stringValue = ""
            return
        }
        statusLabel.stringValue = lastFindSucceeded ? "Found" : "No results"
        statusLabel.textColor = lastFindSucceeded ? Theme.textTertiary : Theme.textSecondary
    }

    // MARK: - Key equivalents (Cmd+G / Cmd+Shift+G)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+G → find next
        if flags == .command, event.charactersIgnoringModifiers == "g" {
            findNext(self)
            return true
        }
        // Cmd+Shift+G → find previous
        if flags == [.command, .shift], event.charactersIgnoringModifiers == "G" {
            findPrevious(self)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Button factory

    private static func makeIconButton(title: String, tooltip: String) -> NSButton {
        let b = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        b.title = title
        b.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        b.alignment = .center
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 4
        b.toolTip = tooltip
        b.bezelStyle = .inline
        b.setButtonType(.momentaryPushIn)
        (b.cell as? NSButtonCell)?.highlightsBy = []
        return b
    }
}
