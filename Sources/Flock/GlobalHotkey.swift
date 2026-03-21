import AppKit

class GlobalHotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var window: NSWindow?

    var keyCode: UInt16 = 50  // backtick
    var modifiers: NSEvent.ModifierFlags = .control
    var isEnabled: Bool = true

    init(window: NSWindow) {
        self.window = window
        register()
    }

    func register() {
        unregister()

        // Fires when Flock is NOT the frontmost app
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isEnabled, self.matchesHotkey(event) else { return }
            self.toggleWindow()
        }

        // Fires when Flock IS the frontmost app — return nil to consume the event
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isEnabled, self.matchesHotkey(event) else { return event }
            self.toggleWindow()
            return nil
        }
    }

    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func matchesHotkey(_ event: NSEvent) -> Bool {
        let deviceIndependent = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == keyCode && deviceIndependent == modifiers
    }

    private func toggleWindow() {
        if NSApp.isActive && window?.isVisible == true {
            NSApp.hide(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    deinit {
        unregister()
    }
}
