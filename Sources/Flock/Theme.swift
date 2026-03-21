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
    static let all: [ColorTheme] = [flock, claude, midnight, overcast]

    // The original warm cream
    static let flock = ColorTheme(
        id: "flock", name: "Flock",
        chrome:        NSColor(hex: 0xEDECE8),
        surface:       NSColor(hex: 0xFAFAF7),
        hover:         NSColor(hex: 0xE5E4E0),
        divider:       NSColor(hex: 0xE0DED8),
        borderRest:    NSColor(hex: 0xDBD9D3),
        borderFocus:   NSColor(hex: 0xC5C3BC),
        textPrimary:   NSColor(hex: 0x1A1A1C),
        textSecondary: NSColor(hex: 0x6E6E73),
        textTertiary:  NSColor(hex: 0xAEAEB2),
        terminalBg:    NSColor(hex: 0xFAFAF7),
        terminalFg:    NSColor(hex: 0x1A1A1C),
        ansiHex: [
            0x1D1D1F, 0xFF3B30, 0x28CD41, 0xFF9500,
            0x007AFF, 0xC4727A, 0x59ADC4, 0xE5E5EA,
            0x6E6E73, 0xFF6961, 0x5AD85C, 0xFFB340,
            0x409CFF, 0xD99BA1, 0x7CD4FC, 0xFAFAFA,
        ]
    )

    // Claude cream — warm parchment, soft blue accents, no orange
    static let claude = ColorTheme(
        id: "claude", name: "Claude",
        chrome:        NSColor(hex: 0xF0EDE6),
        surface:       NSColor(hex: 0xFAF9F5),
        hover:         NSColor(hex: 0xE8E4DC),
        divider:       NSColor(hex: 0xDDD9D0),
        borderRest:    NSColor(hex: 0xD5D0C7),
        borderFocus:   NSColor(hex: 0xB8B0A4),
        textPrimary:   NSColor(hex: 0x1B1714),
        textSecondary: NSColor(hex: 0x6B6560),
        textTertiary:  NSColor(hex: 0xA8A29C),
        terminalBg:    NSColor(hex: 0xFAF9F5),
        terminalFg:    NSColor(hex: 0x1B1714),
        ansiHex: [
            0x1B1714, 0xC4453A, 0x3D8B53, 0xA68932,
            0x4A7FB5, 0x8E6B8A, 0x4E97A8, 0xE8E4DC,
            0x6B6560, 0xD6665C, 0x5AAF6E, 0xC4A84E,
            0x6B9FD4, 0xAE8BA8, 0x6EB8C8, 0xFAF9F5,
        ]
    )

    // Dark mode
    static let midnight = ColorTheme(
        id: "midnight", name: "Midnight",
        chrome:        NSColor(hex: 0x1C1C1E),
        surface:       NSColor(hex: 0x2C2C2E),
        hover:         NSColor(hex: 0x3A3A3C),
        divider:       NSColor(hex: 0x38383A),
        borderRest:    NSColor(hex: 0x48484A),
        borderFocus:   NSColor(hex: 0x636366),
        textPrimary:   NSColor(hex: 0xF2F2F7),
        textSecondary: NSColor(hex: 0xAEAEB2),
        textTertiary:  NSColor(hex: 0x636366),
        terminalBg:    NSColor(hex: 0x1C1C1E),
        terminalFg:    NSColor(hex: 0xF2F2F7),
        ansiHex: [
            0x1C1C1E, 0xFF453A, 0x30D158, 0xFFD60A,
            0x0A84FF, 0xBF5AF2, 0x64D2FF, 0xE5E5EA,
            0x636366, 0xFF6961, 0x5AD85C, 0xFFE066,
            0x409CFF, 0xDA8FFF, 0x7CD4FC, 0xF2F2F7,
        ]
    )

    // Cool grey
    static let overcast = ColorTheme(
        id: "overcast", name: "Overcast",
        chrome:        NSColor(hex: 0xE8EAED),
        surface:       NSColor(hex: 0xF4F5F7),
        hover:         NSColor(hex: 0xDFE1E5),
        divider:       NSColor(hex: 0xD4D6DB),
        borderRest:    NSColor(hex: 0xCDD0D5),
        borderFocus:   NSColor(hex: 0xB0B4BC),
        textPrimary:   NSColor(hex: 0x1A1C20),
        textSecondary: NSColor(hex: 0x5F6368),
        textTertiary:  NSColor(hex: 0x9AA0A6),
        terminalBg:    NSColor(hex: 0xF4F5F7),
        terminalFg:    NSColor(hex: 0x1A1C20),
        ansiHex: [
            0x1A1C20, 0xDC3545, 0x28A745, 0xD4A017,
            0x0D6EFD, 0x8B5CF6, 0x0DCAF0, 0xDFE1E5,
            0x5F6368, 0xEA6875, 0x4ECB71, 0xE8BD3E,
            0x3D8BFD, 0xA78BFA, 0x3DD5F3, 0xF4F5F7,
        ]
    )
}

// MARK: - Theme (static accessors backed by active theme)

struct Theme {
    private static var _active: ColorTheme = Themes.flock

    static var active: ColorTheme {
        get { _active }
        set {
            _active = newValue
            NotificationCenter.default.post(name: themeDidChange, object: nil)
        }
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

    // Text
    static var textPrimary:   NSColor { active.textPrimary }
    static var textSecondary: NSColor { active.textSecondary }
    static var textTertiary:  NSColor { active.textTertiary }

    // Terminal
    static var terminalBg: NSColor { active.terminalBg }
    static var terminalFg: NSColor { active.terminalFg }

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

    static let tabBarHeight:  CGFloat = 44
    static let statusHeight:  CGFloat = 28
    static let paneGap:       CGFloat = Space.md
    static let panePadding:   CGFloat = Space.md
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

    // MARK: - Typography

    enum Typo {
        static let brand      = NSFont.systemFont(ofSize: 14, weight: .semibold)
        static let tabActive  = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        static let tabRest    = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        static let button     = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        static let status     = NSFont.systemFont(ofSize: 11, weight: .regular)
        static let brandKern: CGFloat = 1.2
    }

    // MARK: - Shadows

    struct ShadowConfig {
        let opacity: Float
        let radius: CGFloat
        let offset: CGSize
    }

    enum Shadow {
        enum Rest {
            static let contact = ShadowConfig(opacity: 0.04, radius: 2, offset: CGSize(width: 0, height: 0.5))
            static let ambient = ShadowConfig(opacity: 0.03, radius: 16, offset: CGSize(width: 0, height: 4))
        }
        enum Focus {
            static let contact = ShadowConfig(opacity: 0.08, radius: 3, offset: CGSize(width: 0, height: 1))
            static let ambient = ShadowConfig(opacity: 0.06, radius: 20, offset: CGSize(width: 0, height: 8))
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
}
