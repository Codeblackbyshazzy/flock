import AppKit

enum StartupBehavior: Int {
    case newClaudePane = 0
    case restoreLastSession = 1
}

class Settings {
    static let shared = Settings()
    static let didChange = Notification.Name("FlockSettingsDidChange")

    private let defaults = UserDefaults.standard

    private enum Key: String {
        case fontSize
        case defaultPaneType
        case startupBehavior
        case showActivityIndicators
        case themeId
        case soundEffectsEnabled
        case globalHotkeyEnabled
        case globalHotkeyKeyCode
        case globalHotkeyModifiers
        case maxParallelAgents
    }

    var themeId: String {
        get { defaults.string(forKey: Key.themeId.rawValue) ?? "flock" }
        set { defaults.set(newValue, forKey: Key.themeId.rawValue); post(.themeId) }
    }

    var fontSize: CGFloat {
        get {
            let v = defaults.double(forKey: Key.fontSize.rawValue)
            return v > 0 ? CGFloat(v) : 13
        }
        set { defaults.set(Double(newValue), forKey: Key.fontSize.rawValue); post(.fontSize) }
    }

    var defaultPaneType: PaneType {
        get { defaults.string(forKey: Key.defaultPaneType.rawValue) == "shell" ? .shell : .claude }
        set { defaults.set(newValue == .shell ? "shell" : "claude", forKey: Key.defaultPaneType.rawValue); post(.defaultPaneType) }
    }

    var startupBehavior: StartupBehavior {
        get { StartupBehavior(rawValue: defaults.integer(forKey: Key.startupBehavior.rawValue)) ?? .newClaudePane }
        set { defaults.set(newValue.rawValue, forKey: Key.startupBehavior.rawValue); post(.startupBehavior) }
    }

    var showActivityIndicators: Bool {
        get {
            if defaults.object(forKey: Key.showActivityIndicators.rawValue) == nil { return true }
            return defaults.bool(forKey: Key.showActivityIndicators.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.showActivityIndicators.rawValue); post(.showActivityIndicators) }
    }

    var soundEffectsEnabled: Bool {
        get { defaults.bool(forKey: Key.soundEffectsEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.soundEffectsEnabled.rawValue); post(.soundEffectsEnabled) }
    }

    var globalHotkeyEnabled: Bool {
        get {
            if defaults.object(forKey: Key.globalHotkeyEnabled.rawValue) == nil { return true }
            return defaults.bool(forKey: Key.globalHotkeyEnabled.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.globalHotkeyEnabled.rawValue); post(.globalHotkeyEnabled) }
    }

    var globalHotkeyKeyCode: UInt16 {
        get {
            let v = defaults.integer(forKey: Key.globalHotkeyKeyCode.rawValue)
            return v > 0 ? UInt16(v) : 50  // backtick
        }
        set { defaults.set(Int(newValue), forKey: Key.globalHotkeyKeyCode.rawValue); post(.globalHotkeyKeyCode) }
    }

    var globalHotkeyModifiers: UInt {
        get {
            let v = defaults.integer(forKey: Key.globalHotkeyModifiers.rawValue)
            return v > 0 ? UInt(v) : NSEvent.ModifierFlags.control.rawValue
        }
        set { defaults.set(Int(newValue), forKey: Key.globalHotkeyModifiers.rawValue); post(.globalHotkeyModifiers) }
    }

    var maxParallelAgents: Int {
        get {
            let v = defaults.integer(forKey: Key.maxParallelAgents.rawValue)
            return v > 0 ? v : 3
        }
        set { defaults.set(newValue, forKey: Key.maxParallelAgents.rawValue); post(.maxParallelAgents) }
    }

    // ANSI color overrides per theme
    func customAnsiColors(forTheme themeId: String) -> [Int]? {
        guard let data = defaults.data(forKey: "ansiColors_\(themeId)") else { return nil }
        return try? JSONDecoder().decode([Int].self, from: data)
    }

    func setCustomAnsiColors(_ colors: [Int]?, forTheme themeId: String) {
        if let colors = colors, let data = try? JSONEncoder().encode(colors) {
            defaults.set(data, forKey: "ansiColors_\(themeId)")
        } else {
            defaults.removeObject(forKey: "ansiColors_\(themeId)")
        }
        NotificationCenter.default.post(name: Theme.themeDidChange, object: nil)
    }

    private func post(_ key: Key) {
        NotificationCenter.default.post(name: Settings.didChange, object: nil, userInfo: ["key": key.rawValue])
    }
}
