import AppKit

extension NSColor {
    /// Create a color from a hex string like "#3b63fb" or "3b63fb" (optionally with alpha "#rrggbbaa").
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b, a: CGFloat
        switch s.count {
        case 8:
            r = CGFloat((value & 0xFF000000) >> 24) / 255
            g = CGFloat((value & 0x00FF0000) >> 16) / 255
            b = CGFloat((value & 0x0000FF00) >> 8) / 255
            a = CGFloat(value & 0x000000FF) / 255
        default: // 6 (and fallback)
            r = CGFloat((value & 0xFF0000) >> 16) / 255
            g = CGFloat((value & 0x00FF00) >> 8) / 255
            b = CGFloat(value & 0x0000FF) / 255
            a = 1.0
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    func withAlpha(_ a: CGFloat) -> NSColor {
        return self.withAlphaComponent(a)
    }
}

enum ThemeMode {
    case light
    case dark
    case system
}

struct AccentOption {
    let id: String
    let labelX: String
    let labelW: String
    let dotColor: NSColor
    let lightAccent: NSColor
    let lightBg: NSColor
    let lightHover: NSColor
    let darkAccent: NSColor
    let darkBg: NSColor
    let darkHover: NSColor

    static let all: [AccentOption] = [
        AccentOption(id: "blue",    labelX: "Blue",    labelW: "蓝",
                     dotColor:    NSColor(hex: "#4b75ff"),
                     lightAccent: NSColor(hex: "#3b63fb"), lightBg: NSColor(hex: "#3b63fb"), lightHover: NSColor(hex: "#274dea"),
                     darkAccent:  NSColor(hex: "#5681ff"), darkBg:  NSColor(hex: "#4069fd"), darkHover:  NSColor(hex: "#345bf8")),
        AccentOption(id: "indigo",  labelX: "Indigo",  labelW: "靛蓝",
                     dotColor:    NSColor(hex: "#7a6afd"),
                     lightAccent: NSColor(hex: "#7155fa"), lightBg: NSColor(hex: "#7155fa"), lightHover: NSColor(hex: "#6338ee"),
                     darkAccent:  NSColor(hex: "#8077fe"), darkBg:  NSColor(hex: "#745bfc"), darkHover:  NSColor(hex: "#6d4bf8")),
        AccentOption(id: "purple",  labelX: "Violet",  labelW: "紫",
                     dotColor:    NSColor(hex: "#b272eb"),
                     lightAccent: NSColor(hex: "#9a47e2"), lightBg: NSColor(hex: "#9a47e2"), lightHover: NSColor(hex: "#8628d9"),
                     darkAccent:  NSColor(hex: "#ad69e9"), darkBg:  NSColor(hex: "#9d4ee4"), darkHover:  NSColor(hex: "#943ee0")),
        AccentOption(id: "magenta", labelX: "Magenta", labelW: "品红",
                     dotColor:    NSColor(hex: "#f02d6e"),
                     lightAccent: NSColor(hex: "#d92361"), lightBg: NSColor(hex: "#d92361"), lightHover: NSColor(hex: "#ba1650"),
                     darkAccent:  NSColor(hex: "#ff3377"), darkBg:  NSColor(hex: "#e02665"), darkHover:  NSColor(hex: "#cf1f5c")),
        AccentOption(id: "green",   labelX: "Green",   labelW: "绿",
                     dotColor:    NSColor(hex: "#0ba45d"),
                     lightAccent: NSColor(hex: "#05834e"), lightBg: NSColor(hex: "#05834e"), lightHover: NSColor(hex: "#036e45"),
                     darkAccent:  NSColor(hex: "#099d59"), darkBg:  NSColor(hex: "#068850"), darkHover:  NSColor(hex: "#047c4b")),
        AccentOption(id: "orange",  labelX: "Orange",  labelW: "橙",
                     dotColor:    NSColor(hex: "#e86a00"),
                     lightAccent: NSColor(hex: "#c24e00"), lightBg: NSColor(hex: "#c24e00"), lightHover: NSColor(hex: "#a73e00"),
                     darkAccent:  NSColor(hex: "#e06400"), darkBg:  NSColor(hex: "#c75200"), darkHover:  NSColor(hex: "#b94900")),
    ]

