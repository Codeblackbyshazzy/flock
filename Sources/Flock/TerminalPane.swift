import AppKit
import SwiftTerm

class TerminalPane: FlockPane, LocalProcessTerminalViewDelegate {
    let terminalView: FlockTerminalView
    var shouldResume: Bool = false

    // Agent activity detection (Claude panes only)
    private var agentActivityTimer: Timer?
    private let agentIdleTimeout: TimeInterval = 2.5
    private var recentByteCount: Int = 0
    private var byteWindowTimer: Timer?
    private let byteRateThreshold: Int = 150  // bytes per second to count as "active"

    // Agent state parsing (Claude panes only)
    let outputParser = ClaudeOutputParser()

    // Initial directory (for context file writes)
    private var contextDirectory: String?

    // Temp ZDOTDIR for shell enhancements (cleaned up on shutdown)
    private var zdotdir: String?

    // Change log overlay
    private var changeLogView: ChangeLogView?
    private(set) var isChangeLogVisible: Bool = false

    // Command timing
    private var lastKnownTitle: String?

    var isRunningCommand: Bool { commandStartTime != nil }

    override var firstResponderView: NSView { terminalView }

    init(type: PaneType, manager: PaneManager, workingDirectory: String? = nil) {
        self.terminalView = FlockTerminalView(frame: .zero)
        super.init(type: type, manager: manager)

        terminalView.owningPane = self

        // Agent state parser
        outputParser.onStateChange = { [weak self] state in
            guard let self else { return }
            self.agentState = state

            self.updateTitleBar()
            self.manager?.tabBar?.update()
            self.manager?.statusBar?.update()
        }

        outputParser.onAction = { [weak self] entry in
            self?.changeLogView?.addAction(entry)
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
            contextDirectory = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
            if let dir = contextDirectory, Settings.shared.memoryEnabled {
                MemoryStore.shared.writeContextFile(to: dir)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.sendText(self.shouldResume ? "claude --resume\n" : "claude\n")
            }
        }

        // Listen for changes
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged(_:)),
                                               name: Settings.didChange, object: nil)
        if type == .claude {
            NotificationCenter.default.addObserver(self, selector: #selector(memoryDidChange),
                                                   name: MemoryStore.didChange, object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        byteWindowTimer?.invalidate()
        agentActivityTimer?.invalidate()
        shutdown()
    }

    @objc private func settingsChanged(_ note: Notification) {
        guard let key = note.userInfo?["key"] as? String else { return }
        if key == "fontSize" {
            terminalView.font = NSFont.monospacedSystemFont(ofSize: Settings.shared.fontSize, weight: .regular)
        } else if key == "memoryEnabled", let dir = contextDirectory {
            if Settings.shared.memoryEnabled {
                MemoryStore.shared.writeContextFile(to: dir)
            } else {
                MemoryStore.shared.removeContextFile(from: dir)
            }
        }
    }

    @objc private func memoryDidChange() {
        guard let dir = contextDirectory, Settings.shared.memoryEnabled else { return }
        MemoryStore.shared.writeContextFile(to: dir)
    }

    // MARK: - Theme (subclass hook)

    override func themeDidChange() {
        terminalView.nativeBackgroundColor = Theme.terminalBg
        terminalView.nativeForegroundColor = Theme.terminalFg
        installAnsiColors()
        terminalView.setNeedsDisplay(terminalView.bounds)
    }

    // MARK: - Title bar

    override func updateTitleBar() {
        let stateLabel = (agentState != .idle) ? agentState.label : nil
        titleProcessLabel.stringValue = stateLabel ?? processTitle ?? paneType.label
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
        guard paneType == .claude && Settings.shared.showActivityIndicators else { return }

        recentByteCount += byteCount

        if byteWindowTimer == nil {
            byteWindowTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                guard let self else { return }
                let bytes = self.recentByteCount
                self.recentByteCount = 0
                self.byteWindowTimer = nil

                if bytes >= self.byteRateThreshold {
                    if !self.isAgentActive {
                        self.isAgentActive = true
                        self.manager?.tabBar?.update()
                    }
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

    // MARK: - Change Log

    func toggleChangeLog() {
        guard paneType == .claude else { return }

        if isChangeLogVisible {
            hideChangeLog()
        } else {
            showChangeLog()
        }
    }

    private func showChangeLog() {
        guard changeLogView == nil else { return }

        let panel = ChangeLogView(frame: .zero)
        panel.onClose = { [weak self] in self?.hideChangeLog() }

        for action in outputParser.actions {
            panel.addAction(action)
        }

        let h = panel.idealHeight()
        let x = clipView.bounds.width - panel.panelWidth - 8
        let y = clipView.bounds.height - h - 8
        panel.frame = NSRect(x: x, y: y, width: panel.panelWidth, height: h)
        panel.alphaValue = 0

        clipView.addSubview(panel)
        changeLogView = panel
        isChangeLogVisible = true

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.Anim.normal
            ctx.timingFunction = Theme.Anim.snappyTimingFunction
            panel.animator().alphaValue = 1
        }
    }

    private func hideChangeLog() {
        guard let panel = changeLogView else { return }
        isChangeLogVisible = false

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Theme.Anim.fast
            ctx.timingFunction = Theme.Anim.snappyTimingFunction
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.removeFromSuperview()
            self?.changeLogView = nil
        })
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

    override func shutdown() {
        if let dir = zdotdir { ShellEnhancer.cleanup(zdotdir: dir) }
        terminalView.terminate()
    }

    // MARK: - Content layout

    override func layoutContent() {
        let pad: CGFloat = 8
        terminalView.frame = CGRect(x: pad, y: titleBarHeight, width: clipView.bounds.width - pad * 2, height: clipView.bounds.height - titleBarHeight - pad)

        // Reposition change log overlay if visible
        if let panel = changeLogView {
            let h = panel.idealHeight()
            let x = clipView.bounds.width - panel.panelWidth - 8
            let y = clipView.bounds.height - h - 8
            panel.frame = NSRect(x: x, y: y, width: panel.panelWidth, height: h)
        }
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let newTitle = title.isEmpty ? nil : title

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
        let paneName = customName ?? processTitle ?? paneType.label
        let paneIdx = manager?.panes.firstIndex(where: { $0 === self }) ?? 0
        FlockNotifications.sendCompletion(paneName: paneName, paneIndex: paneIdx, duration: lastCommandDuration)
    }
}
