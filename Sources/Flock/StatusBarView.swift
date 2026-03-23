import AppKit

class StatusBarView: NSView {
    weak var paneManager: PaneManager?
    private let label = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let broadcastBadge = NSTextField(labelWithString: "")
    private var lastText: String = ""
    private var durationTimer: Timer?

    override var isFlipped: Bool { true }

    init(paneManager: PaneManager) {
        self.paneManager = paneManager
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = Theme.chrome.cgColor

        label.font = Theme.Typo.status
        label.textColor = Theme.textTertiary
        addSubview(label)

        durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.textColor = Theme.textTertiary
        durationLabel.alignment = .right
        addSubview(durationLabel)

        broadcastBadge.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        broadcastBadge.textColor = NSColor(hex: 0xFF9500)
        broadcastBadge.stringValue = "BROADCAST"
        broadcastBadge.isHidden = true
        addSubview(broadcastBadge)

        update()

        // Timer for live command duration
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDuration()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: Theme.themeDidChange, object: nil)
    }

    @objc private func themeChanged() {
        layer?.backgroundColor = Theme.chrome.cgColor
        label.textColor = Theme.textTertiary
        durationLabel.textColor = Theme.textTertiary
        needsDisplay = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func update() {
        guard let mgr = paneManager else { return }
        let n = mgr.panes.count
        let newText = n == 0 ? "" : n == 1 ? "1 session" : "\(n) sessions"

        if newText != lastText && !lastText.isEmpty {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Theme.Anim.fast
                self.label.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.label.stringValue = newText
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = Theme.Anim.fast
                    self?.label.animator().alphaValue = 1
                }
            })
        } else {
            label.stringValue = newText
        }
        lastText = newText

        // Broadcast badge
        broadcastBadge.isHidden = !(mgr.isBroadcasting)

        updateDuration()
        needsDisplay = true
    }

    private func updateDuration() {
        guard let mgr = paneManager,
              mgr.activePaneIndex >= 0, mgr.activePaneIndex < mgr.panes.count else {
            durationLabel.stringValue = ""
            return
        }
        let pane = mgr.panes[mgr.activePaneIndex]
        if let start = pane.commandStartTime {
            let elapsed = Int(Date().timeIntervalSince(start))
            durationLabel.stringValue = "Running: \(elapsed)s"
        } else if let duration = pane.lastCommandDuration {
            if duration < 1 {
                durationLabel.stringValue = String(format: "Last: %.0fms", duration * 1000)
            } else if duration < 60 {
                durationLabel.stringValue = String(format: "Last: %.1fs", duration)
            } else {
                let mins = Int(duration) / 60
                let secs = Int(duration) % 60
                durationLabel.stringValue = "Last: \(mins)m\(secs)s"
            }
        } else {
            durationLabel.stringValue = ""
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let pad = Theme.Space.lg
        let labelH: CGFloat = 16
        let labelY = (bounds.height - labelH) / 2
        broadcastBadge.frame = NSRect(x: pad, y: labelY, width: 70, height: labelH)
        let labelX = (paneManager?.isBroadcasting == true) ? pad + 76 : pad
        label.frame = NSRect(x: labelX, y: labelY, width: 200, height: labelH)
        durationLabel.frame = NSRect(x: bounds.width - 200 - pad, y: labelY, width: 200, height: labelH)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let fadeLen: CGFloat = bounds.width * 0.1
        let color = Theme.divider

        for i in 0..<Int(fadeLen) {
            let alpha = CGFloat(i) / fadeLen
            ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
            ctx.fill(CGRect(x: CGFloat(i), y: 0, width: 1, height: 0.5))
        }
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: fadeLen, y: 0, width: bounds.width - fadeLen * 2, height: 0.5))
        for i in 0..<Int(fadeLen) {
            let alpha = CGFloat(i) / fadeLen
            ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
            ctx.fill(CGRect(x: bounds.width - CGFloat(i) - 1, y: 0, width: 1, height: 0.5))
        }
    }
}
