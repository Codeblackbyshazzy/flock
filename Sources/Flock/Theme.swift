import AppKit

// MARK: - Color Theme Definition

struct ColorTheme {
    let id: String
    let name: String

    // Surfaces
    let chrome: NSColor
    let surface: NSColor
    let hover: NSColor
    let divider: NSColor

    // Focus
    let borderRest: NSColor
    let borderFocus: NSColor

    // Accent
    let accent: NSColor
    let accentSubtle: NSColor

    // Text
    let textPrimary: NSColor
    let textSecondary: NSColor
    let textTertiary: NSColor

    // Terminal
    let terminalBg: NSColor
    let terminalFg: NSColor

    // ANSI 16-color palette
    let ansiHex: [Int]
}

// MARK: - Built-in Themes

enum Themes {
    static let all: [ColorTheme] = [flock, claude, midnight, overcast, linen]

    // The original warm cream
    static let flock = ColorTheme(
        id: "flock", name: "Flock",
        chrome:        NSColor(hex: 0xE8E3DA),
        surface:       NSColor(hex: 0xF7F4ED),
        hover:         NSColor(hex: 0xE2DDD3),
        divider:       NSColor(hex: 0xD9D3C8),
        borderRest:    NSColor(hex: 0xD4CEC3),
        borderFocus:   NSColor(hex: 0xB8B0A3),
        accent:        NSColor(hex: 0x9B8574),
        accentSubtle:  NSColor(hex: 0x9B8574, alpha: 0x26),
        textPrimary:   NSColor(hex: 0x2C2520),
        textSecondary: NSColor(hex: 0x6A6560),
        textTertiary:  NSColor(hex: 0x8A857E),
        terminalBg:    NSColor(hex: 0xFAF7F0),
        terminalFg:    NSColor(hex: 0x2C2520),
        ansiHex: [
            0x2C2520, 0xC75450, 0x5B9A6B, 0x9B7B2C,
            0x5B7FA5, 0xA8727E, 0x6A9DAD, 0xE8E3DA,
            0x7A7168, 0xD97B76, 0x7BB585, 0xD4AD56,
            0x7A9EC4, 0xC19BA5, 0x8CBFCC, 0xF7F4ED,
        ]
    )

    // Claude cream -- warm parchment, terracotta accent
    static let claude = ColorTheme(
        id: "claude", name: "Claude",
        chrome:        NSColor(hex: 0xE9E0D1),
        surface:       NSColor(hex: 0xF5EFE4),
        hover:         NSColor(hex: 0xDED6C8),
        divider:       NSColor(hex: 0xD3CABB),
        borderRest:    NSColor(hex: 0xCCC2B1),
        borderFocus:   NSColor(hex: 0xA89A89),
        accent:        NSColor(hex: 0xB5524A),
        accentSubtle:  NSColor(hex: 0xB5524A, alpha: 0x26),
        textPrimary:   NSColor(hex: 0x30261E),
        textSecondary: NSColor(hex: 0x6D6356),
        textTertiary:  NSColor(hex: 0x8D8475),
        terminalBg:    NSColor(hex: 0xF8F2E8),
        terminalFg:    NSColor(hex: 0x30261E),
        ansiHex: [
            0x30261E, 0xB5524A, 0x5A8F61, 0xB89840,
            0x5D7FA0, 0x96717E, 0x5E949E, 0xE9E0D1,
            0x7D7063, 0xCC7A72, 0x7AAD7D, 0xCBB265,
            0x7D9DBF, 0xB5929E, 0x7FB5BE, 0xF5EFE4,
        ]
    )

    // Dark mode -- warm near-black
    static let midnight = ColorTheme(
        id: "midnight", name: "Midnight",
        chrome:        NSColor(hex: 0x1A1918),
        surface:       NSColor(hex: 0x252321),
        hover:         NSColor(hex: 0x33302D),
        divider:       NSColor(hex: 0x302D2A),
        borderRest:    NSColor(hex: 0x3E3A36),
        borderFocus:   NSColor(hex: 0x5C5550),
        accent:        NSColor(hex: 0x6A9FD4),
        accentSubtle:  NSColor(hex: 0x6A9FD4, alpha: 0x26),
        textPrimary:   NSColor(hex: 0xE8E4DE),
        textSecondary: NSColor(hex: 0xA09890),
        textTertiary:  NSColor(hex: 0x706860),
        terminalBg:    NSColor(hex: 0x1C1A19),
        terminalFg:    NSColor(hex: 0xE8E4DE),
        ansiHex: [
            0x1A1918, 0xD4655E, 0x6BBF7A, 0xD4B94E,
            0x6A9FD4, 0xA87EC4, 0x72B8CC, 0xE8E4DE,
            0x635C55, 0xE08A84, 0x85CC8A, 0xDCC86E,
            0x85B3D9, 0xBFA0D4, 0x8FC5D9, 0xE8E4DE,
        ]
    )

