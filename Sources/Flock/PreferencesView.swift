import AppKit

class PreferencesView: NSView {

    override var isFlipped: Bool { true }

    // MARK: - Controls

    private let themeControl = NSSegmentedControl()
    private let fontSizeSlider = NSSlider()
    private let fontSizeLabel = NSTextField(labelWithString: "")
    private let paneTypeControl = NSSegmentedControl()
    private let launchControl = NSSegmentedControl()
    private let activitySwitch = NSSwitch()
    private let soundSwitch = NSSwitch()
    private let memorySwitch = NSSwitch()
    private let usageSwitch = NSSwitch()
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    // MARK: - Layout Constants

    private let panelWidth: CGFloat = 480
    private let panelHeight: CGFloat = 512
    private let labelX: CGFloat = 24
    private let controlX: CGFloat = 160
    private let controlWidth: CGFloat = 200
    private let rowHeight: CGFloat = 32
    private let sectionGap: CGFloat = 28
    private let sectionHeaderHeight: CGFloat = 20

    // MARK: - Show

    static func show(on window: NSWindow) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 512),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        panel.title = "Preferences"
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false

        let view = PreferencesView(frame: NSRect(x: 0, y: 0, width: 480, height: 512))
        view.panel = panel
        view.hostWindow = window
        panel.contentView = view

        window.beginSheet(panel)
    }

    // MARK: - Internal refs

    private weak var panel: NSPanel?
    private weak var hostWindow: NSWindow?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.chrome.cgColor
        setupControls()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupControls() {
        let settings = Settings.shared

        var y: CGFloat = 20

        // ── Appearance ──
        y = addSectionHeader("Appearance", y: y)

        // Theme
        y = addRow(y: y)
        addLabel("Theme", y: y)

        let themes = Themes.all
        themeControl.segmentCount = themes.count
        for (i, t) in themes.enumerated() {
            themeControl.setLabel(t.name, forSegment: i)
            if t.id == Settings.shared.themeId { themeControl.selectedSegment = i }
        }
        themeControl.segmentStyle = .rounded
        themeControl.target = self
        themeControl.action = #selector(themeChanged(_:))
        themeControl.frame = NSRect(x: controlX, y: y + 2, width: controlWidth + 60, height: 24)
        addSubview(themeControl)

        y += rowHeight

        // ── Terminal ──
        y += sectionGap - rowHeight
        y = addSectionHeader("Terminal", y: y)

        // Font Size
        y = addRow(y: y)
        addLabel("Font Size", y: y)

        fontSizeSlider.minValue = 11
        fontSizeSlider.maxValue = 18
        fontSizeSlider.isContinuous = true
        fontSizeSlider.doubleValue = Double(settings.fontSize)
        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(fontSizeChanged(_:))
        fontSizeSlider.frame = NSRect(x: controlX, y: y + 4, width: controlWidth, height: 20)
        addSubview(fontSizeSlider)

        fontSizeLabel.font = Theme.Typo.status
        fontSizeLabel.textColor = Theme.textSecondary
        fontSizeLabel.alignment = .left
        fontSizeLabel.stringValue = "\(Int(settings.fontSize)) pt"
        fontSizeLabel.frame = NSRect(x: controlX + controlWidth + 8, y: y + 4, width: 50, height: 20)
        addSubview(fontSizeLabel)

        y += rowHeight

        // ── Behavior ──
        y += sectionGap - rowHeight
        y = addSectionHeader("Behavior", y: y)

        // Default Pane
        y = addRow(y: y)
        addLabel("Default Pane", y: y)

        paneTypeControl.segmentCount = 2
        paneTypeControl.setLabel("Claude", forSegment: 0)
        paneTypeControl.setLabel("Shell", forSegment: 1)
        paneTypeControl.segmentStyle = .rounded
        paneTypeControl.selectedSegment = settings.defaultPaneType == .claude ? 0 : 1
        paneTypeControl.target = self
        paneTypeControl.action = #selector(paneTypeChanged(_:))
        paneTypeControl.frame = NSRect(x: controlX, y: y + 2, width: controlWidth, height: 24)
        addSubview(paneTypeControl)

        y += rowHeight

        // On Launch
        y = addRow(y: y)
        addLabel("On Launch", y: y)

        launchControl.segmentCount = 2
        launchControl.setLabel("New Claude Pane", forSegment: 0)
        launchControl.setLabel("Restore Last Session", forSegment: 1)
        launchControl.segmentStyle = .rounded
        launchControl.selectedSegment = settings.startupBehavior.rawValue
        // Session restore is now functional
        launchControl.target = self
        launchControl.action = #selector(launchChanged(_:))
        launchControl.frame = NSRect(x: controlX, y: y + 2, width: controlWidth + 60, height: 24)
        addSubview(launchControl)

        y += rowHeight

        // ── Indicators ──
        y += sectionGap - rowHeight
        y = addSectionHeader("Indicators", y: y)

        // Activity Dots
        y = addRow(y: y)
        addLabel("Activity Dots", y: y)

        activitySwitch.state = settings.showActivityIndicators ? .on : .off
        activitySwitch.target = self
        activitySwitch.action = #selector(activityChanged(_:))
        activitySwitch.frame = NSRect(x: controlX, y: y + 2, width: 38, height: 22)
        addSubview(activitySwitch)

        y += rowHeight

        // Sound Effects
        y = addRow(y: y)
        addLabel("Sound Effects", y: y)

        soundSwitch.state = settings.soundEffectsEnabled ? .on : .off
        soundSwitch.target = self
        soundSwitch.action = #selector(soundChanged(_:))
        soundSwitch.frame = NSRect(x: controlX, y: y + 2, width: 38, height: 22)
        addSubview(soundSwitch)

        y += rowHeight

        // Usage Tracker
        y = addRow(y: y)
        addLabel("Usage Tracker", y: y)

        usageSwitch.state = settings.showUsageTracker ? .on : .off
        usageSwitch.target = self
        usageSwitch.action = #selector(usageChanged(_:))
        usageSwitch.frame = NSRect(x: controlX, y: y + 2, width: 38, height: 22)
        addSubview(usageSwitch)

        let usageHint = NSTextField(labelWithString: "Show today's cost + tokens in status bar")
        usageHint.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        usageHint.textColor = Theme.textTertiary
        usageHint.frame = NSRect(x: controlX + 48, y: y + 5, width: 240, height: 14)
        addSubview(usageHint)

        y += rowHeight

        // ── Memory ──
        y += sectionGap - rowHeight
        y = addSectionHeader("Memory", y: y)

        y = addRow(y: y)
        addLabel("AI Memory", y: y)

        memorySwitch.state = settings.memoryEnabled ? .on : .off
        memorySwitch.target = self
        memorySwitch.action = #selector(memoryChanged(_:))
        memorySwitch.frame = NSRect(x: controlX, y: y + 2, width: 38, height: 22)
        addSubview(memorySwitch)

        let memoryHint = NSTextField(labelWithString: "Auto-captures task summaries, writes .flock-context.md")
        memoryHint.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        memoryHint.textColor = Theme.textTertiary
        memoryHint.frame = NSRect(x: controlX + 48, y: y + 5, width: 240, height: 14)
        addSubview(memoryHint)

        y += rowHeight

        // ── Done Button ──
        let btnWidth: CGFloat = 72
        let btnHeight: CGFloat = 28
        let btnX = panelWidth - btnWidth - 24
        let btnY = panelHeight - btnHeight - 20

        doneButton.frame = NSRect(x: btnX, y: btnY, width: btnWidth, height: btnHeight)
        doneButton.bezelStyle = .rounded
        doneButton.isBordered = false
        doneButton.wantsLayer = true
        doneButton.layer?.backgroundColor = Theme.surface.cgColor
        doneButton.layer?.borderColor = Theme.divider.cgColor
        doneButton.layer?.borderWidth = 1
        doneButton.layer?.cornerRadius = 6
        doneButton.font = Theme.Typo.button
        doneButton.contentTintColor = Theme.textPrimary
        doneButton.target = self
        doneButton.action = #selector(done(_:))
        doneButton.keyEquivalent = "\r"
        addSubview(doneButton)
    }

    // MARK: - Layout Helpers

    @discardableResult
    private func addSectionHeader(_ title: String, y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = Theme.textSecondary
        label.frame = NSRect(x: labelX, y: y, width: panelWidth - labelX * 2, height: sectionHeaderHeight)
        addSubview(label)
        return y + sectionHeaderHeight + 8
    }

    private func addRow(y: CGFloat) -> CGFloat {
        return y
    }

    private func addLabel(_ text: String, y: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        label.textColor = Theme.textPrimary
        label.alignment = .right
        label.frame = NSRect(x: labelX, y: y + 4, width: controlX - labelX - 16, height: 20)
        addSubview(label)
    }

    // MARK: - Actions

    @objc private func themeChanged(_ sender: NSSegmentedControl) {
        let themes = Themes.all
        guard sender.selectedSegment >= 0, sender.selectedSegment < themes.count else { return }
        let theme = themes[sender.selectedSegment]
        Settings.shared.themeId = theme.id
        Theme.active = theme
    }

    @objc private func fontSizeChanged(_ sender: NSSlider) {
        let value = CGFloat(round(sender.doubleValue))
        sender.doubleValue = Double(value)
        Settings.shared.fontSize = value
        fontSizeLabel.stringValue = "\(Int(value)) pt"
    }

    @objc private func paneTypeChanged(_ sender: NSSegmentedControl) {
        Settings.shared.defaultPaneType = sender.selectedSegment == 0 ? .claude : .shell
    }

    @objc private func launchChanged(_ sender: NSSegmentedControl) {
        if let behavior = StartupBehavior(rawValue: sender.selectedSegment) {
            Settings.shared.startupBehavior = behavior
        }
    }

    @objc private func activityChanged(_ sender: NSSwitch) {
        Settings.shared.showActivityIndicators = (sender.state == .on)
    }

    @objc private func soundChanged(_ sender: NSSwitch) {
        Settings.shared.soundEffectsEnabled = (sender.state == .on)
    }

    @objc private func usageChanged(_ sender: NSSwitch) {
        Settings.shared.showUsageTracker = (sender.state == .on)
    }

    @objc private func memoryChanged(_ sender: NSSwitch) {
        Settings.shared.memoryEnabled = (sender.state == .on)
    }

    @objc private func done(_ sender: Any) {
        guard let panel = panel, let host = hostWindow else { return }
        host.endSheet(panel)
    }
}