    static func find(_ id: String) -> AccentOption { all.first(where: { $0.id == id }) ?? all[0] }
}

/// Resolved Spectrum 2 semantic + raw tokens for one appearance.
struct Theme {
    let mode: ThemeMode
    var isDark: Bool { mode == .dark }

    // raw grays (needed directly in several places)
    let gray25, gray50, gray75, gray100, gray200, gray300, gray400, gray500, gray600, gray700, gray800, gray900, gray1000: NSColor

    // semantic backgrounds
    let bgBase, bgLayer1, bgLayer2, bgElevated, bgPasteboard: NSColor
    // semantic foregrounds
    let fgHeading, fgTitle, fgBody, fgNeutral, fgSubdued, fgDisabled: NSColor
    // borders
    let borderDefault, borderStrong, borderDisabled: NSColor
    // accent & status
    let accent, accentBg, accentBgHover, accentBgDown: NSColor
    let negative, negativeBg, positive, positiveBg, noticeBg, informative, focusRing: NSColor
    // action-bar accent colors
    let green700, magenta800: NSColor

    static let light: Theme = {
        let g25 = NSColor(hex: "#ffffff")
        let g50 = NSColor(hex: "#f8f8f8")
        let g75 = NSColor(hex: "#f3f3f3")
        let g100 = NSColor(hex: "#e9e9e9")
        let g200 = NSColor(hex: "#e1e1e1")
        let g300 = NSColor(hex: "#dadada")
        let g400 = NSColor(hex: "#c6c6c6")
        let g500 = NSColor(hex: "#8f8f8f")
        let g600 = NSColor(hex: "#717171")
        let g700 = NSColor(hex: "#505050")
        let g800 = NSColor(hex: "#292929")
        let g900 = NSColor(hex: "#131313")
        let g1000 = NSColor(hex: "#000000")
        return Theme(
            mode: .light,
            gray25: g25, gray50: g50, gray75: g75, gray100: g100, gray200: g200, gray300: g300,
            gray400: g400, gray500: g500, gray600: g600, gray700: g700, gray800: g800, gray900: g900, gray1000: g1000,
            bgBase: g25, bgLayer1: g50, bgLayer2: g25, bgElevated: g25, bgPasteboard: g100,
            fgHeading: g900, fgTitle: g900, fgBody: g800, fgNeutral: g800, fgSubdued: g700, fgDisabled: g400,
            borderDefault: g300, borderStrong: g800, borderDisabled: g300,
            accent: NSColor(hex: "#3b63fb"),        // blue-900
            accentBg: NSColor(hex: "#3b63fb"),       // blue-900
            accentBgHover: NSColor(hex: "#274dea"),  // blue-1000
            accentBgDown: NSColor(hex: "#274dea"),
            negative: NSColor(hex: "#d73220"),       // red-900
            negativeBg: NSColor(hex: "#d73220"),
            positive: NSColor(hex: "#05834e"),       // green-900
            positiveBg: NSColor(hex: "#05834e"),
            noticeBg: NSColor(hex: "#fc7d00"),       // orange-600
            informative: NSColor(hex: "#3b63fb"),
            focusRing: NSColor(hex: "#4b75ff"),      // blue-800
            green700: NSColor(hex: "#0ba45d"),
            magenta800: NSColor(hex: "#f02d6e")
        )
    }()

