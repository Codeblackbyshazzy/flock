import AppKit
import SwiftTerm

class TerminalPane: NSView, LocalProcessTerminalViewDelegate {
    let terminalView: FlockTerminalView
    let type: PaneType
    var customName: String?
    weak var manager: PaneManager?

    private let clipView = NSView(frame: .zero)
    private let ambientShadowLayer = CALayer()

    // Agent activity detection (Claude panes only)
    private(set) var isAgentActive: Bool = false
    private var agentActivityTimer: Timer?
    private let agentIdleTimeout: TimeInterval = 2.5
    private var recentByteCount: Int = 0
    private var byteWindowTimer: Timer?
    private let byteRateThreshold: Int = 150  // bytes per second to count as "active"

    // Process title tracking
    var processTitle: String?

    // Current working directory (for session restore + title bar)
    var currentDirectory: String?

    // Accent color (optional per-pane coloring)
    var accentColor: NSColor? {
        didSet { updateAccentBar() }
    }
    private let accentBarLayer = CALayer()

    // Command timing
    private(set) var commandStartTime: Date?
    var lastCommandDuration: TimeInterval?
    private var lastKnownTitle: String?

    // Pane title bar
    private let paneTitleBar = NSView(frame: .zero)
    private let titleProcessLabel = NSTextField(labelWithString: "")
    private let titleCwdLabel = NSTextField(labelWithString: "")
    private let titleBarHeight: CGFloat = 20

    var isFocused: Bool = false {
        didSet {
            animateAppearance()
        }
    }

    var isRunningCommand: Bool { commandStartTime != nil }

    override var isFlipped: Bool { true }

