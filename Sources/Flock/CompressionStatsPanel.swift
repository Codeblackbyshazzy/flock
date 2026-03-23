import AppKit

class CompressionStatsPanel: NSView {

    override var isFlipped: Bool { true }

    private weak var panel: NSPanel?
    private weak var hostWindow: NSWindow?
    private weak var paneManager: PaneManager?

    private let panelWidth: CGFloat = 440
    private let panelHeight: CGFloat = 480

    // Refresh timer
    private var refreshTimer: Timer?

    // Drawn content (updated on refresh)
    private var sessionStats = CompressionStats()
    private var perPaneStats: [(name: String, stats: CompressionStats)] = []

    // MARK: - Show

    static func show(on window: NSWindow, paneManager: PaneManager) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        panel.title = "Compression Stats"
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false

        let view = CompressionStatsPanel(frame: NSRect(x: 0, y: 0, width: 440, height: 480))
        view.panel = panel
        view.hostWindow = window
        view.paneManager = paneManager
        panel.contentView = view

        view.refreshStats()
        view.startRefreshTimer()

        window.beginSheet(panel) { _ in
            view.cleanup()
        }
    }

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Cleanup

    private func cleanup() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func dismiss() {
        cleanup()
        if let panel, let hostWindow {
            hostWindow.endSheet(panel)
        }
    }

    // MARK: - Refresh

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStats()
        }
    }

    private func refreshStats() {
        guard let mgr = paneManager else { return }

        let allStats = mgr.panes.map { $0.compressor.stats }
        sessionStats = CompressionStats.aggregate(allStats)

        perPaneStats = mgr.panes.enumerated().map { (i, pane) in
            let name = pane.customName ?? pane.processTitle ?? "\(pane.type.label) \(i + 1)"
            return (name: name, stats: pane.compressor.stats)
        }

        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Background
        Theme.chrome.setFill()
        bounds.fill()

        let pad: CGFloat = 24
        var y: CGFloat = 20

        // -- Hero number --
        let tokensSaved = sessionStats.tokensSaved
        let heroStr = formatNumber(tokensSaved)

        let heroAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 42, weight: .bold),
            .foregroundColor: tokensSaved > 0 ? NSColor(hex: 0x30D158) : Theme.textTertiary,
        ]
        let heroText = NSAttributedString(string: heroStr, attributes: heroAttrs)
        let heroSize = heroText.size()
        heroText.draw(at: NSPoint(x: (bounds.width - heroSize.width) / 2, y: y))
        y += heroSize.height + 4

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: Theme.textTertiary,
        ]
        let subtitleText = NSAttributedString(string: "tokens saved this session", attributes: subtitleAttrs)
        let subtitleSize = subtitleText.size()
        subtitleText.draw(at: NSPoint(x: (bounds.width - subtitleSize.width) / 2, y: y))
        y += subtitleSize.height + 6

        // Compression percentage pill
        let pct = sessionStats.percentSaved
        if sessionStats.rawBytes > 0 {
            let pctStr = "\(pct)% compression"
            let pillAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: pct >= 20 ? NSColor(hex: 0x30D158) : Theme.textSecondary,
            ]
            let pillText = NSAttributedString(string: pctStr, attributes: pillAttrs)
            let pillSize = pillText.size()
            let pillPadH: CGFloat = 10
            let pillPadV: CGFloat = 4
            let pillRect = NSRect(
                x: (bounds.width - pillSize.width - pillPadH * 2) / 2,
                y: y,
                width: pillSize.width + pillPadH * 2,
                height: pillSize.height + pillPadV * 2
            )
            let pillColor = pct >= 20 ? NSColor(hex: 0x30D158).withAlphaComponent(0.12) : Theme.hover
            pillColor.setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8).fill()
            pillText.draw(at: NSPoint(x: pillRect.minX + pillPadH, y: pillRect.minY + pillPadV))
            y += pillRect.height
        }
        y += 20

        // -- Divider --
        Theme.divider.setFill()
        NSRect(x: pad, y: y, width: bounds.width - pad * 2, height: 1).fill()
        y += 16

        // -- Category breakdown --
        y = drawSectionHeader("Breakdown", at: y, pad: pad)
        y += 4

        let categories: [(String, Int, NSColor)] = [
            ("ANSI Noise", sessionStats.noiseTokens, NSColor(hex: 0x8A857E)),
            ("Progress Bars", sessionStats.progressBarTokens, NSColor(hex: 0x5B9A6B)),
            ("Boilerplate", sessionStats.boilerplateTokens, NSColor(hex: 0x5B7FA5)),
            ("Semantic Folds", sessionStats.semanticFoldTokens, NSColor(hex: 0xA8727E)),
        ]

        let barMaxWidth = bounds.width - pad * 2 - 160
        let maxTokens = max(1, categories.map(\.1).max() ?? 1)

        for (label, tokens, color) in categories {
            y = drawCategoryRow(label: label, tokens: tokens, color: color,
                                maxTokens: maxTokens, barMaxWidth: barMaxWidth,
                                at: y, pad: pad)
        }

        y += 8

        // Total processed
        let totalAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: Theme.textTertiary,
        ]
        let totalStr = "\(formatNumber(sessionStats.tokensTotal)) total tokens processed  |  \(sessionStats.errorLines) error lines preserved"
        let totalText = NSAttributedString(string: totalStr, attributes: totalAttrs)
        totalText.draw(at: NSPoint(x: pad, y: y))
        y += 20

        // -- Divider --
        Theme.divider.setFill()
        NSRect(x: pad, y: y, width: bounds.width - pad * 2, height: 1).fill()
        y += 16

        // -- Per-pane breakdown --
        y = drawSectionHeader("Per Pane", at: y, pad: pad)
        y += 4

        if perPaneStats.isEmpty {
            let noDataAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: Theme.textTertiary,
            ]
            NSAttributedString(string: "No active panes", attributes: noDataAttrs)
                .draw(at: NSPoint(x: pad, y: y))
        } else {
            for (name, stats) in perPaneStats {
                y = drawPaneRow(name: name, stats: stats, at: y, pad: pad)
            }
        }
    }

    // MARK: - Drawing Helpers

    private func drawSectionHeader(_ title: String, at y: CGFloat, pad: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.Typo.sectionHeader,
            .foregroundColor: Theme.textTertiary,
            .kern: 1.0,
        ]
        let text = NSAttributedString(string: title.uppercased(), attributes: attrs)
        text.draw(at: NSPoint(x: pad, y: y))
        return y + text.size().height + 4
    }

    private func drawCategoryRow(label: String, tokens: Int, color: NSColor,
                                  maxTokens: Int, barMaxWidth: CGFloat,
                                  at y: CGFloat, pad: CGFloat) -> CGFloat {
        let rowH: CGFloat = 24

        // Label
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: Theme.textSecondary,
        ]
        let labelText = NSAttributedString(string: label, attributes: labelAttrs)
        labelText.draw(at: NSPoint(x: pad, y: y + 3))

        // Token count
        let countAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: Theme.textPrimary,
        ]
        let countStr = formatNumber(tokens)
        let countText = NSAttributedString(string: countStr, attributes: countAttrs)
        let countSize = countText.size()
        let barX = pad + 120
        countText.draw(at: NSPoint(x: barX, y: y + 3))

        // Bar
        let barStartX = barX + countSize.width + 8
        let barWidth = tokens > 0 ? max(4, barMaxWidth * CGFloat(tokens) / CGFloat(maxTokens)) : 0
        let barY = y + 7
        let barH: CGFloat = 10

        // Background track
        Theme.hover.setFill()
        NSBezierPath(roundedRect: NSRect(x: barStartX, y: barY, width: barMaxWidth, height: barH),
                     xRadius: 3, yRadius: 3).fill()

        // Filled bar
        if barWidth > 0 {
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: barStartX, y: barY, width: barWidth, height: barH),
                         xRadius: 3, yRadius: 3).fill()
        }

        return y + rowH
    }

    private func drawPaneRow(name: String, stats: CompressionStats, at y: CGFloat, pad: CGFloat) -> CGFloat {
        let rowH: CGFloat = 22

        // Pane name
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: Theme.textSecondary,
        ]
        let nameText = NSAttributedString(string: name, attributes: nameAttrs)
        nameText.draw(at: NSPoint(x: pad, y: y + 2))

        // Stats
        let saved = stats.tokensSaved
        let pct = stats.percentSaved
        let statsStr = saved > 0 ? "\(formatNumber(saved)) tokens (\(pct)%)" : "No data"
        let statsAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: saved > 0 ? Theme.textPrimary : Theme.textTertiary,
        ]
        let statsText = NSAttributedString(string: statsStr, attributes: statsAttrs)
        let statsSize = statsText.size()
        statsText.draw(at: NSPoint(x: bounds.width - pad - statsSize.width, y: y + 2))

        return y + rowH
    }

    // MARK: - Formatting

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