    // Cool grey -- fog blue undertone
    static let overcast = ColorTheme(
        id: "overcast", name: "Overcast",
        chrome:        NSColor(hex: 0xE2E5EA),
        surface:       NSColor(hex: 0xEFF1F4),
        hover:         NSColor(hex: 0xD8DCE2),
        divider:       NSColor(hex: 0xCDD1D8),
        borderRest:    NSColor(hex: 0xC4C9D1),
        borderFocus:   NSColor(hex: 0xA3A9B4),
        accent:        NSColor(hex: 0x5580B5),
        accentSubtle:  NSColor(hex: 0x5580B5, alpha: 0x26),
        textPrimary:   NSColor(hex: 0x1E2228),
        textSecondary: NSColor(hex: 0x555D6A),
        textTertiary:  NSColor(hex: 0x7D8494),
        terminalBg:    NSColor(hex: 0xF0F2F5),
        terminalFg:    NSColor(hex: 0x1E2228),
        ansiHex: [
            0x1E2228, 0xC45462, 0x5A9A6E, 0xBFA04A,
            0x5580B5, 0x8B7AAD, 0x5EAAB8, 0xE2E5EA,
            0x5A6170, 0xD4808A, 0x7AB88C, 0xCCB562,
            0x7098C4, 0xA498BF, 0x78BDCC, 0xEFF1F4,
        ]
    )

    // True sunlit light theme
    static let linen = ColorTheme(
        id: "linen", name: "Linen",
        chrome:        NSColor(hex: 0xF0EEEB),
        surface:       NSColor(hex: 0xFBFAF8),
        hover:         NSColor(hex: 0xE9E7E3),
        divider:       NSColor(hex: 0xE3E1DC),
        borderRest:    NSColor(hex: 0xDDD9D4),
        borderFocus:   NSColor(hex: 0xB5AFA7),
        accent:        NSColor(hex: 0x7A8A7A),
        accentSubtle:  NSColor(hex: 0x7A8A7A, alpha: 0x26),
        textPrimary:   NSColor(hex: 0x2C2B28),
        textSecondary: NSColor(hex: 0x6A6662),
        textTertiary:  NSColor(hex: 0x8A8680),
        terminalBg:    NSColor(hex: 0xFBFAF8),
        terminalFg:    NSColor(hex: 0x2C2B28),
        ansiHex: [
            0x2C2B28, 0xC93D37, 0x3A7D44, 0x9B7B2C,
            0x2E6BB5, 0x9B4D96, 0x2B8A7E, 0xE9E7E3,
            0x7A766F, 0xE05550, 0x4E9A5A, 0xB8962E,
            0x4A8AD4, 0xB86DB2, 0x3BAFA1, 0xFBFAF8,
        ]
    )
}

// MARK: - Theme (static accessors backed by active theme)

struct Theme {
    private static var _active: ColorTheme = Themes.flock

    static var active: ColorTheme {
        get { _active }
        set {
            let window = NSApp.windows.first
            if let window {
                crossDissolve(in: window, duration: 0.25)
            }
            _active = newValue
            NotificationCenter.default.post(name: themeDidChange, object: nil)
        }
    }

    /// Captures a snapshot of the window content, updates theme underneath,
    /// then fades the snapshot to reveal the new theme.
    static func crossDissolve(in window: NSWindow, duration: TimeInterval) {
        guard let contentView = window.contentView,
              let contentLayer = contentView.layer else { return }

        // Capture snapshot of current appearance
        let bounds = contentLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let scale = window.backingScaleFactor
        let pixelW = Int(bounds.width * scale)
        let pixelH = Int(bounds.height * scale)
        guard pixelW > 0, pixelH > 0 else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return }

        ctx.scaleBy(x: scale, y: scale)
        contentLayer.render(in: ctx)

        guard let cgImage = ctx.makeImage() else { return }

        // Create overlay layer with the snapshot
        let snapshotLayer = CALayer()
        snapshotLayer.frame = bounds
        snapshotLayer.contents = cgImage
        snapshotLayer.contentsGravity = .resizeAspectFill
        snapshotLayer.contentsScale = scale
        snapshotLayer.zPosition = 10000
        contentLayer.addSublayer(snapshotLayer)

