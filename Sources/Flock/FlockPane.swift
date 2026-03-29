import AppKit

/// Base class for all pane types in Flock (terminal, markdown, etc.)
/// Provides shared visual chrome: shadows, borders, dim overlay, title bar, animations.
class FlockPane: NSView {
    let paneType: PaneType
    var customName: String? {
        didSet {
            updateTitleBar()
            manager?.tabBar?.update()
            manager?.statusBar?.update()
        }
    }
    weak var manager: PaneManager?

    // Visual chrome
    let clipView = NSView(frame: .zero)
    private let ambientShadowLayer = CALayer()
    private let dimOverlayLayer = CALayer()
    private let accentBarLayer = CALayer()

    // Title bar
    let paneTitleBar = NSView(frame: .zero)
    let titleProcessLabel = NSTextField(labelWithString: "")
    let titleCwdLabel = NSTextField(labelWithString: "")
    let titleBarHeight: CGFloat = 24

    // Shared state -- subclasses modify directly
    var isAgentActive: Bool = false
    var processTitle: String?
    var agentState: AgentState = .idle
    var commandStartTime: Date?
    var lastCommandDuration: TimeInterval?
    var currentDirectory: String?

    var accentColor: NSColor? {
        didSet { updateAccentBar() }
    }

    var isFocused: Bool = false {
        didSet { animateAppearance() }
    }

    override var isFlipped: Bool { true }

    /// The view that should become first responder when this pane is focused.
    var firstResponderView: NSView { self }

    init(type: PaneType, manager: PaneManager) {
        self.paneType = type
        self.manager = manager
        super.init(frame: .zero)
        setupChrome()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Chrome setup

    private func setupChrome() {
        wantsLayer = true
        layer?.cornerRadius = Theme.paneRadius
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Theme.Shadow.Rest.contact.opacity
        layer?.shadowRadius = Theme.Shadow.Rest.contact.radius
        layer?.shadowOffset = Theme.Shadow.Rest.contact.offset
        layer?.borderWidth = 1
        layer?.borderColor = Theme.borderRest.cgColor

        // Ambient shadow
        ambientShadowLayer.shadowColor = NSColor.black.cgColor
        ambientShadowLayer.shadowOpacity = Theme.Shadow.Rest.ambient.opacity
        ambientShadowLayer.shadowRadius = Theme.Shadow.Rest.ambient.radius
        ambientShadowLayer.shadowOffset = Theme.Shadow.Rest.ambient.offset
        ambientShadowLayer.backgroundColor = Theme.surface.cgColor
        ambientShadowLayer.cornerRadius = Theme.paneRadius
        layer?.insertSublayer(ambientShadowLayer, at: 0)

        // Accent bar (hidden by default)
        accentBarLayer.isHidden = true
        accentBarLayer.cornerRadius = 1.5
        layer?.addSublayer(accentBarLayer)

        // Clip view
        clipView.wantsLayer = true
        clipView.layer?.cornerRadius = Theme.paneRadius
        clipView.layer?.masksToBounds = true
        addSubview(clipView)

        // Dim overlay for unfocused panes
        dimOverlayLayer.backgroundColor = Theme.chrome.withAlphaComponent(0.04).cgColor
        dimOverlayLayer.cornerRadius = Theme.paneRadius
        dimOverlayLayer.opacity = 1  // starts dimmed (unfocused)
        layer?.addSublayer(dimOverlayLayer)

        // Pane title bar
        paneTitleBar.wantsLayer = true
        paneTitleBar.layer?.backgroundColor = Theme.surface.cgColor
        clipView.addSubview(paneTitleBar)

        titleProcessLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        titleProcessLabel.textColor = Theme.textSecondary
        titleProcessLabel.isBezeled = false
        titleProcessLabel.drawsBackground = false
        titleProcessLabel.isEditable = false
        titleProcessLabel.lineBreakMode = .byTruncatingTail
        paneTitleBar.addSubview(titleProcessLabel)

        titleCwdLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        titleCwdLabel.textColor = Theme.textTertiary
        titleCwdLabel.alignment = .right
        titleCwdLabel.isBezeled = false
        titleCwdLabel.drawsBackground = false
        titleCwdLabel.isEditable = false
        titleCwdLabel.lineBreakMode = .byTruncatingMiddle
        paneTitleBar.addSubview(titleCwdLabel)

        updateTitleBar()

        // Theme observer
        NotificationCenter.default.addObserver(self, selector: #selector(baseThemeDidChange),
                                               name: Theme.themeDidChange, object: nil)
    }

    // MARK: - Title bar (override in subclasses)

    func updateTitleBar() {
        titleProcessLabel.stringValue = customName ?? paneType.label
        titleCwdLabel.stringValue = ""
    }

    /// Override in subclasses that support full-text search outside the terminal find API.
    func matchesSearchTerm(_ term: String) -> Bool { false }

    // MARK: - Theme

    @objc private func baseThemeDidChange() {
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.borderColor = (isFocused ? Theme.borderFocus : Theme.borderRest).cgColor
        ambientShadowLayer.backgroundColor = Theme.surface.cgColor
        dimOverlayLayer.backgroundColor = Theme.chrome.withAlphaComponent(0.04).cgColor
        paneTitleBar.layer?.backgroundColor = Theme.surface.cgColor
        titleProcessLabel.textColor = Theme.textSecondary
        titleCwdLabel.textColor = Theme.textTertiary
        themeDidChange()
    }

    /// Override point for subclass-specific theme updates.
    func themeDidChange() {}

    // MARK: - Accent bar

    private func updateAccentBar() {
        if let color = accentColor {
            accentBarLayer.isHidden = false
            accentBarLayer.backgroundColor = color.cgColor
        } else {
            accentBarLayer.isHidden = true
        }
    }

    // MARK: - Focus animation

    private func animateAppearance() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(Theme.Anim.normal)
        CATransaction.setAnimationTimingFunction(Theme.Anim.snappyTimingFunction)

        layer?.borderWidth = 1

        if isFocused {
            layer?.shadowOpacity = Theme.Shadow.Focus.contact.opacity
            layer?.shadowRadius = Theme.Shadow.Focus.contact.radius
            layer?.shadowOffset = Theme.Shadow.Focus.contact.offset
            layer?.borderColor = Theme.borderFocus.cgColor
            ambientShadowLayer.shadowOpacity = Theme.Shadow.Focus.ambient.opacity
            ambientShadowLayer.shadowRadius = Theme.Shadow.Focus.ambient.radius
            ambientShadowLayer.shadowOffset = Theme.Shadow.Focus.ambient.offset
            dimOverlayLayer.opacity = 0
        } else {
            layer?.shadowOpacity = Theme.Shadow.Rest.contact.opacity
            layer?.shadowRadius = Theme.Shadow.Rest.contact.radius
            layer?.shadowOffset = Theme.Shadow.Rest.contact.offset
            layer?.borderColor = Theme.borderRest.cgColor
            ambientShadowLayer.shadowOpacity = Theme.Shadow.Rest.ambient.opacity
            ambientShadowLayer.shadowRadius = Theme.Shadow.Rest.ambient.radius
            ambientShadowLayer.shadowOffset = Theme.Shadow.Rest.ambient.offset
            dimOverlayLayer.opacity = 1
        }

        CATransaction.commit()
    }