    static let dark: Theme = {
        let g25 = NSColor(hex: "#111111")
        let g50 = NSColor(hex: "#1b1b1b")
        let g75 = NSColor(hex: "#222222")
        let g100 = NSColor(hex: "#2c2c2c")
        let g200 = NSColor(hex: "#323232")
        let g300 = NSColor(hex: "#393939")
        let g400 = NSColor(hex: "#444444")
        let g500 = NSColor(hex: "#6d6d6d")
        let g600 = NSColor(hex: "#8a8a8a")
        let g700 = NSColor(hex: "#afafaf")
        let g800 = NSColor(hex: "#dbdbdb")
        let g900 = NSColor(hex: "#f2f2f2")
        let g1000 = NSColor(hex: "#ffffff")
        return Theme(
            mode: .dark,
            gray25: g25, gray50: g50, gray75: g75, gray100: g100, gray200: g200, gray300: g300,
            gray400: g400, gray500: g500, gray600: g600, gray700: g700, gray800: g800, gray900: g900, gray1000: g1000,
            bgBase: g25, bgLayer1: g50, bgLayer2: g75, bgElevated: g75, bgPasteboard: g25,
            fgHeading: g900, fgTitle: g900, fgBody: g800, fgNeutral: g800, fgSubdued: g700, fgDisabled: g400,
            borderDefault: g300, borderStrong: g800, borderDisabled: g300,
            accent: NSColor(hex: "#5681ff"),         // blue-900 (dark)
            accentBg: NSColor(hex: "#4069fd"),        // blue-800 (dark)
            accentBgHover: NSColor(hex: "#345bf8"),   // blue-700 (dark)
            accentBgDown: NSColor(hex: "#345bf8"),
            negative: NSColor(hex: "#fc432e"),        // red-900 (dark)
            negativeBg: NSColor(hex: "#df3422"),      // red-800 (dark)
            positive: NSColor(hex: "#099d59"),        // green-900 (dark)
            positiveBg: NSColor(hex: "#068850"),      // green-800 (dark)
            noticeBg: NSColor(hex: "#e06400"),        // orange-900 (dark)
            informative: NSColor(hex: "#4069fd"),
            focusRing: NSColor(hex: "#4069fd"),
            green700: NSColor(hex: "#047c4b"),
            magenta800: NSColor(hex: "#e02665")
        )
    }()