        // Fade the snapshot out to reveal the updated theme
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock {
            snapshotLayer.removeFromSuperlayer()
        }
        snapshotLayer.opacity = 0
        CATransaction.commit()
    }

    static let themeDidChange = Notification.Name("FlockThemeDidChange")

    // Surfaces
    static var chrome:      NSColor { active.chrome }
    static var surface:     NSColor { active.surface }
    static var hover:       NSColor { active.hover }
    static var divider:     NSColor { active.divider }

    // Focus
    static var borderRest:  NSColor { active.borderRest }
    static var borderFocus: NSColor { active.borderFocus }

    // Accent
    static var accent:       NSColor { active.accent }
    static var accentSubtle: NSColor { active.accentSubtle }

    // Text
    static var textPrimary:   NSColor { active.textPrimary }
    static var textSecondary: NSColor { active.textSecondary }
    static var textTertiary:  NSColor { active.textTertiary }

    // Terminal
    static var terminalBg: NSColor { active.terminalBg }
    static var terminalFg: NSColor { active.terminalFg }

    // Status
    static let statusGreen = NSColor(hex: 0x5B9A6B)
    static let statusRed   = NSColor(hex: 0xC75450)

    // ANSI (with per-theme custom overrides)
    static var ansiHex: [Int] { Settings.shared.customAnsiColors(forTheme: active.id) ?? active.ansiHex }

    // MARK: - Spacing System (4px base)

    enum Space {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Layout

    static let tabBarHeight:  CGFloat = 16
    static let statusHeight:  CGFloat = 24
    static let paneGap:       CGFloat = Space.sm
    static let panePadding:   CGFloat = Space.lg
    static let paneRadius:    CGFloat = 10

    // MARK: - Animation

    enum Anim {
        static let fast:   TimeInterval = 0.12
        static let normal: TimeInterval = 0.2
        static let slow:   TimeInterval = 0.35

        static var snappyTimingFunction: CAMediaTimingFunction {
            CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.5, 1.0)
        }
    }

    // MARK: - Accessibility

    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - Typography

    enum Typo {
        static let searchInput   = NSFont.systemFont(ofSize: 16, weight: .medium)
        static let body          = NSFont.systemFont(ofSize: 13, weight: .regular)
        static let tabActive     = NSFont.systemFont(ofSize: 13, weight: .semibold)
        static let tabRest       = NSFont.systemFont(ofSize: 13, weight: .regular)
        static let button        = NSFont.systemFont(ofSize: 12, weight: .medium)
        static let status        = NSFont.systemFont(ofSize: 11, weight: .regular)
        static let caption       = NSFont.systemFont(ofSize: 11, weight: .regular)
        static let sectionHeader = NSFont.systemFont(ofSize: 10, weight: .semibold)
        static let brand         = NSFont.systemFont(ofSize: 11, weight: .medium)
        static let badge         = NSFont.boldSystemFont(ofSize: 9)
        static let monoSmall     = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        static let monoDigit     = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        static let brandKern: CGFloat = 1.2
    }

    // MARK: - Formatters

    static func formatElapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Shadows

    struct ShadowConfig {
        let opacity: Float
        let radius: CGFloat
        let offset: CGSize
    }

    enum Shadow {
        enum Rest {
            static let contact = ShadowConfig(opacity: 0.06, radius: 3, offset: CGSize(width: 0, height: 1))
            static let ambient = ShadowConfig(opacity: 0.05, radius: 12, offset: CGSize(width: 0, height: 3))
        }
        enum Focus {
            static let contact = ShadowConfig(opacity: 0.12, radius: 4, offset: CGSize(width: 0, height: 1.5))
            static let ambient = ShadowConfig(opacity: 0.10, radius: 24, offset: CGSize(width: 0, height: 10))
        }
    }
}

extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green:   CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue:    CGFloat(hex & 0xFF) / 255.0,
            alpha:   1.0
        )
    }

    convenience init(hex: Int, alpha: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green:   CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue:    CGFloat(hex & 0xFF) / 255.0,
            alpha:   CGFloat(alpha) / 255.0
        )
    }
}

// MARK: - AgentActionType badge colors (UI extension, kept out of model layer)

extension AgentActionType {
    var badgeColor: NSColor {
        switch self {
        case .think:   return Theme.textTertiary
        case .read:    return Theme.accent.blended(withFraction: 0.4, of: Theme.textSecondary) ?? Theme.accent
        case .edit:    return Theme.accent
        case .write:   return Theme.accent
        case .bash:    return Theme.textPrimary.withAlphaComponent(0.8)
        case .search:  return Theme.textSecondary
        case .agent:   return Theme.accent.withAlphaComponent(0.7)
        case .web:     return Theme.textSecondary
        case .message: return Theme.accent
        }
    }
}
