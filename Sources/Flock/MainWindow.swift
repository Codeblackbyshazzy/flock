import AppKit

class FlockWindow: NSWindow {
    let paneManager: PaneManager
    let tabBar: TabBarView
    let gridContainer: GridContainer
    let statusBar: StatusBarView
    let rootView: FlockRootView

    init(paneManager: PaneManager) {
        self.paneManager = paneManager
        self.tabBar = TabBarView(paneManager: paneManager)
        self.gridContainer = GridContainer(paneManager: paneManager)
        self.statusBar = StatusBarView(paneManager: paneManager)
        self.rootView = FlockRootView()

        // Screen-relative sizing: 80% of main screen
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = floor(screen.width * 0.8)
        let h = floor(screen.height * 0.8)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        paneManager.tabBar = tabBar
        paneManager.gridContainer = gridContainer
        paneManager.statusBar = statusBar

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        titlebarSeparatorStyle = .none
        backgroundColor = Theme.chrome
        minSize = NSSize(width: 600, height: 400)
        title = "Flock"
        center()

        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: Theme.themeDidChange, object: nil)

        rootView.tabBar = tabBar
        rootView.gridContainer = gridContainer
        rootView.statusBar = statusBar
        rootView.addSubview(tabBar)
        rootView.addSubview(gridContainer)
        rootView.addSubview(statusBar)
        contentView = rootView
    }

    @objc private func themeChanged() {
        backgroundColor = Theme.chrome
    }
}

class FlockRootView: NSView {
    weak var tabBar: NSView?
    weak var gridContainer: NSView?
    weak var statusBar: NSView?

    override var isFlipped: Bool { true }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let w = bounds.width
        let h = bounds.height
        let tabH = Theme.tabBarHeight
        let statusH = Theme.statusHeight

        tabBar?.frame       = NSRect(x: 0, y: 0, width: w, height: tabH)
        gridContainer?.frame = NSRect(x: 0, y: tabH, width: w, height: h - tabH - statusH)
        statusBar?.frame    = NSRect(x: 0, y: h - statusH, width: w, height: statusH)
    }
}