    // MARK: - Entrance / Exit animations

    func animateEntrance() {
        alphaValue = 0
        layer?.setAffineTransform(CGAffineTransform(scaleX: 0.96, y: 0.96))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.Anim.slow
            ctx.timingFunction = Theme.Anim.snappyTimingFunction
            self.animator().alphaValue = 1
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(Theme.Anim.slow)
        CATransaction.setAnimationTimingFunction(Theme.Anim.snappyTimingFunction)
        layer?.setAffineTransform(.identity)
        CATransaction.commit()
    }

    func animateExit(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Theme.Anim.normal
            ctx.timingFunction = Theme.Anim.snappyTimingFunction
            self.animator().alphaValue = 0
        }, completionHandler: completion)
        CATransaction.begin()
        CATransaction.setAnimationDuration(Theme.Anim.normal)
        CATransaction.setAnimationTimingFunction(Theme.Anim.snappyTimingFunction)
        layer?.setAffineTransform(CGAffineTransform(scaleX: 0.97, y: 0.97))
        CATransaction.commit()
    }

    func animateFadeOut() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.Anim.normal
            ctx.timingFunction = Theme.Anim.snappyTimingFunction
            self.animator().alphaValue = 0
        }
    }

    func animateFadeIn() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.Anim.normal
            ctx.timingFunction = Theme.Anim.snappyTimingFunction
            self.animator().alphaValue = 1
        }
    }

    // MARK: - Layout

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        clipView.frame = bounds
        paneTitleBar.frame = CGRect(x: 0, y: 0, width: clipView.bounds.width, height: titleBarHeight)
        let labelH: CGFloat = 16
        let labelY = (titleBarHeight - labelH) / 2
        titleProcessLabel.frame = CGRect(x: 8, y: labelY, width: paneTitleBar.bounds.width / 2 - 12, height: labelH)
        titleCwdLabel.frame = CGRect(x: paneTitleBar.bounds.width / 2, y: labelY, width: paneTitleBar.bounds.width / 2 - 8, height: labelH)
        ambientShadowLayer.frame = bounds
        dimOverlayLayer.frame = bounds
        accentBarLayer.frame = CGRect(x: 4, y: 0, width: bounds.width - 8, height: 3)

        layoutContent()
    }

    /// Override in subclasses to layout content within clipView.
    func layoutContent() {}

    // MARK: - Shutdown

    /// Override in subclasses to clean up resources.
    func shutdown() {}
}