    static func forMode(_ mode: ThemeMode, accent: String = "blue") -> Theme {
        let dark: Bool
        switch mode {
        case .dark: dark = true
        case .light: dark = false
        case .system:
            dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        var base = dark ? Theme.dark : Theme.light
        if accent != "blue" {
            let opt = AccentOption.find(accent)
            base.applyAccent(opt, dark: dark)
        }
        return base
    }

    mutating func applyAccent(_ opt: AccentOption, dark: Bool) {
        // NOTE: Theme is a struct – we mutate a copy
        if dark {
            // accent, accentBg, accentBgHover, accentBgDown
            self = Theme(mode: mode,
                gray25: gray25, gray50: gray50, gray75: gray75, gray100: gray100,
                gray200: gray200, gray300: gray300, gray400: gray400, gray500: gray500,
                gray600: gray600, gray700: gray700, gray800: gray800, gray900: gray900,
                gray1000: gray1000,
                bgBase: bgBase, bgLayer1: bgLayer1, bgLayer2: bgLayer2,
                bgElevated: bgElevated, bgPasteboard: bgPasteboard,
                fgHeading: fgHeading, fgTitle: fgTitle, fgBody: fgBody,
                fgNeutral: fgNeutral, fgSubdued: fgSubdued, fgDisabled: fgDisabled,
                borderDefault: borderDefault, borderStrong: borderStrong, borderDisabled: borderDisabled,
                accent: opt.darkAccent, accentBg: opt.darkBg,
                accentBgHover: opt.darkHover, accentBgDown: opt.darkHover,
                negative: negative, negativeBg: negativeBg, positive: positive,
                positiveBg: positiveBg, noticeBg: noticeBg, informative: opt.darkAccent,
                focusRing: opt.darkBg, green700: green700, magenta800: magenta800)
        } else {
            self = Theme(mode: mode,
                gray25: gray25, gray50: gray50, gray75: gray75, gray100: gray100,
                gray200: gray200, gray300: gray300, gray400: gray400, gray500: gray500,
                gray600: gray600, gray700: gray700, gray800: gray800, gray900: gray900,
                gray1000: gray1000,
                bgBase: bgBase, bgLayer1: bgLayer1, bgLayer2: bgLayer2,
                bgElevated: bgElevated, bgPasteboard: bgPasteboard,
                fgHeading: fgHeading, fgTitle: fgTitle, fgBody: fgBody,
                fgNeutral: fgNeutral, fgSubdued: fgSubdued, fgDisabled: fgDisabled,
                borderDefault: borderDefault, borderStrong: borderStrong, borderDisabled: borderDisabled,
                accent: opt.lightAccent, accentBg: opt.lightBg,
                accentBgHover: opt.lightHover, accentBgDown: opt.lightHover,
                negative: negative, negativeBg: negativeBg, positive: positive,
                positiveBg: positiveBg, noticeBg: noticeBg, informative: opt.lightAccent,
                focusRing: opt.lightBg, green700: green700, magenta800: magenta800)
        }
    }

    /// Resolve a Spectrum scale token like "indigo-700" to a color for the current mode.
    /// Used for avatar / author accent colors that flip with the theme.
    func scaleColor(_ token: String) -> NSColor {
        let pair = Theme.scale[token]
        if let pair { return NSColor(hex: isDark ? pair.1 : pair.0) }
        return fgSubdued
    }

    /// Strip a CSS `var(--token)` / `--token` wrapper, returning the bare token.
    static func stripToken(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("var(") && s.hasSuffix(")") {
            s = String(s.dropFirst(4).dropLast())
        }
        if s.hasPrefix("--") { s = String(s.dropFirst(2)) }
        return s
    }

    // (lightHex, darkHex) for the scale steps referenced by mock data.
    private static let scale: [String: (String, String)] = [
        "indigo-700": ("#8480fe", "#6d4bf8"),
        "seafoam-700": ("#0ba286", "#067a67"),
        "magenta-700": ("#ff4885", "#cf1f5c"),
        "magenta-800": ("#f02d6e", "#e02665"),
        "orange-700": ("#e86a00", "#b94900"),
        "orange-800": ("#d86600", "#a84300"),
        "seafoam-800": ("#0a9384", "#067a67"),
        "purple-700": ("#b272eb", "#943ee0"),
        "cyan-800": ("#1286cd", "#0d7dba"),
        "blue-900": ("#3b63fb", "#5681ff"),
        "green-700": ("#0ba45d", "#047c4b"),
        "green-800": ("#079355", "#068850"),
        "green-900": ("#05834e", "#099d59"),
        "orange-900": ("#c24e00", "#e06400"),
        "red-900": ("#d73220", "#fc432e"),
        "celery-800": ("#489014", "#428612"),
        "turquoise-800": ("#0a8d99", "#09838e"),
        "red-800": ("#f03823", "#df3422"),
        // additional steps referenced by notification actor pools
        "pink-700": ("#ed5aa0", "#d83b8a"),
        "brown-700": ("#a3795a", "#8a6446"),
        "cyan-700": ("#1aa0d6", "#0e8fc4"),
        "indigo-800": ("#6f5bf5", "#5b46e8"),
        "purple-800": ("#9a4ce0", "#883dd2"),
    ]
}

/// Any view that wants to be re-colored when the theme changes.
protocol Themeable: AnyObject {
    func applyTheme(_ theme: Theme)
}

/// Central theme holder + recursive recolor walker.
final class ThemeManager {
    static let shared = ThemeManager()
    private(set) var theme: Theme = .dark
    private(set) var mode: ThemeMode = .dark
    private(set) var accentId: String = "blue"

    private static let modeKey = "perch.appearanceMode"

    /// The user's persisted Appearance setting, or `.system` on first launch
    /// (no saved value) so Perch follows macOS out of the box.
    static func savedMode() -> ThemeMode {
        switch UserDefaults.standard.string(forKey: modeKey) {
        case "light": return .light
        case "dark": return .dark
        default: return .system
        }
    }

    private func string(for mode: ThemeMode) -> String {
        switch mode { case .light: return "light"; case .dark: return "dark"; case .system: return "system" }
    }

    /// Drive the native window chrome (traffic lights, menus) to match the theme.
    private func applyAppAppearance(_ mode: ThemeMode) {
        switch mode {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }

    func setMode(_ mode: ThemeMode, root: NSView?, persist: Bool = true) {
        self.mode = mode
        if persist { UserDefaults.standard.set(string(for: mode), forKey: ThemeManager.modeKey) }
        applyAppAppearance(mode)
        theme = Theme.forMode(mode, accent: accentId)
        if let root { recolor(root) }
    }

    func setAccent(_ id: String, root: NSView?) {
        accentId = id
        theme = Theme.forMode(mode, accent: id)
        if let root { recolor(root) }
    }

    func recolor(_ view: NSView) {
        (view as? Themeable)?.applyTheme(theme)
        for sub in view.subviews { recolor(sub) }
    }
}
