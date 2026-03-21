import Cocoa
import WebKit

class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ n: Notification) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
        let w = min(1400, screen.width * 0.88)
        let h = min(920, screen.height * 0.88)
        let x = screen.origin.x + (screen.width - w) / 2
        let y = screen.origin.y + (screen.height - h) / 2

        window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Flock"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.96, green: 0.95, blue: 0.94, alpha: 1)
        window.minSize = NSSize(width: 600, height: 400)
        window.setFrameAutosaveName("FlockWindow")

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let wv = WKWebView(frame: window.contentView!.bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")
        wv.load(URLRequest(url: URL(string: "http://localhost:7681")!))

        window.contentView!.addSubview(wv)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let d = Delegate()
app.delegate = d
app.run()
