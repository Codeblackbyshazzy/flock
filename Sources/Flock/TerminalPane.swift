import AppKit
import SwiftTerm

class TerminalPane: NSView, LocalProcessTerminalViewDelegate {
    let terminalView: FlockTerminalView
    let type: PaneType
    var customName: String?
    var shouldResume: Bool = false
    weak var manager: PaneManager?

    private let clipView = NSView(frame: .zero)
    private let ambientShadowLayer = CALayer()
    private let dimOverlayLayer = CALayer()

    // Agent activity detection (Claude panes only)
    private(set) var isAgentActive: Bool = false
    private var agentActivityTimer: Timer?
    private let agentIdleTimeout: TimeInterval = 2.5
    private var recentByteCount: Int = 0
    private var byteWindowTimer: Timer?
    private let byteRateThreshold: Int = 150  // bytes per second to count as "active"

    // Agent state parsing (Claude panes only)
    let outputParser = ClaudeOutputParser()
    private(set) var agentState: AgentState = .idle

    // Process title tracking
    var processTitle: String?

    // Current working directory (for session restore + title bar)
    var currentDirectory: String?

    // Temp ZDOTDIR for shell enhancements (cleaned up on shutdown)
    private var zdotdir: String?

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
    private let titleBarHeight: CGFloat = 24

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

        // Agent state parser
        outputParser.onStateChange = { [weak self] state in
            guard let self else { return }
            let oldState = self.agentState
            self.agentState = state

            self.updateTitleBar()
            self.manager?.tabBar?.update()
            self.manager?.statusBar?.update()

            // Notify on important state changes in unfocused panes
            if !self.isFocused {
                let paneName = self.customName ?? self.processTitle ?? self.type.label
                let paneIdx = self.manager?.panes.firstIndex(where: { $0 === self }) ?? 0
                if state == .waiting && oldState != .waiting {
                    FlockNotifications.sendAgentStateChange(
                        paneName: paneName, paneIndex: paneIdx, state: "Waiting for your input")
                    SoundEffects.playChime()
                } else if state == .error && oldState != .error {
                    FlockNotifications.sendAgentStateChange(
                        paneName: paneName, paneIndex: paneIdx, state: "Error detected")
                }
            }
        }

        // Terminal
        let fontSize = Settings.shared.fontSize
        terminalView.nativeBackgroundColor = Theme.terminalBg
        terminalView.nativeForegroundColor = Theme.terminalFg
        terminalView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        installAnsiColors()
        terminalView.processDelegate = self
        clipView.addSubview(terminalView)

        // Start shell with enhancements (autosuggestions)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let name = (shell as NSString).lastPathComponent
        let cwd = workingDirectory ?? ProcessInfo.processInfo.environment["HOME"]

        if let enhanced = ShellEnhancer.enhancedEnvironment(workingDirectory: workingDirectory) {
            self.zdotdir = enhanced.zdotdir
            terminalView.startProcess(executable: shell, environment: enhanced.env, execName: "-\(name)", currentDirectory: cwd)
        } else {
            terminalView.startProcess(executable: shell, execName: "-\(name)", currentDirectory: cwd)
        }

        if type == .claude {
            // Write memory context file before launching Claude
            if Settings.shared.memoryEnabled {
                let contextDir = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
                MemoryStore.shared.writeContextFile(to: contextDir)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.sendText(self.shouldResume ? "claude --resume\n" : "claude\n")
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
        dimOverlayLayer.backgroundColor = Theme.chrome.withAlphaComponent(0.04).cgColor
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
        let stateLabel = (agentState != .idle) ? agentState.label : nil
        titleProcessLabel.stringValue = stateLabel ?? processTitle ?? type.label
        titleProcessLabel.textColor = (agentState == .waiting) ? Theme.accent
            : (agentState == .error) ? NSColor(hex: 0xFF3B30)
            : Theme.textSecondary
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

        // Constant border width -- only animate color (prevents layout twitch)
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

    func shutdown() {
        if let dir = zdotdir { ShellEnhancer.cleanup(zdotdir: dir) }
        terminalView.terminate()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        clipView.frame = bounds
        let titleY: CGFloat = 0
        paneTitleBar.frame = CGRect(x: 0, y: titleY, width: clipView.bounds.width, height: titleBarHeight)
        // Vertically center the labels in the title bar
        let labelH: CGFloat = 16
        let labelY = (titleBarHeight - labelH) / 2
        titleProcessLabel.frame = CGRect(x: 8, y: labelY, width: paneTitleBar.bounds.width / 2 - 12, height: labelH)
        titleCwdLabel.frame = CGRect(x: paneTitleBar.bounds.width / 2, y: labelY, width: paneTitleBar.bounds.width / 2 - 8, height: labelH)
        // Terminal inner padding: 8px on left, right, and bottom
        let pad: CGFloat = 8
        terminalView.frame = CGRect(x: pad, y: titleBarHeight, width: clipView.bounds.width - pad * 2, height: clipView.bounds.height - titleBarHeight - pad)
        ambientShadowLayer.frame = bounds
        dimOverlayLayer.frame = bounds
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
        let paneIdx = manager?.panes.firstIndex(where: { $0 === self }) ?? 0
        FlockNotifications.sendCompletion(paneName: paneName, paneIndex: paneIdx, duration: lastCommandDuration)
    }
}