    init(type: PaneType, manager: PaneManager, workingDirectory: String? = nil) {
        self.type = type
        self.manager = manager
        self.terminalView = FlockTerminalView(frame: .zero)
        super.init(frame: .zero)

        terminalView.owningPane = self

        // Shadow layer (self) — no clipping so shadow is visible
        wantsLayer = true
        layer?.cornerRadius = Theme.paneRadius
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.shadowColor = NSColor.black.cgColor

        layer?.shadowOpacity = Theme.Shadow.Rest.contact.opacity
        layer?.shadowRadius = Theme.Shadow.Rest.contact.radius
        layer?.shadowOffset = Theme.Shadow.Rest.contact.offset

        layer?.borderWidth = 0.5
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

        // Pane title bar
        paneTitleBar.wantsLayer = true
        paneTitleBar.layer?.backgroundColor = Theme.chrome.cgColor
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

        // Terminal
        let fontSize = Settings.shared.fontSize
        terminalView.nativeBackgroundColor = Theme.terminalBg
        terminalView.nativeForegroundColor = Theme.terminalFg
        terminalView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        installAnsiColors()
        terminalView.processDelegate = self
        clipView.addSubview(terminalView)

        // Start shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let name = (shell as NSString).lastPathComponent
        terminalView.startProcess(executable: shell, execName: "-\(name)")

        // Navigate to working directory if provided
        if let dir = workingDirectory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.sendText("cd \(dir)\n")
            }
        }

        if type == .claude {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.sendText("claude\n")
            }
        }

        // Listen for changes
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged(_:)),
                                               name: Settings.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange),
                                               name: Theme.themeDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func settingsChanged(_ note: Notification) {
        guard let key = note.userInfo?["key"] as? String else { return }
        if key == "fontSize" {
            terminalView.font = NSFont.monospacedSystemFont(ofSize: Settings.shared.fontSize, weight: .regular)
        }
    }

    @objc private func themeDidChange() {
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.borderColor = (isFocused ? Theme.borderFocus : Theme.borderRest).cgColor
        ambientShadowLayer.backgroundColor = Theme.surface.cgColor
        terminalView.nativeBackgroundColor = Theme.terminalBg
        terminalView.nativeForegroundColor = Theme.terminalFg
        paneTitleBar.layer?.backgroundColor = Theme.chrome.cgColor
        titleProcessLabel.textColor = Theme.textSecondary
        titleCwdLabel.textColor = Theme.textTertiary
        installAnsiColors()
        terminalView.setNeedsDisplay(terminalView.bounds)
    }

    // MARK: - Accent bar

    private func updateAccentBar() {
        if let color = accentColor {
            accentBarLayer.isHidden = false
            accentBarLayer.backgroundColor = color.cgColor
        } else {
            accentBarLayer.isHidden = true
        }
    }

    // MARK: - Title bar

    private func updateTitleBar() {
        titleProcessLabel.stringValue = processTitle ?? type.label
        if let dir = currentDirectory {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            titleCwdLabel.stringValue = dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
        } else {
            titleCwdLabel.stringValue = ""
        }
    }

    // MARK: - Agent activity detection

    func didReceiveOutput(byteCount: Int) {
        guard type == .claude && Settings.shared.showActivityIndicators else { return }

        // Accumulate bytes in a rolling 1-second window
        recentByteCount += byteCount

        if byteWindowTimer == nil {
            byteWindowTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                guard let self else { return }
                let bytes = self.recentByteCount
                self.recentByteCount = 0
                self.byteWindowTimer = nil

                if bytes >= self.byteRateThreshold {
                    // Enough output to count as active
                    if !self.isAgentActive {
                        self.isAgentActive = true
                        self.manager?.tabBar?.update()
                    }
                    // Reset idle timer
                    self.agentActivityTimer?.invalidate()
                    self.agentActivityTimer = Timer.scheduledTimer(withTimeInterval: self.agentIdleTimeout, repeats: false) { [weak self] _ in
                        guard let self, self.isAgentActive else { return }
                        self.isAgentActive = false
                        self.manager?.tabBar?.update()
                    }
                }
            }
        }
    }

    // MARK: - Focus animation

    private func animateAppearance() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(Theme.Anim.normal)
        CATransaction.setAnimationTimingFunction(Theme.Anim.snappyTimingFunction)

        if isFocused {
            layer?.shadowOpacity = Theme.Shadow.Focus.contact.opacity
            layer?.shadowRadius = Theme.Shadow.Focus.contact.radius
            layer?.shadowOffset = Theme.Shadow.Focus.contact.offset
            layer?.borderColor = Theme.borderFocus.cgColor
            layer?.borderWidth = 1
            ambientShadowLayer.shadowOpacity = Theme.Shadow.Focus.ambient.opacity
            ambientShadowLayer.shadowRadius = Theme.Shadow.Focus.ambient.radius
            ambientShadowLayer.shadowOffset = Theme.Shadow.Focus.ambient.offset
        } else {
            layer?.shadowOpacity = Theme.Shadow.Rest.contact.opacity
            layer?.shadowRadius = Theme.Shadow.Rest.contact.radius
            layer?.shadowOffset = Theme.Shadow.Rest.contact.offset
            layer?.borderColor = Theme.borderRest.cgColor
            layer?.borderWidth = 0.5
            ambientShadowLayer.shadowOpacity = Theme.Shadow.Rest.ambient.opacity
            ambientShadowLayer.shadowRadius = Theme.Shadow.Rest.ambient.radius
            ambientShadowLayer.shadowOffset = Theme.Shadow.Rest.ambient.offset
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

    private func installAnsiColors() {
        var colors: [Color] = []
        for hex in Theme.ansiHex {
            let r = UInt16(((hex >> 16) & 0xFF)) * 257
            let g = UInt16(((hex >> 8) & 0xFF)) * 257
            let b = UInt16((hex & 0xFF)) * 257
            colors.append(Color(red: r, green: g, blue: b))
        }
        terminalView.installColors(colors)
    }

    func sendText(_ text: String) { terminalView.send(txt: text) }
    func shutdown() { terminalView.terminate() }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        clipView.frame = bounds
        let titleY: CGFloat = 0
        paneTitleBar.frame = CGRect(x: 0, y: titleY, width: clipView.bounds.width, height: titleBarHeight)
        titleProcessLabel.frame = CGRect(x: 8, y: 2, width: paneTitleBar.bounds.width / 2 - 12, height: 16)
        titleCwdLabel.frame = CGRect(x: paneTitleBar.bounds.width / 2, y: 2, width: paneTitleBar.bounds.width / 2 - 8, height: 16)
        terminalView.frame = CGRect(x: 0, y: titleBarHeight, width: clipView.bounds.width, height: clipView.bounds.height - titleBarHeight)
        ambientShadowLayer.frame = bounds
        accentBarLayer.frame = CGRect(x: 4, y: 0, width: bounds.width - 8, height: 3)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let newTitle = title.isEmpty ? nil : title

        // Command duration tracking
        if let oldTitle = lastKnownTitle, oldTitle != title {
            if commandStartTime == nil && newTitle != nil {
                commandStartTime = Date()
            } else if let start = commandStartTime {
                let elapsed = Date().timeIntervalSince(start)
                lastCommandDuration = elapsed
                if !isFocused && elapsed > 10 {
                    sendCommandNotification()
                    SoundEffects.playChime()
                }
                commandStartTime = nil
            }
        }
        lastKnownTitle = title
        processTitle = newTitle
        updateTitleBar()
        manager?.tabBar?.update()
        manager?.statusBar?.update()
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        currentDirectory = directory
        updateTitleBar()
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if let start = commandStartTime, !isFocused {
            let elapsed = Date().timeIntervalSince(start)
            lastCommandDuration = elapsed
            if elapsed > 10 {
                sendCommandNotification()
                SoundEffects.playChime()
            }
        }
        commandStartTime = nil
    }

    private func sendCommandNotification() {
        let paneName = customName ?? processTitle ?? type.label
        let script = "display notification \"\(paneName) — Command completed\" with title \"Flock\""
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
    }
}
